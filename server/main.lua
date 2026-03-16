--[[
    ╔══════════════════════════════════════════════════════╗
    ║           prop_placement – server/main.lua           ║
    ║   Server-side Entities (wie qb-propplacing)          ║
    ║   Kein Chunk-Bug, kein Retry-Loop                    ║
    ╚══════════════════════════════════════════════════════╝

    ARCHITEKTUR:
    ─────────────
    Server erstellt alle Prop-Entities mit CreateObjectNoOffset + isNetwork=true.
    Der Server gibt jedem Prop eine NetID (NetworkGetNetworkIdFromEntity).
    Clients erhalten nur die NetID und rufen NetToObj(netId) auf.
    GTA's eigene Engine übernimmt Streaming und Sichtbarkeit automatisch.
]]

local placedProps     = {} -- [id] = { id, itemName, model, x,y,z, rotation, ownerIdentifier, persistent, entity, netId }
local nextId          = 1
local cooldowns       = {}
local playerPropCount = {}
local dbReady         = false
local syncQueue       = {} -- Clients die vor DB-Load requestSync schickten

-- ─────────────────────────────────────────────────────────
-- Hilfsfunktionen
-- ─────────────────────────────────────────────────────────

local function DebugLog(msg)
    if Config.Debug then print('[prop_placement][SERVER] ' .. tostring(msg)) end
end

local function GetIdentifier(source)
    for i = 0, GetNumPlayerIdentifiers(source) - 1 do
        local id = GetPlayerIdentifier(source, i)
        if string.sub(id, 1, 8) == 'license:' then return id end
    end
    return 'player:' .. source
end

local function IsAdmin(source)
    if source == 0 then return true end
    return IsPlayerAceAllowed(source, 'prop_placement.admin')
end

local function CountPlayerProps(identifier)
    return playerPropCount[identifier] or 0
end

local function IncrementPlayerProps(identifier)
    playerPropCount[identifier] = (playerPropCount[identifier] or 0) + 1
end

local function DecrementPlayerProps(identifier)
    local count = (playerPropCount[identifier] or 0) - 1
    playerPropCount[identifier] = count > 0 and count or nil
end

-- Serialisierbares PropData für Clients (ohne server-seitige Entity-Handle)
local function ToClientData(prop)
    return {
        id              = prop.id,
        itemName        = prop.itemName,
        model           = prop.model,
        x               = prop.x,
        y               = prop.y,
        z               = prop.z,
        rotation        = prop.rotation,
        ownerIdentifier = prop.ownerIdentifier,
        persistent      = prop.persistent,
        netId           = prop.netId,
    }
end

local function GetPropList()
    local list = {}
    for _, prop in pairs(placedProps) do
        table.insert(list, ToClientData(prop))
    end
    return list
end

local function IsOnCooldown(identifier)
    if Config.PlacementCooldown <= 0 then return false end
    local last = cooldowns[identifier]
    if not last then return false end
    return (os.clock() * 1000 - last) < Config.PlacementCooldown
end

local function SetCooldown(identifier)
    cooldowns[identifier] = os.clock() * 1000
end

-- ─────────────────────────────────────────────────────────
-- Server-seitige Entity erstellen
-- ─────────────────────────────────────────────────────────

