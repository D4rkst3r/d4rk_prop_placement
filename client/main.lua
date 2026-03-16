--[[
    ╔══════════════════════════════════════════════════════╗
    ║           prop_placement – client/main.lua           ║
    ║   Client-side Entities mit CreateObjectNoOffset      ║
    ╚══════════════════════════════════════════════════════╝

    ROOT CAUSE:
    ────────────
    syncAll feuert während des Ladebildschirms. Props werden
    erstellt (DoesEntityExist = true), aber das Framework / die
    Engine wirft beim playerSpawned-Event einen Teil der Entities
    raus. Der Handle bleibt "gültig" – der Renderer zeigt nichts.

    FIXES:
    ──────
    1. Sync erst NACH playerSpawned auslösen, nicht beim
       Ressourcenstart (onClientResourceStart nur als Fallback
       für späte Resource-Starts wenn Spieler bereits in der Welt).
    2. RequestCollisionAtCoord vor jedem Spawn – stellt sicher
       dass die Game-Welt an dieser Position geladen ist.
    3. Post-Spawn-Check: nach dem Spawnen prüfen ob Alpha & LOD
       korrekt gesetzt sind (detektiert "Zombie"-Entities).
    4. Keepalive-Thread erkennt von der Engine gelöschte Entities.
    5. NetworkSetEntityInvisibleToNetwork entfernt (verwirrt
       Network-Manager bei lokalen Entities).
]]

local placedProps       = {}
local allPropData       = {}
local propGrid          = {}
local hasSynced         = false
local syncInProgress    = false
local isSyncing         = false
local streamStillFrames = 0
local forceStreamCheck  = false
-- FIX: Flag das anzeigt ob playerSpawned bereits gefeuert hat
local playerHasSpawned  = false

-- ─────────────────────────────────────────────────────────
-- Hilfsfunktionen
-- ─────────────────────────────────────────────────────────

local function DebugLog(msg)
    if Config.Debug then print('[prop_placement][CLIENT] ' .. tostring(msg)) end
end

local function LoadModel(model)
    if HasModelLoaded(model) then return true end
    RequestModel(model)
    local t = 0
    while not HasModelLoaded(model) do
        Wait(100); t = t + 1
        if t > 80 then return false end
    end
    return true
end

-- ─────────────────────────────────────────────────────────
-- Grid-System
-- ─────────────────────────────────────────────────────────

local function GetGridCell(x, y)
    local size = Config.Grid.GridSize
    return math.floor(x / size), math.floor(y / size)
end

local function GetGridKey(cx, cy) return cx .. ':' .. cy end

local function AddToGrid(propId, x, y)
    local key = GetGridKey(GetGridCell(x, y))
    if not propGrid[key] then propGrid[key] = {} end
    propGrid[key][propId] = true
end

local function RemoveFromGrid(propId, x, y)
    local key = GetGridKey(GetGridCell(x, y))
    if propGrid[key] then propGrid[key][propId] = nil end
end

local function GetNearbyPropIds(x, y)
    local cx, cy = GetGridCell(x, y)
    local nearby = {}
    for dx = -1, 1 do
        for dy = -1, 1 do
            local key = GetGridKey(cx + dx, cy + dy)
            if propGrid[key] then
                for propId in pairs(propGrid[key]) do nearby[propId] = true end
            end
        end
    end
    return nearby
end

-- ─────────────────────────────────────────────────────────
-- Model-Preloading
-- ─────────────────────────────────────────────────────────

if Config.Preloading.Enabled then
    CreateThread(function()
        Wait(Config.Preloading.Delay)
        local count = 0
        for _, cfg in pairs(Config.Props) do
            local model = GetHashKey(cfg.model)
            if not HasModelLoaded(model) then
                RequestModel(model)
                local t = 0
                while not HasModelLoaded(model) and t < 50 do
                    Wait(100); t = t + 1
                end
                SetModelAsNoLongerNeeded(model)
                count = count + 1
            end
        end
        DebugLog(('Preloading: %d Modelle vorgeladen.'):format(count))
    end)
end

-- ─────────────────────────────────────────────────────────
-- ox_target registrieren
-- ─────────────────────────────────────────────────────────

