--[[
    ╔══════════════════════════════════════════════════════╗
    ║           prop_placement – server/main.lua           ║
    ║   Validierung, Datenbank, Sync & Admin-Logik         ║
    ╚══════════════════════════════════════════════════════╝
]]

local placedProps = {}
local nextId      = 1

-- ─────────────────────────────────────────────────────────
-- Hilfsfunktionen
-- ─────────────────────────────────────────────────────────

local function DebugLog(msg)
    if Config.Debug then
        print('[prop_placement][SERVER] ' .. tostring(msg))
    end
end

local function GetIdentifier(source)
    for i = 0, GetNumPlayerIdentifiers(source) - 1 do
        local id = GetPlayerIdentifier(source, i)
        if string.sub(id, 1, 8) == 'license:' then
            return id
        end
    end
    return 'player:' .. source
end

local function IsAdmin(source)
    if source == 0 then return true end
    return IsPlayerAceAllowed(source, 'prop_placement.admin')
end

local function GetPlayerJobName(source)
    local ok, player = pcall(function()
        return exports.qbx_core:GetPlayer(source)
    end)
    if ok and player then
        return player.PlayerData.job and player.PlayerData.job.name or nil
    end
    return nil
end

local function CountPlayerProps(identifier)
    local count = 0
    for _, prop in pairs(placedProps) do
        if prop.ownerIdentifier == identifier then
            count = count + 1
        end
    end
    return count
end

local function GetPropList()
    local list = {}
    for _, prop in pairs(placedProps) do
        table.insert(list, prop)
    end
    return list
end

-- ─────────────────────────────────────────────────────────
-- Props beim Start aus DB laden
-- ─────────────────────────────────────────────────────────