local function CreatePropEntity(model, x, y, z, rotation)
    local hash   = GetHashKey(model)
    local entity = CreateObjectNoOffset(hash, x, y, z, true, false, false)
    if not DoesEntityExist(entity) then
        DebugLog('FEHLER: Entity konnte nicht erstellt werden für Modell: ' .. model)
        return nil, nil
    end
    FreezeEntityPosition(entity, true)
    SetEntityRotation(entity, 0.0, 0.0, rotation or 0.0, 2, true)

    -- Allen Clients mitteilen dass diese Entity existiert (beschleunigt NetID-Vergabe)
    NetworkSetEntityExistsOnAllMachines(entity, true)

    -- Retry-Loop bis FiveM die Entity im Netzwerk registriert hat.
    -- NetworkGetNetworkIdFromEntity liefert 65532/65533 (0xFFFC/0xFFFD) solange
    -- die Registration noch aussteht – das kann mehrere Ticks dauern.
    local netId   = 0
    local attempt = 0
    repeat
        Wait(50)
        netId   = NetworkGetNetworkIdFromEntity(entity)
        attempt = attempt + 1
    until (netId > 0 and netId < 65000) or attempt >= 40 -- max 2s

    if netId == 0 or netId >= 65000 then
        DebugLog(('FEHLER: NetID nach 40 Versuchen ungültig (%d) für %s'):format(netId, model))
        DeleteEntity(entity)
        return nil, nil
    end

    DebugLog(('Entity erstellt: model=%s | entity=%d | netId=%d'):format(model, entity, netId))
    return entity, netId
end

local function DeletePropEntity(prop)
    if prop and prop.entity and DoesEntityExist(prop.entity) then
        DeleteEntity(prop.entity)
    end
end

-- ─────────────────────────────────────────────────────────
-- DB laden & Entities erstellen
-- ─────────────────────────────────────────────────────────