local function RegisterPropTarget(propId, entity, propData)
    local options = {
        {
            label    = 'Prop entfernen',
            icon     = 'fas fa-trash-alt',
            name     = 'pp_remove_' .. propId,
            onSelect = function()
                TriggerServerEvent('prop_placement:remove', propId)
            end,
        },
    }
    if Config.Debug then
        table.insert(options, {
            label    = 'Prop-Info [Debug]',
            icon     = 'fas fa-info-circle',
            name     = 'pp_info_' .. propId,
            onSelect = function()
                lib.notify({
                    title       = 'Prop #' .. propId,
                    description = ('Item: %s\nModel: %s\nBesitzer: %s'):format(
                        propData.itemName, propData.model, propData.ownerIdentifier or '?'),
                    type        = 'inform',
                    duration    = 6000,
                })
            end,
        })
    end
    exports.ox_target:addLocalEntity(entity, options)
end

-- ─────────────────────────────────────────────────────────
-- Prop spawnen / entfernen
-- ─────────────────────────────────────────────────────────

local function SpawnProp(propData)
    local propId = propData.id

    -- Bereits gespawnt und Entity noch gültig → nichts tun
    if placedProps[propId] and DoesEntityExist(placedProps[propId]) then return end

    -- Alter ungültiger Handle → aufräumen
    if placedProps[propId] then
        pcall(function() exports.ox_target:removeLocalEntity(placedProps[propId]) end)
        placedProps[propId] = nil
    end

    local model = GetHashKey(propData.model)
    if not LoadModel(model) then
        DebugLog('Modell nicht ladbar: ' .. propData.model); return
    end

    -- FIX: Collision für diese Koordinaten anfordern bevor die Entity erstellt
    -- wird. Ohne das kann die Engine eine "Zombie"-Entity erstellen die existiert
    -- aber nicht gerendert wird weil die Welt an dieser Stelle noch nicht geladen ist.
    RequestCollisionAtCoord(propData.x, propData.y, propData.z)
    local colWait = 0
    while not HasCollisionLoadedAroundEntity(PlayerPedId()) and colWait < 2000 do
        Wait(100); colWait = colWait + 100
    end

    local entity = CreateObjectNoOffset(model,
        propData.x, propData.y, propData.z,
        false, -- isNetwork: false = lokale Entity, nur für diesen Client
        true,  -- netMissionEntity: true = am Script-Host gepinnt, verhindert
        -- dass die Engine die Entity als "orphaned" betrachtet und löscht
        false) -- doorFlag

    if not DoesEntityExist(entity) then
        DebugLog('Entity nicht erstellt: #' .. propId)
        SetModelAsNoLongerNeeded(model)
        return
    end

    -- Entity dauerhaft halten
    SetEntityAsMissionEntity(entity, true, true)
    SetEntityRotation(entity, 0.0, 0.0, propData.rotation, 2, true)
    FreezeEntityPosition(entity, true)
    SetEntityCollision(entity, true, true)
    SetEntityInvincible(entity, true)
    SetEntityCanBeDamaged(entity, false)
    SetEntityAlpha(entity, 255, false)
    SetEntityLodDist(entity, 1000)

    -- FIX: NetworkSetEntityInvisibleToNetwork ENTFERNT –
    -- auf lokalen Entities (isNetwork=false) kann das den
    -- Network-Manager verwirren und die Entity sofort löschen.

    -- Post-Spawn-Check: Alpha prüfen um Zombie-Entities zu erkennen
    Wait(0) -- einen Frame warten damit die Engine die Entity verarbeitet
    local alpha = GetEntityAlpha(entity)
    if alpha ~= 255 then
        -- Engine hat Alpha überschrieben → Entity ist im falschen Zustand
        -- Nochmals setzen
        SetEntityAlpha(entity, 255, false)
        DebugLog(('Prop #%d: Alpha-Fix angewendet (war %d)'):format(propId, alpha))
    end

    placedProps[propId] = entity
    allPropData[propId] = propData
    AddToGrid(propId, propData.x, propData.y)
    RegisterPropTarget(propId, entity, propData)
    SetModelAsNoLongerNeeded(model)

    DebugLog(('Prop #%d gespawnt bei %.1f / %.1f / %.1f'):format(
        propId, propData.x, propData.y, propData.z))
