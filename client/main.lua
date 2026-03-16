--[[
    ╔══════════════════════════════════════════════════════╗
    ║           prop_placement – client/main.lua           ║
    ║   Client-side Spawning nach M-PropV2-Muster          ║
    ╚══════════════════════════════════════════════════════╝
]]

local placedProps       = {} -- [propId] = entity handle
local allPropData       = {} -- [propId] = propData
local propGrid          = {}
local hasSynced         = false
local syncInProgress    = false
local isSyncing         = false
local streamStillFrames = 0
local forceStreamCheck  = false
local playerHasSpawned  = false

-- Editor-Mode (nur für Admins)
local isEditorMode      = false
local isAdmin           = false

-- Decorator einmalig beim Start registrieren
CreateThread(function()
    if not DecorIsRegisteredAsType('PP_PROP_ID', 3) then
        DecorRegister('PP_PROP_ID', 3)
    end
end)

-- ─────────────────────────────────────────────────────────
-- Hilfsfunktionen
-- ─────────────────────────────────────────────────────────

local function DebugLog(msg)
    if Config.Debug then print('[prop_placement][CLIENT] ' .. tostring(msg)) end
end

-- Exakt wie M-PropV2: IsModelInCdimage + Wait(0), KEIN SetModelAsNoLongerNeeded
local function LoadModel(model)
    local hash = (type(model) == 'number') and model or GetHashKey(model)
    if not IsModelInCdimage(hash) then
        DebugLog('Modell nicht in cdimage: ' .. tostring(model))
        return false
    end
    if HasModelLoaded(hash) then return true end
    RequestModel(hash)
    local timeout = GetGameTimer() + 5000
    while not HasModelLoaded(hash) do
        Wait(0)
        if GetGameTimer() > timeout then return false end
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
-- Kein SetModelAsNoLongerNeeded – sonst werden gespawnte
-- Entities unsichtbar wenn das Modell entladen wird
-- ─────────────────────────────────────────────────────────

if Config.Preloading.Enabled then
    CreateThread(function()
        Wait(Config.Preloading.Delay)
        local count = 0
        for _, cfg in pairs(Config.Props) do
            local hash = GetHashKey(cfg.model)
            if IsModelInCdimage(hash) and not HasModelLoaded(hash) then
                RequestModel(hash)
                local timeout = GetGameTimer() + 5000
                while not HasModelLoaded(hash) do
                    Wait(0)
                    if GetGameTimer() > timeout then break end
                end
                -- KEIN SetModelAsNoLongerNeeded hier!
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
                        propData.itemName, propData.model,
                        propData.ownerIdentifier or '?'),
                    type        = 'inform',
                    duration    = 6000,
                })
            end,
        })
    end
    exports.ox_target:addLocalEntity(entity, options)
end

-- ─────────────────────────────────────────────────────────
-- Prop spawnen – M-PropV2-Muster
-- ─────────────────────────────────────────────────────────

local function SpawnProp(propData)
    local propId = propData.id

    if placedProps[propId] and DoesEntityExist(placedProps[propId]) then return end

    if placedProps[propId] then
        pcall(function() exports.ox_target:removeLocalEntity(placedProps[propId]) end)
        placedProps[propId] = nil
    end

    if not LoadModel(propData.model) then
        DebugLog('Modell nicht ladbar: ' .. propData.model); return
    end

    -- Sicherstellen dass der Bereich an den Zielkoordinaten geladen ist
    -- kurzes Wait damit die Engine nach RequestModel verarbeiten kann
    RequestCollisionAtCoord(propData.x, propData.y, propData.z)
    Wait(50)

    -- M-PropV2: String übergeben, alle Parameter false
    local entity = CreateObjectNoOffset(
        propData.model,
        propData.x, propData.y, propData.z,
        false, false, false
    )

    if not DoesEntityExist(entity) then
        DebugLog('Entity nicht erstellt: #' .. propId)
        -- Nur bei Fehler freigeben
        SetModelAsNoLongerNeeded(GetHashKey(propData.model))
        return
    end

    SetEntityRotation(entity, 0.0, 0.0, propData.rotation, 2, true)
    FreezeEntityPosition(entity, false) -- kurz unfreezen damit PlaceOnGround funktioniert
    PlaceObjectOnGroundProperly(entity)
    FreezeEntityPosition(entity, true)

    placedProps[propId] = entity
    allPropData[propId] = propData
    AddToGrid(propId, propData.x, propData.y)
    RegisterPropTarget(propId, entity, propData)

    DebugLog(('Prop #%d gespawnt bei %.1f / %.1f / %.1f'):format(
        propId, propData.x, propData.y, propData.z))