CreateThread(function()
    local result = MySQL.query.await('SELECT * FROM prop_placement_props WHERE persistent = 1 ORDER BY id ASC')
    if result then
        for _, row in ipairs(result) do
            local id            = row.id
            local owner         = row.owner_identifier

            local entity, netId = CreatePropEntity(row.model, row.x, row.y, row.z, row.rotation)

            placedProps[id]     = {
                id              = id,
                itemName        = row.item_name,
                model           = row.model,
                x               = row.x,
                y               = row.y,
                z               = row.z,
                rotation        = row.rotation,
                ownerIdentifier = owner,
                persistent      = true,
                entity          = entity,
                netId           = netId,
            }
            if owner then playerPropCount[owner] = (playerPropCount[owner] or 0) + 1 end
            if id >= nextId then nextId = id + 1 end
        end
        print(('[prop_placement] %d persistente Props aus DB geladen und erstellt.'):format(#result))
    end

    -- dbReady setzen BEVOR syncQueue abgearbeitet wird
    dbReady = true

    -- Clients versorgen die requestSync geschickt haben bevor DB fertig war
    for _, src in ipairs(syncQueue) do
        TriggerClientEvent('prop_placement:syncAll', src, GetPropList())
        DebugLog('Queued Sync → Spieler ' .. src)
    end
    syncQueue = {}

    -- d4rk_livemap Integration
    CreateThread(function()
        Wait(2000)
        local colorMap = { Allgemein = '#60a5fa', Polizei = '#f87171', Baustelle = '#fbbf24', Admin = '#c084fc' }
        local loaded = 0
        for id, prop in pairs(placedProps) do
            pcall(function()
                local cfg = Config.Props[prop.itemName]
                exports.d4rk_livemap:AddMarker({
                    id = 'prop_' .. id,
                    x = prop.x,
                    y = prop.y,
                    z = prop.z,
                    label  = (cfg and cfg.label or prop.itemName) .. ' #' .. id,
                    color  = colorMap[(cfg and cfg.category)] or '#00d4aa',
                    icon   = 'box',
                    group  = (cfg and cfg.category) or 'Props',
                    source = 'prop_placement',
                })
                loaded = loaded + 1
            end)
        end
        print(('[prop_placement] %d Props an d4rk_livemap übermittelt.'):format(loaded))
    end)
end)

-- ─────────────────────────────────────────────────────────
-- Items registrieren
-- ─────────────────────────────────────────────────────────

CreateThread(function()
    Wait(500)
    local ok = pcall(function()
        local resourceName = GetCurrentResourceName()
        local items = {}
        for itemName, cfg in pairs(Config.Props) do
            items[itemName] = {
                label  = cfg.label,
                weight = cfg.weight or 1000,
                stack  = true,
                close  = true,
                image  = ('nui://%s/web/images/%s.png'):format(resourceName, itemName),
            }
        end
        exports.ox_inventory:Items(items)
    end)
    if ok then
        print('[prop_placement] ox_inventory: Items automatisch registriert.')
    else
        print('[prop_placement] HINWEIS: Items manuell in ox_inventory/data/items.lua eintragen.')
    end
end)

-- ─────────────────────────────────────────────────────────
-- Hilfsfunktion: Spieler-Props bereinigen
-- ─────────────────────────────────────────────────────────

local function RemovePlayerProps(identifier)
    local removedIds = {}
    for id, prop in pairs(placedProps) do
        if prop.ownerIdentifier == identifier then
            table.insert(removedIds, id)
        end
    end
    if #removedIds == 0 then return 0 end

    for _, id in ipairs(removedIds) do
        DeletePropEntity(placedProps[id])
        placedProps[id] = nil
        TriggerClientEvent('prop_placement:propRemoved', -1, id)
    end
    playerPropCount[identifier] = nil

    local placeholders = {}
    for i = 1, #removedIds do placeholders[i] = '?' end
    MySQL.query('DELETE FROM prop_placement_props WHERE id IN (' .. table.concat(placeholders, ',') .. ')', removedIds)
    return #removedIds
end

-- ─────────────────────────────────────────────────────────
-- Net Events
-- ─────────────────────────────────────────────────────────

AddEventHandler('ox_inventory:usedItem', function(playerId, name)
    if not Config.Props[name] then return end
    if not playerId or playerId == 0 then return end
    TriggerClientEvent('prop_placement:startPlacing', playerId, name)
end)

AddEventHandler('playerDropped', function()
    local src             = source
    local identifier      = GetIdentifier(src)
    cooldowns[identifier] = nil
    if Config.RemoveOnDisconnect then
        local removed = RemovePlayerProps(identifier)
        if removed > 0 then
            DebugLog(('Spieler %s – %d Props entfernt.'):format(identifier, removed))
        end
    end
end)

RegisterNetEvent('prop_placement:requestSync', function()
    local src = source
    if not dbReady then
        table.insert(syncQueue, src)
        DebugLog('Sync queued für Spieler ' .. src .. ' (DB noch nicht bereit)')
        return
    end
    TriggerClientEvent('prop_placement:syncAll', src, GetPropList())
    DebugLog('Sync → Spieler ' .. src .. ' (' .. #GetPropList() .. ' Props)')
end)

RegisterNetEvent('prop_placement:place', function(itemName, posData)
    local src        = source
    local propConfig = Config.Props[itemName]
    local identifier = GetIdentifier(src)

    if not propConfig then
        lib.notify(src, { title = 'Fehler', description = 'Ungültiger Prop-Typ.', type = 'error' }); return
    end
    if propConfig.adminOnly and not IsAdmin(src) then
        lib.notify(src, { title = 'Keine Berechtigung', type = 'error' }); return
    end
    if not IsAdmin(src) and IsOnCooldown(identifier) then
        lib.notify(src, { title = 'Zu schnell!', type = 'warning' }); return
    end
    if Config.MaxPropsPerPlayer > 0 and not IsAdmin(src) then
        local current = CountPlayerProps(identifier)
        if current >= Config.MaxPropsPerPlayer then
            lib.notify(src, {
                title = 'Limit erreicht',
                description = ('%d/%d Props.'):format(current, Config.MaxPropsPerPlayer),
                type = 'warning'
            }); return
        end
    end
    if not IsAdmin(src) then
        local distance = #(GetEntityCoords(GetPlayerPed(src)) - vector3(posData.x, posData.y, posData.z))
        if distance > Config.Placement.MaxDistance * 1.5 then
            lib.notify(src, { title = 'Zu weit entfernt', type = 'error' }); return
        end
        if posData.z < -200.0 then
            lib.notify(src, { title = 'Ungültige Z-Koordinate', type = 'error' }); return
        end
    end

    if not exports.ox_inventory:RemoveItem(src, itemName, 1) then
        lib.notify(src, { title = 'Item nicht gefunden', type = 'error' }); return
    end

    SetCooldown(identifier)
    local propId        = nextId; nextId = nextId + 1

    -- Entity server-seitig erstellen
    local entity, netId = CreatePropEntity(propConfig.model, posData.x, posData.y, posData.z, posData.rotation or 0.0)
    if not entity then
        -- Entity-Erstellung fehlgeschlagen → Item zurückgeben
        exports.ox_inventory:AddItem(src, itemName, 1)
        lib.notify(src, { title = 'Fehler', description = 'Prop konnte nicht erstellt werden.', type = 'error' }); return
    end

    local propData = {
        id              = propId,
        itemName        = itemName,
        model           = propConfig.model,
        x               = posData.x,
        y               = posData.y,
        z               = posData.z,
        rotation        = posData.rotation or 0.0,
        ownerIdentifier = identifier,
        persistent      = propConfig.persistent,
        entity          = entity,
        netId           = netId,
    }
    placedProps[propId] = propData
    IncrementPlayerProps(identifier)

    if propConfig.persistent then
        MySQL.insert(
            'INSERT INTO prop_placement_props (id,item_name,model,x,y,z,rotation,owner_identifier,owner_job,persistent) VALUES (?,?,?,?,?,?,?,?,?,?)',
            { propId, itemName, propConfig.model, posData.x, posData.y, posData.z, posData.rotation or 0.0, identifier, nil, 1 }
        )
    end

    -- An alle Clients broadcasten (ohne server-seitigen Entity-Handle)
    TriggerClientEvent('prop_placement:propPlaced', -1, ToClientData(propData))
    lib.notify(src, { title = 'Platziert! ✅', description = propConfig.label .. ' platziert.', type = 'success' })
    LogPropAction('place', src, identifier, GetPlayerName(src) or 'Unbekannt', propId, itemName, propConfig.model,
        { x = posData.x, y = posData.y, z = posData.z, rotation = posData.rotation }, {})

    -- d4rk_livemap Integration
    pcall(function()
        exports.d4rk_livemap:AddMarker({
            id = 'prop_' .. propId,
            x = posData.x,
            y = posData.y,
            z = posData.z,
            label  = propConfig.label .. ' #' .. propId,
            color  = ({ Allgemein = '#60a5fa', Polizei = '#f87171', Baustelle = '#fbbf24', Admin = '#c084fc' })
                [propConfig.category] or '#00d4aa',
            icon   = 'box',
            group  = propConfig.category or 'Props',
            source = 'prop_placement',
        })
    end)
end)

RegisterNetEvent('prop_placement:remove', function(propId)
    local src  = source
    local prop = placedProps[propId]
    if not prop then
        lib.notify(src, { title = 'Fehler', description = 'Prop nicht gefunden.', type = 'error' }); return
    end

    local identifier = GetIdentifier(src)
    local isOwner    = prop.ownerIdentifier == identifier
    local admin      = IsAdmin(src)
    local propConfig = Config.Props[prop.itemName]

    local ownerOnly  = true
    if propConfig ~= nil and propConfig.ownerOnly ~= nil then
        ownerOnly = propConfig.ownerOnly
    end

    if not admin and ownerOnly and not isOwner then
        lib.notify(src, { title = 'Keine Berechtigung', type = 'error' }); return
    end

    exports.ox_inventory:AddItem(src, prop.itemName, 1)
    if prop.ownerIdentifier then DecrementPlayerProps(prop.ownerIdentifier) end

    -- Entity server-seitig löschen (Clients merken das automatisch)
    DeletePropEntity(prop)
    placedProps[propId] = nil
    MySQL.query('DELETE FROM prop_placement_props WHERE id = ?', { propId })
    TriggerClientEvent('prop_placement:propRemoved', -1, propId)

    lib.notify(src, {
        title = 'Entfernt ✅',
        description = (propConfig and propConfig.label or prop.itemName) .. ' ins Inventar.',
        type = 'success'
    })
    LogPropAction('remove', src, identifier, GetPlayerName(src) or 'Unbekannt', propId, prop.itemName, prop.model,
        { x = prop.x, y = prop.y, z = prop.z, rotation = prop.rotation }, { owner = prop.ownerIdentifier })

    pcall(function() exports.d4rk_livemap:RemoveMarker('prop_' .. propId) end)
end)

RegisterNetEvent('prop_placement:adminGive', function(targetId, itemName, amount)
    local src = source
    if not IsAdmin(src) then return end
    local propConfig = Config.Props[itemName]
    if not propConfig or not GetPlayerName(targetId) then return end
    amount = math.max(1, math.min(amount or 1, 99))
    exports.ox_inventory:AddItem(targetId, itemName, amount)
    lib.notify(src, {
        title = 'Item gegeben',
        description = ('%dx %s → Spieler %d'):format(amount, propConfig.label, targetId),
        type = 'success'
    })
    lib.notify(targetId, {
        title = 'Item erhalten',
        description = ('%dx %s erhalten.'):format(amount, propConfig.label),
        type = 'success'
    })
    LogPropAction('admin_give', src, GetIdentifier(src), GetPlayerName(src) or 'Unbekannt', nil, itemName, nil, nil,
        { target_id = targetId, amount = amount })
end)

RegisterNetEvent('prop_placement:adminClearAll', function()
    local src = source
    if not IsAdmin(src) then return end

    local count = 0
    local ids = {}
    for id in pairs(placedProps) do table.insert(ids, id) end
    for _, id in ipairs(ids) do
        DeletePropEntity(placedProps[id])
        placedProps[id] = nil
        count = count + 1
    end
    playerPropCount = {}
    MySQL.query('DELETE FROM prop_placement_props')
    TriggerClientEvent('prop_placement:syncAll', -1, {})
    lib.notify(src, { title = 'Props gelöscht', description = count .. ' Props entfernt.', type = 'success' })
    LogPropAction('admin_clear', src, GetIdentifier(src), GetPlayerName(src) or 'Konsole', nil, nil, nil, nil,
        { deleted_count = count })
    print(('[prop_placement] Admin %d löschte alle %d Props.'):format(src, count))
    pcall(function() exports.d4rk_livemap:ClearMarkers('prop_placement') end)
end)

RegisterNetEvent('prop_placement:adminClearPlayer', function(targetIdentifier)
    local src = source
    if not IsAdmin(src) then return end
    local removed = RemovePlayerProps(targetIdentifier)
    lib.notify(src, { title = 'Props gelöscht', description = removed .. ' Props entfernt.', type = 'success' })
end)

RegisterNetEvent('prop_placement:requestPropList', function(filterIdentifier)
    local src = source
    if not IsAdmin(src) then return end
    local list = {}
    for id, prop in pairs(placedProps) do
        if not filterIdentifier or prop.ownerIdentifier == filterIdentifier then
            table.insert(list, {
                id              = id,
                itemName        = prop.itemName,
                model           = prop.model,
                x               = prop.x,
                y               = prop.y,
                z               = prop.z,
                ownerIdentifier = prop.ownerIdentifier or 'Unbekannt',
                persistent      = prop.persistent,
            })
        end
    end
    TriggerClientEvent('prop_placement:receivePropList', src, list)
end)

RegisterNetEvent('prop_placement:requestAdminMenu', function()
    local src = source
    if IsAdmin(src) then
        TriggerClientEvent('prop_placement:openAdminMenu', src)
    else
        lib.notify(src, { title = 'Keine Berechtigung', type = 'error' })
    end
end)

RegisterNetEvent('prop_placement:reloadProps', function()
    local src = source
    if not IsAdmin(src) then
        lib.notify(src, { title = 'Keine Berechtigung', type = 'error' }); return
    end

    -- Alle bestehenden Entities löschen
    for _, prop in pairs(placedProps) do
        DeletePropEntity(prop)
    end
    placedProps     = {}
    playerPropCount = {}
    nextId          = 1

    -- Neu aus DB laden und Entities erstellen
    local result    = MySQL.query.await('SELECT * FROM prop_placement_props WHERE persistent = 1 ORDER BY id ASC')
    if result then
        for _, row in ipairs(result) do
            local id            = row.id
            local owner         = row.owner_identifier
            local entity, netId = CreatePropEntity(row.model, row.x, row.y, row.z, row.rotation)

            placedProps[id]     = {
                id              = id,
                itemName        = row.item_name,
                model           = row.model,
                x               = row.x,
                y               = row.y,
                z               = row.z,
                rotation        = row.rotation,
                ownerIdentifier = owner,
                persistent      = true,
                entity          = entity,
                netId           = netId,
            }
            if owner then playerPropCount[owner] = (playerPropCount[owner] or 0) + 1 end
            if id >= nextId then nextId = id + 1 end
        end
    end

    -- Alle Clients mit neuen NetIDs versorgen
    TriggerClientEvent('prop_placement:syncAll', -1, GetPropList())

    local count = result and #result or 0
    lib.notify(src, {
        title       = 'Props neu geladen ✅',
        description = count .. ' Props neu geladen.',
        type        = 'success',
    })
    print(('[prop_placement] Admin %d: Props neu geladen (%d Props)'):format(src, count))
end)

-- ─────────────────────────────────────────────────────────
-- Konsolen-Commands
-- ─────────────────────────────────────────────────────────

RegisterCommand('prop_clearall', function(src)
    if src ~= 0 and not IsAdmin(src) then return end
    local count = 0
    local ids = {}
    for id in pairs(placedProps) do table.insert(ids, id) end
    for _, id in ipairs(ids) do
        DeletePropEntity(placedProps[id])
        placedProps[id] = nil
        count = count + 1
    end
    playerPropCount = {}
    MySQL.query('DELETE FROM prop_placement_props')
    TriggerClientEvent('prop_placement:syncAll', -1, {})
    print(('[prop_placement] Alle %d Props gelöscht.'):format(count))
end, true)

RegisterCommand('giveprop', function(src, args)
    if src ~= 0 and not IsAdmin(src) then return end
    local itemName = args[1]
    if not itemName or not Config.Props[itemName] then return end
    local target = src
    local amount = tonumber(args[2]) or 1
    if src == 0 then
        target = tonumber(args[2]); amount = tonumber(args[3]) or 1
    end
    if not target then return end
    exports.ox_inventory:AddItem(target, itemName, amount)
    print(('[prop_placement] %dx %s → Spieler %d gegeben.'):format(amount, Config.Props[itemName].label, target))
end, false)

RegisterCommand('prop_list', function(src)
    if src ~= 0 and not IsAdmin(src) then return end
    local count = 0
    for id, prop in pairs(placedProps) do
        print(('  #%d | %s | %.1f %.1f %.1f | netId:%s | %s'):format(
            id, prop.itemName, prop.x, prop.y, prop.z,
            tostring(prop.netId), prop.ownerIdentifier or '?'))
        count = count + 1
    end
    print(('[prop_placement] Gesamt: %d Props'):format(count))
end, true)

-- Resource-Stop: Entities werden automatisch gelöscht wenn die Ressource stoppt
AddEventHandler('onResourceStop', function(resourceName)
    if GetCurrentResourceName() ~= resourceName then return end
    for _, prop in pairs(placedProps) do
        DeletePropEntity(prop)
    end
end)

-- ─────────────────────────────────────────────────────────
-- Globale Funktionen für HTTP-API (server/logger.lua)
-- ─────────────────────────────────────────────────────────

function GetAllPlacedProps()
    return placedProps
end

function RemovePropFromServer(propId)
    local prop = placedProps[propId]
    if not prop then return false, 'Prop nicht gefunden' end
    if prop.ownerIdentifier then DecrementPlayerProps(prop.ownerIdentifier) end
    DeletePropEntity(prop)
    placedProps[propId] = nil
    MySQL.query('DELETE FROM prop_placement_props WHERE id = ?', { propId })
    TriggerClientEvent('prop_placement:propRemoved', -1, propId)
    return true, prop
end