end

local function DespawnProp(propId)
    local entity = placedProps[propId]
    placedProps[propId] = nil
    if entity and DoesEntityExist(entity) then
        exports.ox_target:removeLocalEntity(entity)
        SetEntityInvincible(entity, false)
        SetEntityCanBeDamaged(entity, true)
        FreezeEntityPosition(entity, false)
        SetEntityAsMissionEntity(entity, false, false)
        DeleteEntity(entity)
        DebugLog('Prop #' .. propId .. ' despawnt.')
    end
end

local function ClearAllLocalProps()
    for id, entity in pairs(placedProps) do
        if DoesEntityExist(entity) then
            exports.ox_target:removeLocalEntity(entity)
            SetEntityInvincible(entity, false)
            SetEntityCanBeDamaged(entity, true)
            FreezeEntityPosition(entity, false)
            SetEntityAsMissionEntity(entity, false, false)
            DeleteEntity(entity)
        end
    end
    placedProps = {}
    allPropData = {}
    propGrid    = {}
end

-- ─────────────────────────────────────────────────────────
-- Keepalive-Thread
-- ─────────────────────────────────────────────────────────

CreateThread(function()
    while true do
        Wait(3000)
        if not isSyncing then
            local count = 0
            for propId, entity in pairs(placedProps) do
                if not DoesEntityExist(entity) then
                    placedProps[propId] = nil
                    count = count + 1
                    DebugLog(('Keepalive: Prop #%d fehlt, wird neu erstellt'):format(propId))
                end
            end
            if count > 0 then
                forceStreamCheck = true
                DebugLog(('Keepalive: %d Props neu eingeplant'):format(count))
            end
        end
    end
end)

-- ─────────────────────────────────────────────────────────
-- Streaming-System
-- ─────────────────────────────────────────────────────────

if Config.Streaming.Enabled then
    CreateThread(function()
        local lastPos       = vector3(0, 0, 0)
        local checkInterval = Config.Streaming.CheckInterval

        while true do
            if forceStreamCheck then
                forceStreamCheck = false
                checkInterval    = Config.Streaming.CheckInterval
                Wait(100)
            else
                Wait(checkInterval)
            end

            local playerPos = GetEntityCoords(PlayerPedId())
            local px, py    = playerPos.x, playerPos.y
            local moved     = #(vector3(px, py, playerPos.z) - lastPos)

            if moved < 2.0 then
                streamStillFrames = streamStillFrames + 1
                checkInterval     = math.min(10000, Config.Streaming.CheckInterval + streamStillFrames * 500)
            else
                streamStillFrames = 0
                checkInterval     = Config.Streaming.CheckInterval
            end
            lastPos = vector3(px, py, playerPos.z)

            local toCheck = {}
            if Config.Grid.Enabled then
                for propId in pairs(GetNearbyPropIds(px, py)) do toCheck[propId] = true end
            end
            for propId in pairs(placedProps) do toCheck[propId] = true end
            if not Config.Grid.Enabled then
                for propId in pairs(allPropData) do toCheck[propId] = true end
            end

            if not isSyncing then
                for propId in pairs(toCheck) do
                    local pd = allPropData[propId]
                    if pd then
                        local dist    = #(vector3(px, py, playerPos.z) - vector3(pd.x, pd.y, pd.z))
                        local entity  = placedProps[propId]
                        local spawned = entity and DoesEntityExist(entity)
                        if not spawned and dist <= Config.Streaming.SpawnRadius then
                            SpawnProp(pd)
                        elseif spawned and dist > Config.Streaming.DespawnRadius then
                            DespawnProp(propId)
                        end
                    end
                end
            end
        end
    end)
end

-- ─────────────────────────────────────────────────────────
-- Net Events
-- ─────────────────────────────────────────────────────────

AddEventHandler('ox_inventory:closedInventory', function()
    if IsCurrentlyPlacing() then
        CancelPlacementExternal()
        lib.notify({ title = 'Abgebrochen', description = 'Platzierung abgebrochen.', type = 'inform', duration = 2000 })
    end
end)