end

local function DespawnProp(propId)
    local entity = placedProps[propId]
    placedProps[propId] = nil
    if entity and DoesEntityExist(entity) then
        exports.ox_target:removeLocalEntity(entity)
        if DecorExistOn(entity, 'PP_PROP_ID') then
            DecorSetInt(entity, 'PP_PROP_ID', 0)
        end
        DeleteEntity(entity)
        DebugLog('Prop #' .. propId .. ' despawnt.')
    end
end

local function ClearAllLocalProps()
    for id, entity in pairs(placedProps) do
        if DoesEntityExist(entity) then
            exports.ox_target:removeLocalEntity(entity)
            if DecorExistOn(entity, 'PP_PROP_ID') then
                DecorSetInt(entity, 'PP_PROP_ID', 0)
            end
            DeleteEntity(entity)
        end
    end
    placedProps = {}
    allPropData = {}
    propGrid    = {}
end

-- ─────────────────────────────────────────────────────────
-- Editor-Mode Thread (nach M-PropV2)
-- Nur für Admins – zeigt Linie + Marker zum nächsten Prop
-- ─────────────────────────────────────────────────────────

CreateThread(function()
    local sleep         = 500
    local lastClosestId = nil
    while true do
        sleep = 500

        if isEditorMode and isAdmin then
            sleep             = 0
            local ped         = PlayerPedId()
            local pPos        = GetEntityCoords(ped)

            local closest     = nil
            local closestDist = 10.0
            local closestId   = nil

            for propId, entity in pairs(placedProps) do
                if DoesEntityExist(entity) then
                    local dist = #(pPos - GetEntityCoords(entity))
                    if dist < closestDist then
                        closest     = entity
                        closestDist = dist
                        closestId   = propId
                    end
                end
            end

            if closest then
                local cPos = GetEntityCoords(closest)
                local pd   = allPropData[closestId]

                DrawLine(pPos.x, pPos.y, pPos.z, cPos.x, cPos.y, cPos.z, 0, 255, 255, 180)

                local min, max = GetModelDimensions(GetEntityModel(closest))
                local topZ = cPos.z + max.z + 0.4
                DrawMarker(2, cPos.x, cPos.y, topZ, 0.0, 0.0, 0.0, 0.0, 180.0, 0.0,
                    0.25, 0.25, 0.25, 0, 200, 255, 200, true, true, 2)

                -- FIX: TextUI nur updaten wenn sich das nächste Prop ändert
                -- (nicht jeden Frame – würde NUI/CEF 60-144x/s aufrufen → FPS-Drop)
                if lastClosestId ~= closestId then
                    local label = pd and pd.itemName or ('Prop #' .. tostring(closestId))
                    lib.showTextUI(
                        ('🧱 **%s** | #%d'):format(label, closestId),
                        { position = 'top-center', icon = 'fas fa-cube' }
                    )
                    lastClosestId = closestId
                end
            else
                if lib.isTextUIOpen() then
                    lib.hideTextUI()
                    lastClosestId = nil
                end
            end
        else
            if lib.isTextUIOpen() then
                lib.hideTextUI()
                lastClosestId = nil
            end
        end

        Wait(sleep)
    end
end)

-- ─────────────────────────────────────────────────────────
-- Keepalive
-- ─────────────────────────────────────────────────────────

