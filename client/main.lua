--[[
    ╔══════════════════════════════════════════════════════╗
    ║           prop_placement – client/main.lua           ║
    ║    Prop-Spawning, Sync, ox_target & Admin-Menü       ║
    ╚══════════════════════════════════════════════════════╝
]]

local placedProps = {}

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
-- Prop spawnen
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

    placedProps[propId] = entity
    RegisterPropTarget(propId, entity, propData)
    SetModelAsNoLongerNeeded(model)

    DebugLog('Prop #' .. propId .. ' gespawnt (' .. propData.model .. ')')
end

-- ─────────────────────────────────────────────────────────
-- Prop entfernen
-- ─────────────────────────────────────────────────────────

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

-- ─────────────────────────────────────────────────────────
-- Alle Props löschen
-- ─────────────────────────────────────────────────────────

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
end

-- ─────────────────────────────────────────────────────────
-- Net Events – Server → Client
-- ─────────────────────────────────────────────────────────

RegisterNetEvent('prop_placement:syncAll', function(propList)
    ClearAllLocalProps()

    -- Alte übrig gebliebene Objekte aus vorherigem Start entfernen
    CreateThread(function()
        for _, propData in ipairs(propList) do
            local model = GetHashKey(propData.model)
            -- Objekt an dieser Position suchen und löschen falls vorhanden
            local existing = GetClosestObjectOfType(
                propData.x, propData.y, propData.z,
                1.0, model, false, false, false
            )
            if DoesEntityExist(existing) then
                SetEntityAsMissionEntity(existing, true, true)
                DeleteEntity(existing)
            end
        end

        -- Dann neu spawnen
        for _, propData in ipairs(propList) do
            SpawnProp(propData)
            Wait(30)
        end
    end)

    DebugLog(('Sync: %d Props empfangen'):format(#propList))
end)

RegisterNetEvent('prop_placement:propPlaced', function(propData)
    DebugLog('Neuer Prop empfangen: #' .. propData.id)
    SpawnProp(propData)
end)

RegisterNetEvent('prop_placement:propRemoved', function(propId)
    DebugLog('Prop #' .. propId .. ' wurde entfernt')
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

RegisterNetEvent('prop_placement:openAdminMenu', function()
    local options     = {}
    local sortedItems = {}

    for itemName, cfg in pairs(Config.Props) do
        table.insert(sortedItems, { itemName = itemName, cfg = cfg })
    end
    table.sort(sortedItems, function(a, b) return a.cfg.label < b.cfg.label end)

    for _, entry in ipairs(sortedItems) do
        local itemName = entry.itemName
        local cfg      = entry.cfg
        local jobStr   = cfg.jobs and table.concat(cfg.jobs, ', ') or 'Alle'
        local flags    = (cfg.adminOnly and '🔒 ' or '') .. (cfg.persistent and '💾 ' or '')

        table.insert(options, {
            title       = flags .. cfg.label,
            description = ('Model: %s\nJobs: %s'):format(cfg.model, jobStr),
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

    table.insert(options, {
        title       = '🗑 Alle Props löschen',
        description = 'Entfernt ALLE platzierten Props (DB + Clients)',
        metadata    = { { label = 'Achtung', value = 'Kann nicht rückgängig gemacht werden!' } },
        onSelect    = function()
            lib.alertDialog({
                header   = 'Alle Props löschen?',
                content  = 'Diese Aktion löscht alle Props dauerhaft aus der Datenbank.',
                centered = true,
                cancel   = true,
            }):next(function(confirmed)
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
    Wait(1000)
    TriggerServerEvent('prop_placement:requestSync')
end)

AddEventHandler('playerSpawned', function()
    Wait(500)
    TriggerServerEvent('prop_placement:requestSync')
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

if Config.Debug then
    RegisterCommand('propdebug', function()
        local count = 0
        for _ in pairs(placedProps) do count = count + 1 end
        lib.notify({
            title       = 'Prop Debug',
            description = 'Lokal gespawnte Props: ' .. count,
            type        = 'inform',
        })
    end, false)
end
