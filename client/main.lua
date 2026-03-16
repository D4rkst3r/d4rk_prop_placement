--[[
    ╔══════════════════════════════════════════════════════╗
    ║           prop_placement – client/main.lua           ║
    ║   Server-side Entities – Client nur ox_target        ║
    ╚══════════════════════════════════════════════════════╝

    ARCHITEKTUR:
    ─────────────
    Der Server erstellt alle Entities und schickt NetIDs.
    Der Client wartet mit NetToObj(netId) bis die Entity gestreamt ist
    und registriert dann nur ox_target – kein eigenes Spawning nötig.
    GTA's Engine übernimmt Streaming, Sichtbarkeit und Chunk-Loading.
]]

local propTargets = {}    -- [propId] = entity handle (für ox_target Cleanup)
local hasSynced   = false -- Guard gegen Doppel-Sync

-- ─────────────────────────────────────────────────────────
-- Hilfsfunktionen
-- ─────────────────────────────────────────────────────────

local function DebugLog(msg)
    if Config.Debug then
        print('[prop_placement][CLIENT] ' .. tostring(msg))
    end
end

-- Wartet bis die Netzwerk-Entity beim Client angekommen ist
local function WaitForNetEntity(netId, timeoutMs)
    local waited = 0
    timeoutMs = timeoutMs or 5000
    while waited < timeoutMs do
        local entity = NetToObj(netId)
        if DoesEntityExist(entity) then
            return entity
        end
        Wait(10)
        waited = waited + 10
    end
    return nil
end

-- ─────────────────────────────────────────────────────────
-- Model-Preloading (für Platzierungs-Vorschau in placement.lua)
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
        DebugLog(('Preloading: %d Modelle vorgeladen.'):format(count))
    end)
end

-- ─────────────────────────────────────────────────────────
-- ox_target registrieren
-- ─────────────────────────────────────────────────────────

local function RegisterPropTarget(propId, entity, propData)
    propTargets[propId] = entity

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
                    description = ('Item: %s\nModel: %s\nNetID: %s\nBesitzer: %s'):format(
                        propData.itemName, propData.model,
                        tostring(propData.netId),
                        propData.ownerIdentifier or '?'
                    ),
                    type        = 'inform',
                    duration    = 6000,
                })
            end,
        })
    end

    exports.ox_target:addLocalEntity(entity, options)
    DebugLog(('Prop #%d Target registriert (entity=%d)'):format(propId, entity))
end

local function RemovePropTarget(propId)
    local entity = propTargets[propId]
    if entity and DoesEntityExist(entity) then
        exports.ox_target:removeLocalEntity(entity)
    end
    propTargets[propId] = nil
end

local function ClearAllTargets()
    for propId, entity in pairs(propTargets) do
        if DoesEntityExist(entity) then
            exports.ox_target:removeLocalEntity(entity)
        end
    end
    propTargets = {}
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
    DebugLog('syncAll: ' .. #propList .. ' Props empfangen')
    hasSynced = true
    ClearAllTargets()

    -- Für jeden Prop auf die Entity warten und Target registrieren
    CreateThread(function()
        local registered = 0
        for _, propData in ipairs(propList) do
            if propData.netId then
                local entity = WaitForNetEntity(propData.netId, 8000)
                if entity then
                    RegisterPropTarget(propData.id, entity, propData)
                    registered = registered + 1
                else
                    DebugLog(('Prop #%d Timeout – netId %d nicht angekommen'):format(
                        propData.id, propData.netId))
                end
            end
        end
        DebugLog(('syncAll abgeschlossen: %d/%d Props registriert'):format(registered, #propList))
    end)
end)

RegisterNetEvent('prop_placement:propPlaced', function(propData)
    DebugLog('Neuer Prop: #' .. propData.id .. ' (netId: ' .. tostring(propData.netId) .. ')')
    if not propData.netId then return end

    CreateThread(function()
        local entity = WaitForNetEntity(propData.netId, 8000)
        if entity then
            RegisterPropTarget(propData.id, entity, propData)
        else
            DebugLog('Prop #' .. propData.id .. ': Entity nie angekommen.')
        end
    end)
end)

RegisterNetEvent('prop_placement:propRemoved', function(propId)
    DebugLog('Prop #' .. propId .. ' entfernt')
    RemovePropTarget(propId)
    -- Entity selbst wird vom Server gelöscht – kein DeleteEntity nötig
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

AddEventHandler('onClientResourceStart', function(resourceName)
    if resourceName ~= GetCurrentResourceName() then return end
    hasSynced = false
    CreateThread(function()
        local ped    = PlayerPedId()
        local waited = 0
        repeat
            Wait(500)
            waited = waited + 500
            ped = PlayerPedId()
        until HasCollisionLoadedAroundEntity(ped) or waited >= 10000
        Wait(500)

        if not hasSynced then
            hasSynced = true
            TriggerServerEvent('prop_placement:requestSync')
            DebugLog('Sync via onClientResourceStart')
        end
    end)
end)

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

        if not hasSynced then
            hasSynced = true
            TriggerServerEvent('prop_placement:requestSync')
            DebugLog('Sync via playerSpawned')
        end
    end)
end)

AddEventHandler('baseevents:onPlayerDied', function()
    CancelPlacementExternal()
end)

AddEventHandler('onClientResourceStop', function(resourceName)
    if resourceName ~= GetCurrentResourceName() then return end
    CancelPlacementExternal()
    ClearAllTargets()
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
    ClearAllTargets()
    lib.notify({ title = 'Props werden neu geladen...', type = 'inform', duration = 2000 })
    CreateThread(function()
        Wait(500)
        TriggerServerEvent('prop_placement:reloadProps')
    end)
end, false)

if Config.Debug then
    RegisterCommand('propdebug', function()
        local count = 0
        for _ in pairs(propTargets) do count = count + 1 end
        lib.notify({
            title       = 'Prop Debug',
            description = ('Registrierte Targets: %d'):format(count),
            type        = 'inform',
        })
    end, false)
end