RegisterNetEvent('prop_placement:syncAll', function(propList)
    DebugLog('syncAll empfangen: ' .. #propList .. ' Props')
    hasSynced = true
    isSyncing = true
    ClearAllLocalProps()

    for _, propData in ipairs(propList) do
        allPropData[propData.id] = propData
        if Config.Grid.Enabled then AddToGrid(propData.id, propData.x, propData.y) end
    end

    CreateThread(function()
        -- FIX: Warten bis playerSpawned gefeuert hat UND die Welt geladen ist.
        -- Props die vor playerSpawned erstellt werden können vom Framework
        -- beim Spawn-Event gelöscht werden.
        local waitTime = 0
        while not playerHasSpawned and waitTime < 15000 do
            Wait(200); waitTime = waitTime + 200
        end

        -- Zusätzlich warten bis gültige Position vorhanden
        local playerPos = GetEntityCoords(PlayerPedId())
        waitTime = 0
        while #playerPos < 1.0 and waitTime < 8000 do
            Wait(300); waitTime = waitTime + 300
            playerPos = GetEntityCoords(PlayerPedId())
        end

        -- Collision sicherstellen
        local ped = PlayerPedId()
        waitTime = 0
        while not HasCollisionLoadedAroundEntity(ped) and waitTime < 5000 do
            Wait(200); waitTime = waitTime + 200; ped = PlayerPedId()
        end

        local spawnCount = 0
        local skipCount  = 0

        for _, propData in ipairs(propList) do
            playerPos = GetEntityCoords(PlayerPedId())
            local dist = #(playerPos - vector3(propData.x, propData.y, propData.z))
            if not Config.Streaming.Enabled or dist <= Config.Streaming.SpawnRadius then
                SpawnProp(propData)
                spawnCount = spawnCount + 1
                Wait(10)
            else
                skipCount = skipCount + 1
            end
        end

        streamStillFrames = 0
        if skipCount > 0 then forceStreamCheck = true end
        isSyncing = false

        DebugLog(('syncAll abgeschlossen: %d gespawnt, %d per Streaming/Retry'):format(spawnCount, skipCount))
    end)
end)

RegisterNetEvent('prop_placement:propPlaced', function(propData)
    DebugLog('Neuer Prop: #' .. propData.id)
    allPropData[propData.id] = propData
    if Config.Grid.Enabled then AddToGrid(propData.id, propData.x, propData.y) end

    local playerPos = GetEntityCoords(PlayerPedId())
    local dist      = #(playerPos - vector3(propData.x, propData.y, propData.z))
    if not Config.Streaming.Enabled or dist <= Config.Streaming.SpawnRadius then
        SpawnProp(propData)
    end
end)

RegisterNetEvent('prop_placement:propRemoved', function(propId)
    DebugLog('Prop #' .. propId .. ' entfernt')
    local pd = allPropData[propId]
    if pd and Config.Grid.Enabled then RemoveFromGrid(propId, pd.x, pd.y) end
    allPropData[propId] = nil
    DespawnProp(propId)
end)

RegisterNetEvent('prop_placement:startPlacing', function(itemName)
    local propConfig = Config.Props[itemName]
    if not propConfig then
        lib.notify({ title = 'Fehler', description = 'Unbekannter Prop-Typ: ' .. itemName, type = 'error' }); return
    end
    StartPropPlacement(itemName, propConfig)
end)

RegisterNetEvent('prop_placement:receivePropList', function(list, filterName)
    if #list == 0 then
        lib.notify({ title = 'Prop-Liste', description = 'Keine Props gefunden.', type = 'inform' }); return
    end
    local options = {}
    table.sort(list, function(a, b) return a.id < b.id end)
    for _, prop in ipairs(list) do
        local shortOwner   = prop.ownerIdentifier:match('license:(.+)$') or prop.ownerIdentifier
        shortOwner         = shortOwner:sub(1, 12) .. '...'
        local capturedProp = prop
        table.insert(options, {
            title       = ('#%d – %s'):format(capturedProp.id, capturedProp.itemName),
            description = ('Pos: %.1f / %.1f / %.1f\nBesitzer: %s'):format(
                capturedProp.x, capturedProp.y, capturedProp.z, shortOwner),
            onSelect    = function()
                CreateThread(function()
                    local confirmed = lib.alertDialog({
                        header   = 'Prop #' .. capturedProp.id .. ' entfernen?',
                        content  = capturedProp.itemName .. ' dauerhaft löschen?',
                        centered = true,
                        cancel   = true,
                    })
                    if confirmed == 'confirm' then
                        TriggerServerEvent('prop_placement:remove', capturedProp.id)
                    end
                end)
            end,
        })
    end
    lib.registerContext({
        id      = 'prop_placement_list',
        title   = ('🧱 Props (%d)%s'):format(#list, filterName and ' – ' .. filterName or ''),
        options = options,
    })
    lib.showContext('prop_placement_list')
end)

RegisterNetEvent('prop_placement:openAdminMenu', function()
    local categories = {}
    local catItems   = {}
    for itemName, cfg in pairs(Config.Props) do
        local cat = cfg.category or 'Sonstiges'
        if not catItems[cat] then
            catItems[cat] = {}; table.insert(categories, cat)
        end
        table.insert(catItems[cat], { itemName = itemName, cfg = cfg })
    end
    table.sort(categories)

    local options = {}
    for _, cat in ipairs(categories) do
        local items   = catItems[cat]
        local catName = cat
        table.sort(items, function(a, b) return a.cfg.label < b.cfg.label end)
        table.insert(options, {
            title       = ('📦 %s (%d)'):format(catName, #items),
            description = 'Kategorie öffnen',
            arrow       = true,
            onSelect    = function()
                local subOptions = {}
                for _, entry in ipairs(items) do
                    local itemName = entry.itemName
                    local cfg      = entry.cfg
                    local flags    = (cfg.adminOnly and '🔒 ' or '') .. (cfg.persistent and '💾 ' or '')
                    table.insert(subOptions, {
                        title       = flags .. cfg.label,
                        description = ('Model: %s | %sg'):format(cfg.model, cfg.weight or 1000),
                        onSelect    = function()
                            local input = lib.inputDialog('Prop-Item geben', {
                                { type = 'number', label = 'Server-ID des Spielers', required = true, min = 1 },
                                { type = 'number', label = 'Anzahl',                 default = 1,     min = 1, max = 99 },
                            })
                            if input and input[1] then
                                TriggerServerEvent('prop_placement:adminGive',
                                    tonumber(input[1]), itemName, tonumber(input[2]) or 1)
                            end
                        end,
                    })
                end
                lib.registerContext({
                    id      = 'pp_cat_' .. catName,
                    title   = ('🧱 %s'):format(catName),
                    menu    = 'prop_placement_admin_menu',
                    options = subOptions,
                })
                lib.showContext('pp_cat_' .. catName)
            end,
        })
    end

    table.insert(options, { title = '─────────────────', disabled = true })
    table.insert(options, {
        title       = '📋 Alle Props anzeigen',
        description = 'Liste aller platzierten Props',
        onSelect    = function() TriggerServerEvent('prop_placement:requestPropList', nil) end,
    })
    table.insert(options, {
        title       = '🔍 Props nach Spieler filtern',
        description = 'Props eines bestimmten Spielers',
        onSelect    = function()
            local input = lib.inputDialog('Spieler filtern', {
                { type = 'text', label = 'License-Identifier (license:...)', required = true },
            })
            if input and input[1] and input[1] ~= '' then
                TriggerServerEvent('prop_placement:requestPropList', input[1])
            end
        end,
    })
    table.insert(options, {
        title       = '🗑 Props eines Spielers löschen',
        description = 'Alle Props eines Spielers entfernen',
        onSelect    = function()
            local input = lib.inputDialog('Spieler-Props löschen', {
                { type = 'text', label = 'License-Identifier (license:...)', required = true },
            })
            if input and input[1] and input[1] ~= '' then
                TriggerServerEvent('prop_placement:adminClearPlayer', input[1])
            end
        end,
    })
    table.insert(options, {
        title       = '💥 Alle Props löschen',
        description = 'Entfernt ALLE platzierten Props',
        metadata    = { { label = 'Achtung', value = 'Kann nicht rückgängig gemacht werden!' } },
        onSelect    = function()
            CreateThread(function()
                local confirmed = lib.alertDialog({
                    header   = 'Alle Props löschen?',
                    content  = 'Diese Aktion löscht alle Props dauerhaft.',
                    centered = true,
                    cancel   = true,
                })
                if confirmed == 'confirm' then TriggerServerEvent('prop_placement:adminClearAll') end
            end)
        end,
    })

    lib.registerContext({ id = 'prop_placement_admin_menu', title = '🧱 Prop Placement – Admin', options = options })
    lib.showContext('prop_placement_admin_menu')
end)

-- ─────────────────────────────────────────────────────────
-- Initialisierung
-- ─────────────────────────────────────────────────────────

local function DoSync()
    if hasSynced or syncInProgress then return end
    syncInProgress = true

    local ped      = PlayerPedId()
    local waited   = 0
    repeat
        Wait(500); waited = waited + 500; ped = PlayerPedId()
    until HasCollisionLoadedAroundEntity(ped) or waited >= 10000
    Wait(500)

    hasSynced      = true
    syncInProgress = false
    TriggerServerEvent('prop_placement:requestSync')
end

-- FIX: playerSpawned ist der primäre Trigger.
-- Props werden ERST erstellt nachdem der Spieler vollständig gespawnt
-- ist – so kann das Framework sie nicht mehr beim Spawn-Event löschen.
AddEventHandler('playerSpawned', function()
    playerHasSpawned = true
    CreateThread(function()
        DoSync()
        DebugLog('Sync via playerSpawned')
    end)
end)

-- Fallback: Falls die Ressource gestartet wird während der Spieler
-- bereits in der Welt ist (z.B. Ressource reload via Admin)
AddEventHandler('onClientResourceStart', function(resourceName)
    if resourceName ~= GetCurrentResourceName() then return end
    hasSynced        = false
    syncInProgress   = false
    forceStreamCheck = false
    -- playerHasSpawned NICHT zurücksetzen – der Spieler ist bereits spawned

    CreateThread(function()
        -- Kurz warten damit playerSpawned ggf. noch feuern kann
        Wait(1000)
        if playerHasSpawned then
            -- Spieler ist bereits gespawnt → sofort sync
            DoSync()
            DebugLog('Sync via onClientResourceStart (Spieler bereits gespawnt)')
        else
            -- Spieler noch nicht gespawnt → playerSpawned übernimmt
            DebugLog('onClientResourceStart: warte auf playerSpawned für Sync')
        end
    end)
end)

AddEventHandler('baseevents:onPlayerDied', function() CancelPlacementExternal() end)

AddEventHandler('onClientResourceStop', function(resourceName)
    if resourceName ~= GetCurrentResourceName() then return end
    CancelPlacementExternal()
    ClearAllLocalProps()
end)

-- ─────────────────────────────────────────────────────────
-- Commands
-- ─────────────────────────────────────────────────────────

RegisterCommand('propadmin', function()
    TriggerServerEvent('prop_placement:requestAdminMenu')
end, false)

RegisterCommand('proplist', function()
    TriggerServerEvent('prop_placement:requestPropList', nil)
end, false)

RegisterCommand('propreload', function()
    hasSynced      = false
    syncInProgress = false
    ClearAllLocalProps()
    lib.notify({ title = 'Props werden neu geladen...', type = 'inform', duration = 2000 })
    CreateThread(function()
        Wait(500)
        TriggerServerEvent('prop_placement:reloadProps')
    end)
end, false)

if Config.Debug then
    RegisterCommand('propdebug', function()
        local spawned, total, cells = 0, 0, 0
        for _ in pairs(placedProps) do spawned = spawned + 1 end
        for _ in pairs(allPropData) do total = total + 1 end
        for _ in pairs(propGrid) do cells = cells + 1 end
        lib.notify({
            title       = 'Prop Debug',
            description = ('Gespawnt: %d / Bekannt: %d / Grid-Zellen: %d\nplayerHasSpawned: %s'):format(
                spawned, total, cells, tostring(playerHasSpawned)),
            type        = 'inform',
        })
    end, false)
end