CreateThread(function()
    while true do
        Wait(3000)
        if not isSyncing then
            local count = 0
            for propId, entity in pairs(placedProps) do
                if not DoesEntityExist(entity) then
                    local pd = allPropData[propId]
                    if pd and IsModelInCdimage(GetHashKey(pd.model)) then
                        placedProps[propId] = nil
                        count = count + 1
                        DebugLog(('Keepalive: Prop #%d fehlt, wird neu erstellt'):format(propId))
                    end
                end
            end
            if count > 0 then forceStreamCheck = true end
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
                checkInterval     = math.min(10000,
                    Config.Streaming.CheckInterval + streamStillFrames * 500)
            else
                streamStillFrames = 0
                checkInterval     = Config.Streaming.CheckInterval
            end
            lastPos = vector3(px, py, playerPos.z)

            local toCheck = {}
            if Config.Grid.Enabled then
                for propId in pairs(GetNearbyPropIds(px, py)) do
                    toCheck[propId] = true
                end
            end
            for propId in pairs(placedProps) do toCheck[propId] = true end
            if not Config.Grid.Enabled then
                for propId in pairs(allPropData) do toCheck[propId] = true end
            end

            if not isSyncing then
                for propId in pairs(toCheck) do
                    local pd = allPropData[propId]
                    if pd then
                        local dist    = #(vector3(px, py, playerPos.z) -
                            vector3(pd.x, pd.y, pd.z))
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
        lib.notify({
            title = 'Abgebrochen',
            description = 'Platzierung abgebrochen.',
            type = 'inform',
            duration = 2000
        })
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
        local playerPos = GetEntityCoords(PlayerPedId())
        local waitTime  = 0
        while #playerPos < 1.0 and waitTime < 8000 do
            Wait(300); waitTime = waitTime + 300
            playerPos = GetEntityCoords(PlayerPedId())
        end

        local spawnCount = 0
        local skipCount  = 0

        for _, propData in ipairs(propList) do
            playerPos = GetEntityCoords(PlayerPedId())
            local dist = #(playerPos - vector3(propData.x, propData.y, propData.z))
            if not Config.Streaming.Enabled or dist <= Config.Streaming.SpawnRadius then
                SpawnProp(propData)
                spawnCount = spawnCount + 1
                Wait(0)
            else
                skipCount = skipCount + 1
            end
        end

        streamStillFrames = 0
        if skipCount > 0 then forceStreamCheck = true end
        isSyncing = false

        DebugLog(('syncAll abgeschlossen: %d gespawnt, %d außerhalb Radius'):format(
            spawnCount, skipCount))
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
        lib.notify({
            title = 'Fehler',
            description = 'Unbekannter Prop-Typ: ' .. itemName,
            type = 'error'
        }); return
    end
    StartPropPlacement(itemName, propConfig)
end)

RegisterNetEvent('prop_placement:receivePropList', function(list, filterName)
    if #list == 0 then
        lib.notify({
            title = 'Prop-Liste',
            description = 'Keine Props gefunden.',
            type = 'inform'
        }); return
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
                        header = 'Prop #' .. capturedProp.id .. ' entfernen?',
                        content = capturedProp.itemName .. ' dauerhaft löschen?',
                        centered = true,
                        cancel = true,
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
    isAdmin          = true -- Wenn der Server das Menü schickt, ist der Spieler Admin

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

    -- Editor-Mode Toggle
    table.insert(options, {
        title       = ('🔍 Editor-Mode: %s'):format(isEditorMode and '**AN**' or 'AUS'),
        description = isEditorMode
            and 'Zeigt nächsten Prop mit Linie & Marker'
            or 'Aktivieren um Props visuell zu markieren',
        icon        = isEditorMode and 'toggle-on' or 'toggle-off',
        onSelect    = function()
            isEditorMode = not isEditorMode
            if not isEditorMode and lib.isTextUIOpen() then
                lib.hideTextUI()
            end
            lib.notify({
                title       = 'Editor-Mode',
                description = isEditorMode and 'Aktiviert' or 'Deaktiviert',
                type        = 'inform',
                duration    = 2000,
            })
            -- Menü neu öffnen damit Toggle-Status aktualisiert wird
            TriggerServerEvent('prop_placement:requestAdminMenu')
        end,
    })

    table.insert(options, { title = '─────────────────', disabled = true })

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
                    local flags    = (cfg.adminOnly and '🔒 ' or '') ..
                        (cfg.persistent and '💾 ' or '')
                    table.insert(subOptions, {
                        title       = flags .. cfg.label,
                        description = ('Model: %s | %sg'):format(cfg.model, cfg.weight or 1000),
                        onSelect    = function()
                            local input = lib.inputDialog('Prop-Item geben', {
                                {
                                    type = 'number',
                                    label = 'Server-ID des Spielers',
                                    required = true,
                                    min = 1
                                },
                                {
                                    type = 'number',
                                    label = 'Anzahl',
                                    default = 1,
                                    min = 1,
                                    max = 99
                                },
                            })
                            if input and input[1] then
                                TriggerServerEvent('prop_placement:adminGive',
                                    tonumber(input[1]), itemName, tonumber(input[2]) or 1)
                            end
                        end,
                    })
                end
                lib.registerContext({
                    id      = 'pp_cat_' .. catName:gsub('%s+', '_'),
                    title   = ('🧱 %s'):format(catName),
                    menu    = 'prop_placement_admin_menu',
                    options = subOptions,
                })
                lib.showContext('pp_cat_' .. catName:gsub('%s+', '_'))
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
                    header = 'Alle Props löschen?',
                    content = 'Diese Aktion löscht alle Props dauerhaft.',
                    centered = true,
                    cancel = true,
                })
                if confirmed == 'confirm' then
                    TriggerServerEvent('prop_placement:adminClearAll')
                end
            end)
        end,
    })

    lib.registerContext({
        id      = 'prop_placement_admin_menu',
        title   = '🧱 Prop Placement – Admin',
        options = options
    })
    lib.showContext('prop_placement_admin_menu')
