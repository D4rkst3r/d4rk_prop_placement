--[[
    ╔══════════════════════════════════════════════════════╗
    ║           prop_placement – client/main.lua           ║
    ║    Prop-Spawning, Sync, ox_target & Admin-Menü       ║
    ║    OPTIMIERT für 400+ Spieler                        ║
    ╚══════════════════════════════════════════════════════╝
]]

local placedProps = {}
local allPropData = {}
local propGrid    = {}
local isSyncing   = false -- Guard gegen gleichzeitige syncAll-Aufrufe
local syncToken   = 0     -- Einfache Token-Logik um veraltete syncAll-Threads zu erkennen (siehe weiter unten)

-- ─────────────────────────────────────────────────────────
-- Hilfsfunktionen
-- ─────────────────────────────────────────────────────────

local function DebugLog(msg)
    if Config.Debug then
        print('[prop_placement][CLIENT] ' .. tostring(msg))
    end
end

local function LoadModel(model)
    if HasModelLoaded(model) then return true end
    RequestModel(model)
    local t = 0
    while not HasModelLoaded(model) do
        Wait(100)
        t = t + 1
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

local function GetGridKey(cx, cy)
    return cx .. ':' .. cy
end

local function AddToGrid(propId, x, y)
    local cx, cy = GetGridCell(x, y)
    local key    = GetGridKey(cx, cy)
    if not propGrid[key] then propGrid[key] = {} end
    propGrid[key][propId] = true
end

local function RemoveFromGrid(propId, x, y)
    local cx, cy = GetGridCell(x, y)
    local key    = GetGridKey(cx, cy)
    if propGrid[key] then
        propGrid[key][propId] = nil
    end
end

local function GetNearbyPropIds(x, y)
    local cx, cy = GetGridCell(x, y)
    local nearby = {}
    for dx = -1, 1 do
        for dy = -1, 1 do
            local key = GetGridKey(cx + dx, cy + dy)
            if propGrid[key] then
                for propId in pairs(propGrid[key]) do
                    nearby[propId] = true
                end
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
                    Wait(100)
                    t = t + 1
                end
                SetModelAsNoLongerNeeded(model)
                count = count + 1
            end
        end
        DebugLog(('Model-Preloading: %d Modelle vorgeladen.'):format(count))
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
                        propData.itemName, propData.model, propData.ownerIdentifier or '?'
                    ),
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
    local model  = GetHashKey(propData.model)

    if placedProps[propId] and DoesEntityExist(placedProps[propId]) then return end

    if not LoadModel(model) then
        DebugLog('Modell konnte nicht geladen werden: ' .. propData.model)
        return
    end

    local entity = CreateObject(model, propData.x, propData.y, propData.z, false, false, false)

    SetEntityAsMissionEntity(entity, true, true)
    SetEntityRotation(entity, 0.0, 0.0, propData.rotation, 2, true)
    FreezeEntityPosition(entity, true)
    SetEntityCollision(entity, true, true)
    SetEntityInvincible(entity, true)
    SetEntityCanBeDamaged(entity, false)
    SetEntityAlpha(entity, 255, false)
    NetworkSetEntityInvisibleToNetwork(entity, false) -- ← wieder rein
    SetEntityLodDist(entity, 1000)                    -- ← neu dazu

    placedProps[propId] = entity
    allPropData[propId] = propData
    AddToGrid(propId, propData.x, propData.y)
    RegisterPropTarget(propId, entity, propData)
    SetModelAsNoLongerNeeded(model)

    DebugLog('Prop #' .. propId .. ' gespawnt (' .. propData.model .. ')')
end

local function DespawnProp(propId)
    local entity = placedProps[propId]
    placedProps[propId] = nil

    if entity and DoesEntityExist(entity) then
        exports.ox_target:removeLocalEntity(entity)
        SetEntityInvincible(entity, false)
        SetEntityCanBeDamaged(entity, true)
        FreezeEntityPosition(entity, false)
        SetEntityAsMissionEntity(entity, true, true)
        DeleteEntity(entity)
        DebugLog('Prop #' .. propId .. ' entfernt.')
    end