CreateThread(function()
    local result = MySQL.query.await(
        'SELECT * FROM prop_placement_props WHERE persistent = 1 ORDER BY id ASC'
    )
    if result then
        for _, row in ipairs(result) do
            local id = row.id
            placedProps[id] = {
                id              = id,
                itemName        = row.item_name,
                model           = row.model,
                x               = row.x,
                y               = row.y,
                z               = row.z,
                rotation        = row.rotation,
                ownerIdentifier = row.owner_identifier,
                ownerJob        = row.owner_job,
                persistent      = true,
            }
            if id >= nextId then nextId = id + 1 end
        end
        print(('[prop_placement] %d persistente Props aus Datenbank geladen.'):format(#result))
    end
end)

-- ─────────────────────────────────────────────────────────
-- Items in ox_inventory registrieren
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
-- Item benutzen → Platzierung starten
-- ─────────────────────────────────────────────────────────

AddEventHandler('ox_inventory:usedItem', function(playerId, name, slotId, metadata)
    if not Config.Props[name] then return end
    if not playerId or playerId == 0 then return end

    DebugLog(('Item-Use: %s von Spieler %d'):format(name, playerId))
    TriggerClientEvent('prop_placement:startPlacing', playerId, name)
end)

-- ─────────────────────────────────────────────────────────
-- NET EVENT: Sync
-- ─────────────────────────────────────────────────────────

RegisterNetEvent('prop_placement:requestSync', function()
    local src = source
    TriggerClientEvent('prop_placement:syncAll', src, GetPropList())
    DebugLog(('Sync an Spieler %d (%d Props)'):format(src, #GetPropList()))
end)

-- ─────────────────────────────────────────────────────────
-- NET EVENT: Prop platzieren
-- ─────────────────────────────────────────────────────────

RegisterNetEvent('prop_placement:place', function(itemName, posData)
    local src        = source
    local propConfig = Config.Props[itemName]

    if not propConfig then
        lib.notify(src, { title = 'Fehler', description = 'Ungültiger Prop-Typ.', type = 'error' })
        return
    end

    if propConfig.adminOnly and not IsAdmin(src) then
        lib.notify(src,
            { title = 'Keine Berechtigung', description = 'Diesen Prop können nur Admins platzieren.', type = 'error' })
        return
    end

    if propConfig.jobs and not IsAdmin(src) then
        local jobName = GetPlayerJobName(src)
        local hasJob  = false
        if jobName then
            for _, allowedJob in ipairs(propConfig.jobs) do
                if allowedJob == jobName then
                    hasJob = true; break
                end
            end
        end
        if not hasJob then
            lib.notify(src, {
                title       = 'Falscher Job',
                description = 'Benötigter Job: ' .. table.concat(propConfig.jobs, ', '),
                type        = 'error',
            })
            return
        end
    end

    local identifier = GetIdentifier(src)
    if Config.MaxPropsPerPlayer > 0 and not IsAdmin(src) then
        if CountPlayerProps(identifier) >= Config.MaxPropsPerPlayer then
            lib.notify(src, {
                title       = 'Limit erreicht',
                description = ('Du hast bereits %d/%d Props platziert.'):format(
                    CountPlayerProps(identifier), Config.MaxPropsPerPlayer),
                type        = 'warning',
            })
            return
        end
    end

    local success = exports.ox_inventory:RemoveItem(src, itemName, 1)
    if not success then
        lib.notify(src,
            { title = 'Item nicht gefunden', description = 'Das Item wurde nicht in deinem Inventar gefunden.', type =
            'error' })
        return
    end

    local propId        = nextId
    nextId              = nextId + 1
    local jobName       = GetPlayerJobName(src)

    local propData      = {
        id              = propId,
        itemName        = itemName,
        model           = propConfig.model,
        x               = posData.x,
        y               = posData.y,
        z               = posData.z,
        rotation        = posData.rotation or 0.0,
        ownerIdentifier = identifier,
        ownerJob        = jobName,
        persistent      = propConfig.persistent,
    }

    placedProps[propId] = propData

    if propConfig.persistent then
        MySQL.insert(
            [[INSERT INTO prop_placement_props
              (id, item_name, model, x, y, z, rotation, owner_identifier, owner_job, persistent)
              VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?)]],
            { propId, itemName, propConfig.model,
                posData.x, posData.y, posData.z, posData.rotation or 0.0,
                identifier, jobName, 1 }
        )
    end

    TriggerClientEvent('prop_placement:propPlaced', -1, propData)

    lib.notify(src, {
        title       = 'Platziert! ✅',
        description = propConfig.label .. ' wurde erfolgreich platziert.',
        type        = 'success',
    })

    LogPropAction('place', src, identifier, GetPlayerName(src) or 'Unbekannt',
        propId, itemName, propConfig.model,
        { x = posData.x, y = posData.y, z = posData.z, rotation = posData.rotation },
        { job = jobName }
    )

    DebugLog(('Prop #%d (%s) von Spieler %d platziert.'):format(propId, itemName, src))
end)

-- ─────────────────────────────────────────────────────────
-- NET EVENT: Prop entfernen
-- ─────────────────────────────────────────────────────────

RegisterNetEvent('prop_placement:remove', function(propId)
    local src  = source
    local prop = placedProps[propId]

    if not prop then
        lib.notify(src, { title = 'Fehler', description = 'Prop nicht gefunden.', type = 'error' })
        return
    end

    local identifier = GetIdentifier(src)
    local isOwner    = prop.ownerIdentifier == identifier
    local admin      = IsAdmin(src)
    local propConfig = Config.Props[prop.itemName]
    local ownerOnly  = propConfig and propConfig.ownerOnly or true

    if not admin and not isOwner and ownerOnly then
        lib.notify(src,
            { title = 'Keine Berechtigung', description = 'Nur der Besitzer oder ein Admin kann diesen Prop entfernen.', type =
            'error' })
        return
    end

    if not admin and not isOwner and not ownerOnly then
        local playerJob = GetPlayerJobName(src)
        local allowed   = false
        if prop.ownerJob and playerJob and prop.ownerJob == playerJob then
            allowed = true
        end
        if propConfig and propConfig.jobs then
            for _, j in ipairs(propConfig.jobs) do
                if j == playerJob then allowed = true end
            end
        end
        if not allowed then
            lib.notify(src,
                { title = 'Keine Berechtigung', description = 'Du kannst diesen Prop nicht entfernen.', type = 'error' })
            return
        end
    end

    exports.ox_inventory:AddItem(src, prop.itemName, 1)
    placedProps[propId] = nil
    MySQL.query('DELETE FROM prop_placement_props WHERE id = ?', { propId })
    TriggerClientEvent('prop_placement:propRemoved', -1, propId)

    lib.notify(src, {
        title       = 'Entfernt ✅',
        description = (propConfig and propConfig.label or prop.itemName) .. ' zurück ins Inventar gelegt.',
        type        = 'success',
    })

    LogPropAction('remove', src, GetIdentifier(src), GetPlayerName(src) or 'Unbekannt',
        propId, prop.itemName, prop.model,
        { x = prop.x, y = prop.y, z = prop.z, rotation = prop.rotation },
        { removed_by = GetIdentifier(src), owner = prop.ownerIdentifier }
    )

    DebugLog(('Prop #%d von Spieler %d entfernt.'):format(propId, src))
end)

-- ─────────────────────────────────────────────────────────
-- NET EVENT: Admin – Item geben
-- ─────────────────────────────────────────────────────────

RegisterNetEvent('prop_placement:adminGive', function(targetId, itemName, amount)
    local src = source
    if not IsAdmin(src) then
        lib.notify(src, { title = 'Keine Berechtigung', type = 'error' })
        return
    end

    local propConfig = Config.Props[itemName]
    if not propConfig then
        lib.notify(src, { title = 'Fehler', description = 'Unbekanntes Item: ' .. itemName, type = 'error' })
        return
    end
    if not GetPlayerName(targetId) then
        lib.notify(src, { title = 'Fehler', description = 'Spieler ' .. targetId .. ' nicht gefunden.', type = 'error' })
        return
    end

    amount = math.max(1, math.min(amount or 1, 99))
    exports.ox_inventory:AddItem(targetId, itemName, amount)

    lib.notify(src,
        { title = 'Item gegeben', description = ('%dx %s → Spieler %d'):format(amount, propConfig.label, targetId), type =
        'success' })
    lib.notify(targetId,
        { title = 'Item erhalten', description = ('Du hast %dx %s erhalten.'):format(amount, propConfig.label), type =
        'success' })

    LogPropAction('admin_give', src, GetIdentifier(src), GetPlayerName(src) or 'Unbekannt',
        nil, itemName, nil, nil,
        { target_id = targetId, target_name = GetPlayerName(targetId), amount = amount }
    )
end)

-- ─────────────────────────────────────────────────────────
-- NET EVENT: Admin – Alle Props löschen
-- ─────────────────────────────────────────────────────────

RegisterNetEvent('prop_placement:adminClearAll', function()
    local src = source
    if not IsAdmin(src) then
        lib.notify(src, { title = 'Keine Berechtigung', type = 'error' })
        return
    end

    local count = 0
    for id in pairs(placedProps) do
        placedProps[id] = nil
        count = count + 1
    end

    MySQL.query('DELETE FROM prop_placement_props')
    TriggerClientEvent('prop_placement:syncAll', -1, {})

    lib.notify(src, { title = 'Props gelöscht', description = count .. ' Props wurden entfernt.', type = 'success' })

    LogPropAction('admin_clear', src, GetIdentifier(src), GetPlayerName(src) or 'Konsole',
        nil, nil, nil, nil, { deleted_count = count }
    )

    print(('[prop_placement] Admin %d löschte alle %d Props.'):format(src, count))
end)

-- ─────────────────────────────────────────────────────────
-- NET EVENT: Admin-Menü
-- ─────────────────────────────────────────────────────────

RegisterNetEvent('prop_placement:requestAdminMenu', function()
    local src = source
    if IsAdmin(src) then
        TriggerClientEvent('prop_placement:openAdminMenu', src)
    else
        lib.notify(src,
            { title = 'Keine Berechtigung', description = 'Das Admin-Menü ist nur für Admins zugänglich.', type = 'error' })
    end
end)

-- ─────────────────────────────────────────────────────────
-- Konsolen-Befehle
-- ─────────────────────────────────────────────────────────

RegisterCommand('prop_clearall', function(src)
    if src ~= 0 and not IsAdmin(src) then return end
    local count = 0
    for id in pairs(placedProps) do
        placedProps[id] = nil
        count = count + 1
    end
    MySQL.query('DELETE FROM prop_placement_props')
    TriggerClientEvent('prop_placement:syncAll', -1, {})
    print(('[prop_placement] Alle %d Props gelöscht.'):format(count))
end, true)

RegisterCommand('giveprop', function(src, args)
    if src ~= 0 and not IsAdmin(src) then
        lib.notify(src, { title = 'Keine Berechtigung', type = 'error' })
        return
    end

    local itemName = args[1]
    local amount   = tonumber(args[2]) or 1

    if not itemName then
        if src == 0 then
            print('[prop_placement] Verwendung: giveprop <item_name> <spieler_id> [menge]')
        else
            lib.notify(src, { title = 'Verwendung', description = '/giveprop <item> [menge]', type = 'inform' })
        end
        return
    end

    if not Config.Props[itemName] then
        local msg = 'Unbekanntes Item: ' .. itemName
        if src == 0 then
            print('[prop_placement] ' .. msg)
        else
            lib.notify(src, { title = 'Fehler', description = msg, type = 'error' })
        end
        return
    end

    local target = src
    if src == 0 then
        target = tonumber(args[2])
        amount = tonumber(args[3]) or 1
        if not target then
            print('[prop_placement] Konsole: giveprop <item_name> <spieler_id> [menge]')
            return
        end
    end

    exports.ox_inventory:AddItem(target, itemName, amount)

    local label = Config.Props[itemName].label
    if src ~= 0 then
        lib.notify(src,
            { title = 'Item erhalten ✅', description = ('%dx %s ins Inventar gelegt.'):format(amount, label), type =
            'success' })
    else
        print(('[prop_placement] %dx %s → Spieler %d gegeben.'):format(amount, label, target))
    end
end, false)

RegisterCommand('prop_list', function(src)
    if src ~= 0 and not IsAdmin(src) then return end
    local count = 0
    for id, prop in pairs(placedProps) do
        print(('  #%d | %s | %.1f %.1f %.1f | %s'):format(
            id, prop.itemName, prop.x, prop.y, prop.z, prop.ownerIdentifier or '?'))
        count = count + 1
    end
    print(('[prop_placement] Gesamt: %d Props'):format(count))
end, true)
