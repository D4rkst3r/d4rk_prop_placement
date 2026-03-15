--[[
    ╔══════════════════════════════════════════════════════╗
    ║           prop_placement – client/main.lua           ║
    ║    Prop-Spawning, Sync, ox_target & Admin-Menü       ║
    ╚══════════════════════════════════════════════════════╝
]]

-- Lokale Prop-Tabelle: [propId (int)] = entity (int)
local placedProps = {}

-- ─────────────────────────────────────────────────────────
-- Hilfsfunktionen
-- ─────────────────────────────────────────────────────────

local function DebugLog(msg)
    if Config.Debug then
        print('[prop_placement][CLIENT] ' .. tostring(msg))
    end
end

--- Modell laden mit Timeout-Sicherung
--- @param model number  GetHashKey(…)
--- @return bool
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
-- ox_target an einem platzierten Prop registrieren
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

    -- Optional: Info-Option
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
-- Einen einzelnen Prop spawnen
-- ─────────────────────────────────────────────────────────

local function SpawnProp(propData)
    local propId = propData.id
    local model  = GetHashKey(propData.model)

    -- Bereits gespawnt → überspringen
    if placedProps[propId] and DoesEntityExist(placedProps[propId]) then
        DebugLog('Prop #' .. propId .. ' bereits gespawnt – überspringe.')
        return
    end

    if not LoadModel(model) then
        DebugLog('Modell konnte nicht geladen werden: ' .. propData.model)
        return
    end

    local entity = CreateObject(
        model,
        propData.x, propData.y, propData.z,
        false, false, false
    )

    SetEntityRotation(entity, 0.0, 0.0, propData.rotation, 2, true)
    FreezeEntityPosition(entity, true)
    SetEntityCollision(entity, true, true)
    SetEntityInvincible(entity, true) -- Props sollen nicht beschädigt werden
    SetEntityCanBeDamaged(entity, false)

    placedProps[propId] = entity

    -- ox_target registrieren
    RegisterPropTarget(propId, entity, propData)

    SetModelAsNoLongerNeeded(model)
    DebugLog('Prop #' .. propId .. ' gespawnt (' .. propData.model .. ')')
end

-- ─────────────────────────────────────────────────────────
-- Einen Prop entfernen
-- ─────────────────────────────────────────────────────────

local function DespawnProp(propId)
    local entity = placedProps[propId]
    if entity and DoesEntityExist(entity) then
        exports.ox_target:removeLocalEntity(entity)
        DeleteObject(entity)
        DebugLog('Prop #' .. propId .. ' entfernt.')
    end
    placedProps[propId] = nil
end

-- ─────────────────────────────────────────────────────────
-- Alle Props löschen (z.B. beim Re-Sync)
-- ─────────────────────────────────────────────────────────

local function ClearAllLocalProps()
    for id, entity in pairs(placedProps) do
        if DoesEntityExist(entity) then
            exports.ox_target:removeLocalEntity(entity)
            DeleteObject(entity)
        end
    end
    placedProps = {}
end

-- ─────────────────────────────────────────────────────────
-- Net Events – Server → Client
-- ─────────────────────────────────────────────────────────

--- Server sendet beim Spawn/Ressource-Start alle Props
RegisterNetEvent('prop_placement:syncAll', function(propList)
    ClearAllLocalProps()
    DebugLog(('Sync: %d Props empfangen'):format(#propList))

    -- ox_inventory Client-seitige useItem Registrierung
    CreateThread(function()
        Wait(1000) -- warten bis ox_inventory bereit ist

        for itemName, _ in pairs(Config.Props) do
            local name = itemName

            exports.ox_inventory:useItem(name, function(data)
                print('[PP-DEBUG CLIENT] useItem callback: ' .. name)
                TriggerServerEvent('prop_placement:requestPlace', name)
            end)
        end

        print('[PP-DEBUG CLIENT] Alle useItem Callbacks registriert')
    end)
end)

--- Ein neuer Prop wurde von irgendjemandem platziert
RegisterNetEvent('prop_placement:propPlaced', function(propData)
    DebugLog('Neuer Prop empfangen: #' .. propData.id)
    SpawnProp(propData)
end)

--- Ein Prop wurde entfernt
RegisterNetEvent('prop_placement:propRemoved', function(propId)
    DebugLog('Prop #' .. propId .. ' wurde entfernt')
    DespawnProp(propId)
end)

--- Server fordert uns auf mit dem Platzieren anzufangen
RegisterNetEvent('prop_placement:startPlacing', function(itemName)
    print('[PP-DEBUG CLIENT] startPlacing empfangen für: ' .. tostring(itemName))

    local propConfig = Config.Props[itemName]
    if not propConfig then
        print('[PP-DEBUG CLIENT] FEHLER: propConfig ist nil für ' .. tostring(itemName))
        lib.notify({ title = 'Fehler', description = 'Unbekannter Prop-Typ: ' .. itemName, type = 'error' })
        return
    end

    print('[PP-DEBUG CLIENT] propConfig gefunden, starte Placement. Model: ' .. propConfig.model)
    StartPropPlacement(itemName, propConfig)
end)

--- Admin-Menü öffnen (nur ausgelöst wenn Server die Berechtigung bestätigt hat)
RegisterNetEvent('prop_placement:openAdminMenu', function()
    local options = {}

    -- Props sortiert anzeigen
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

    -- Props-Übersicht / Aufräumen
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
-- Initialisierung: Sync anfordern
-- ─────────────────────────────────────────────────────────

-- Beim Start der Ressource
AddEventHandler('onClientResourceStart', function(resourceName)
    if resourceName ~= GetCurrentResourceName() then return end
    Wait(1000) -- kurz warten bis Netzwerk bereit ist
    TriggerServerEvent('prop_placement:requestSync')
end)

-- Beim Spieler-Spawn (Respawn, erster Spawn)
AddEventHandler('playerSpawned', function()
    Wait(500)
    TriggerServerEvent('prop_placement:requestSync')
end)

-- Bei Tod Platzierung abbrechen
AddEventHandler('baseevents:onPlayerDied', function()
    CancelPlacementExternal()
end)

-- ─────────────────────────────────────────────────────────
-- Ressource aufräumen
-- ─────────────────────────────────────────────────────────

AddEventHandler('onClientResourceStop', function(resourceName)
    if resourceName ~= GetCurrentResourceName() then return end
    CancelPlacementExternal()
    ClearAllLocalProps()
end)

-- ─────────────────────────────────────────────────────────
-- Commands (nur UI-Trigger – Berechtigung prüft Server)
-- ─────────────────────────────────────────────────────────

RegisterCommand('propadmin', function()
    TriggerServerEvent('prop_placement:requestAdminMenu')
end, false)

-- Debug: Alle lokalen Props zählen
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