end)

-- ─────────────────────────────────────────────────────────
-- Initialisierung – exakt wie M-PropV2
-- ─────────────────────────────────────────────────────────
-- Kein playerSpawned, kein Framework-Event, kein Collision-Check.
-- Einfach 1 Sekunde warten, Props per Callback holen,
-- in Grid speichern. Streaming-Thread spawnt den Rest automatisch.

local function LoadProps()
    local propList = lib.callback.await('prop_placement:getProps', false) or {}
    for _, propData in ipairs(propList) do
        allPropData[propData.id] = propData
        if Config.Grid.Enabled then AddToGrid(propData.id, propData.x, propData.y) end
    end
    DebugLog(('%d Props in Grid geladen'):format(#propList))
    forceStreamCheck = true
    hasSynced = true
    return #propList
end

-- Beim Start: 1 Sekunde warten dann Props laden (M-PropV2-Pattern)
CreateThread(function()
    Wait(1000)
    LoadProps()
end)

-- Bei Resource-Reload (restart prop_placement)
AddEventHandler('onClientResourceStart', function(resourceName)
    if resourceName ~= GetCurrentResourceName() then return end
    ClearAllLocalProps()
    hasSynced        = false
    syncInProgress   = false
    forceStreamCheck = false
    CreateThread(function()
        Wait(1000)
        LoadProps()
        DebugLog('Sync via onClientResourceStart')
    end)
end)

AddEventHandler('baseevents:onPlayerDied', function()
    CancelPlacementExternal()
    if isEditorMode then
        isEditorMode = false
        if lib.isTextUIOpen() then lib.hideTextUI() end
    end
end)

AddEventHandler('onClientResourceStop', function(resourceName)
    if resourceName ~= GetCurrentResourceName() then return end
    CancelPlacementExternal()
    if lib.isTextUIOpen() then lib.hideTextUI() end
    ClearAllLocalProps()
end)

-- ─────────────────────────────────────────────────────────
-- Commands
-- ─────────────────────────────────────────────────────────

-- Test 2: DB-Props NEBEN dem Spieler spawnen (nicht an DB-Koordinaten)
-- Wenn das funktioniert → Problem sind die gespeicherten Koordinaten
RegisterCommand('testspawnhere', function()
    local propList = lib.callback.await('prop_placement:getProps', false) or {}
    if #propList == 0 then
        print('[testspawnhere] Keine Props in DB!'); return
    end

    local pos = GetEntityCoords(PlayerPedId())

    for i, propData in ipairs(propList) do
        local hash = GetHashKey(propData.model)
        if IsModelInCdimage(hash) then
            RequestModel(hash)
            while not HasModelLoaded(hash) do Wait(0) end
            -- Neben dem Spieler spawnen, jeweils 2m versetzt
            local obj = CreateObjectNoOffset(
                propData.model,
                pos.x + (i * 2.0), pos.y, pos.z,
                false, false, false
            )
            print(('[testspawnhere] #%d | %s | Exists: %s'):format(
                propData.id, propData.model, tostring(DoesEntityExist(obj))))
        end
    end
end, false)

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
            description = ('Gespawnt: %d / Bekannt: %d / Grid: %d\nEditor: %s'):format(
                spawned, total, cells, tostring(isEditorMode)),
            type        = 'inform',
        })
    end, false)
end