end

local function ClearAllLocalProps()
    for id, entity in pairs(placedProps) do
        if DoesEntityExist(entity) then
            exports.ox_target:removeLocalEntity(entity)
            SetEntityInvincible(entity, false)
            SetEntityCanBeDamaged(entity, true)
            FreezeEntityPosition(entity, false)
            SetEntityAsMissionEntity(entity, true, true)
            DeleteEntity(entity)
        end
    end
    placedProps = {}
    allPropData = {}
    propGrid    = {}
    -- isSyncing hier NICHT zurücksetzen!
end

-- ─────────────────────────────────────────────────────────
-- Streaming-System mit Grid + dynamischem Intervall
-- ─────────────────────────────────────────────────────────

-- Streaming-State (außerhalb Thread damit syncAll es zurücksetzen kann)
local streamStillFrames = 0

if Config.Streaming.Enabled then
    CreateThread(function()
        local lastPos       = vector3(0, 0, 0)
        local checkInterval = Config.Streaming.CheckInterval

        while true do
            Wait(checkInterval)

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
                toCheck = GetNearbyPropIds(px, py)
                for propId in pairs(placedProps) do
                    toCheck[propId] = true
                end
            else
                for propId in pairs(allPropData) do
                    toCheck[propId] = true
                end
            end

            for propId in pairs(toCheck) do
                local propData = allPropData[propId]
                if propData then
                    local dist    = #(vector3(px, py, playerPos.z) - vector3(propData.x, propData.y, propData.z))
                    local spawned = placedProps[propId] and DoesEntityExist(placedProps[propId])

                    if not spawned and dist <= Config.Streaming.SpawnRadius then
                        SpawnProp(propData)
                    elseif spawned and dist > Config.Streaming.DespawnRadius then
                        DespawnProp(propId)
                    end
                end
            end
        end
    end)
end

-- ─────────────────────────────────────────────────────────
-- Inventar geschlossen → Platzierung abbrechen
-- ─────────────────────────────────────────────────────────

AddEventHandler('ox_inventory:closedInventory', function()
    if IsCurrentlyPlacing() then
        CancelPlacementExternal()
        lib.notify({ title = 'Abgebrochen', description = 'Platzierung abgebrochen.', type = 'inform', duration = 2000 })
    end
end)

-- ─────────────────────────────────────────────────────────
-- Net Events – Server → Client
-- ─────────────────────────────────────────────────────────

RegisterNetEvent('prop_placement:syncAll', function(propList)
    ClearAllLocalProps()

    CreateThread(function()
        local playerPos = GetEntityCoords(PlayerPedId())

        -- Doppelte bestehende Welt-Objekte entfernen
        for _, propData in ipairs(propList) do
            local model    = GetHashKey(propData.model)
            local existing = GetClosestObjectOfType(
                propData.x, propData.y, propData.z,
                1.0, model, false, false, false
            )
            if DoesEntityExist(existing) then
                SetEntityAsMissionEntity(existing, true, true)
                DeleteEntity(existing)
            end
        end

        for _, propData in ipairs(propList) do
            allPropData[propData.id] = propData
            if Config.Grid.Enabled then
                AddToGrid(propData.id, propData.x, propData.y)
            end
        end

        for _, propData in ipairs(propList) do
            local dist = #(playerPos - vector3(propData.x, propData.y, propData.z))
            if not Config.Streaming.Enabled or dist <= Config.Streaming.SpawnRadius then
                SpawnProp(propData)
                Wait(30)
            end
        end
    end)

    DebugLog(('Sync: %d Props empfangen'):format(#propList))
end)

RegisterNetEvent('prop_placement:propPlaced', function(propData)
    DebugLog('Neuer Prop empfangen: #' .. propData.id)
    allPropData[propData.id] = propData
    if Config.Grid.Enabled then
        AddToGrid(propData.id, propData.x, propData.y)
    end

    if not Config.Streaming.Enabled then
        SpawnProp(propData)
    else
        local playerPos = GetEntityCoords(PlayerPedId())
        local dist      = #(playerPos - vector3(propData.x, propData.y, propData.z))
        if dist <= Config.Streaming.SpawnRadius then
            SpawnProp(propData)
        end
    end
end)

RegisterNetEvent('prop_placement:propRemoved', function(propId)
    DebugLog('Prop #' .. propId .. ' wurde entfernt')
    local propData = allPropData[propId]
    if propData and Config.Grid.Enabled then
        RemoveFromGrid(propId, propData.x, propData.y)
    end
    allPropData[propId] = nil
    DespawnProp(propId)
end)

RegisterNetEvent('prop_placement:startPlacing', function(itemName)
    local propConfig = Config.Props[itemName]
    if not propConfig then
        lib.notify({ title = 'Fehler', description = 'Unbekannter Prop-Typ: ' .. itemName, type = 'error' })
        return
    end
    StartPropPlacement(itemName, propConfig)
end)

-- ─────────────────────────────────────────────────────────
-- Prop-Liste empfangen (Admin)
-- ─────────────────────────────────────────────────────────

RegisterNetEvent('prop_placement:receivePropList', function(list, filterName)
    if #list == 0 then
        lib.notify({ title = 'Prop-Liste', description = 'Keine Props gefunden.', type = 'inform' })
        return
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

-- ─────────────────────────────────────────────────────────
-- Admin-Menü
-- ─────────────────────────────────────────────────────────

RegisterNetEvent('prop_placement:openAdminMenu', function()
    local categories = {}
    local catItems   = {}

    for itemName, cfg in pairs(Config.Props) do
        local cat = cfg.category or 'Sonstiges'
        if not catItems[cat] then
            catItems[cat] = {}
            table.insert(categories, cat)
        end
        table.insert(catItems[cat], { itemName = itemName, cfg = cfg })
    end
    table.sort(categories)

    local options = {}

    for _, cat in ipairs(categories) do
        local items    = catItems[cat]
        local catName  = cat
        local catCount = #items

        table.sort(items, function(a, b) return a.cfg.label < b.cfg.label end)

        table.insert(options, {
            title       = ('📦 %s (%d)'):format(catName, catCount),
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
        onSelect    = function()
            TriggerServerEvent('prop_placement:requestPropList', nil)
        end,
    })

    table.insert(options, {
        title       = '🔍 Props nach Spieler filtern',
        description = 'Props eines bestimmten Spielers anzeigen',
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
        description = 'Alle Props eines bestimmten Spielers entfernen',
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
                if confirmed == 'confirm' then
                    TriggerServerEvent('prop_placement:adminClearAll')
                end
            end)
        end,
    })

    lib.registerContext({
        id      = 'prop_placement_admin_menu',
        title   = '🧱 Prop Placement – Admin',
        options = options,
    })
    lib.showContext('prop_placement_admin_menu')
end)

-- ─────────────────────────────────────────────────────────
-- Initialisierung
-- ─────────────────────────────────────────────────────────


AddEventHandler('playerSpawned', function()
    CreateThread(function()
        local ped    = PlayerPedId()
        local waited = 0
        repeat
            Wait(500)
            waited = waited + 500
            ped = PlayerPedId()
        until HasCollisionLoadedAroundEntity(ped) or waited >= 10000
        Wait(500)
        TriggerServerEvent('prop_placement:requestSync')
    end)
end)

AddEventHandler('baseevents:onPlayerDied', function()
    CancelPlacementExternal()
end)

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
    -- Nur für Admins – Prüfung erfolgt serverseitig
    TriggerServerEvent('prop_placement:reloadProps')
end, false)

if Config.Debug then
    RegisterCommand('propdebug', function()
        local spawned = 0
        local total   = 0
        local cells   = 0
        for _ in pairs(placedProps) do spawned = spawned + 1 end
        for _ in pairs(allPropData) do total = total + 1 end
        for _ in pairs(propGrid) do cells = cells + 1 end
        lib.notify({
            title       = 'Prop Debug',
            description = ('Gespawnt: %d / Bekannt: %d / Grid-Zellen: %d'):format(spawned, total, cells),
            type        = 'inform',
        })
    end, false)
end
