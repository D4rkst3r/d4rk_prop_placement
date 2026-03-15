--[[
    ╔══════════════════════════════════════════════════════╗
    ║           prop_placement – server/main.lua           ║
    ║   Validierung, Datenbank, Sync & Admin-Logik         ║
    ╚══════════════════════════════════════════════════════╝
]]

-- Server-seitige Prop-Tabelle: [propId (int)] = propData (table)
local placedProps = {}
local nextId      = 1 -- Wird beim Start aus DB geladen

-- ─────────────────────────────────────────────────────────
-- Hilfsfunktionen
-- ─────────────────────────────────────────────────────────

local function DebugLog(msg)
    if Config.Debug then
        print('[prop_placement][SERVER] ' .. tostring(msg))
    end
end

--- Ermittelt den License-Identifier eines Spielers
--- @param source number
--- @return string
local function GetIdentifier(source)
    for i = 0, GetNumPlayerIdentifiers(source) - 1 do
        local id = GetPlayerIdentifier(source, i)
        if string.sub(id, 1, 8) == 'license:' then
            return id
        end
    end
    return 'player:' .. source
end

--- Prüft ob Spieler Admin-Rechte hat (via Ace Permissions)
--- @param source number
--- @return bool
local function IsAdmin(source)
    if source == 0 then return true end -- Konsole
    return IsPlayerAceAllowed(source, 'prop_placement.admin')
end

--- Job-Abfrage via qbx_core
--- @param source number
--- @return string|nil  Job-Name oder nil
local function GetPlayerJobName(source)
    local ok, player = pcall(function()
        return exports.qbx_core:GetPlayer(source)
    end)
    if ok and player then
        return player.PlayerData.job and player.PlayerData.job.name or nil
    end
    return nil
end

--- Wie viele Props hat ein Spieler gerade platziert?
--- @param identifier string
--- @return number
local function CountPlayerProps(identifier)
    local count = 0
    for _, prop in pairs(placedProps) do
        if prop.ownerIdentifier == identifier then
            count = count + 1
        end
    end
    return count
end

--- Props als flaches Array für Client-Sync liefern
--- @return table
local function GetPropList()
    local list = {}
    for _, prop in pairs(placedProps) do
        table.insert(list, prop)
    end
    return list
end

-- ─────────────────────────────────────────────────────────
-- Persistente Props beim Start aus Datenbank laden
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
-- ox_inventory – Items per Export registrieren (falls unterstuetzt)
-- Fallback: Items muessen in ox_inventory/data/items.lua stehen
-- ---------------------------------------------------------

CreateThread(function()
    Wait(500)

    -- Pruefen ob ox_inventory registerItems unterstuetzt
    local ok, err = pcall(function()
        local resourceName = GetCurrentResourceName()
        local items = {}
        for itemName, cfg in pairs(Config.Props) do
            local iconPath = ('nui://%s/web/images/%s.png'):format(resourceName, itemName)
            items[itemName] = {
                label  = cfg.label,
                weight = cfg.weight or 1000,
                stack  = true,
                close  = true,
                image  = iconPath,
            }
        end
        exports.ox_inventory:Items(items)
    end)

    if ok then
        print('[prop_placement] ox_inventory: Items automatisch registriert.')
    else
        print('[prop_placement] HINWEIS: Items konnten nicht automatisch registriert werden.')
        print('[prop_placement] Bitte die Items aus shared/props.lua manuell in ox_inventory/data/items.lua eintragen.')
    end
end)

-- ---------------------------------------------------------
-- ox_inventory – Item-Use Hooks (einer pro Prop-Typ)
-- ─────────────────────────────────────────────────────────

CreateThread(function()
    Wait(500)

    for itemName, _ in pairs(Config.Props) do
        local name = itemName -- Closure-Variable sichern

        exports.ox_inventory:registerUsableItem(name, function(source)
            local src = source
            if not src or src == 0 then return end

            DebugLog(('Item-Use: %s von Spieler %d'):format(name, src))
            TriggerClientEvent('prop_placement:startPlacing', src, name)
        end)
    end

    DebugLog('Usable Items registriert für alle Props.')
end)

-- ─────────────────────────────────────────────────────────
-- NET EVENT: Sync anfordern (beim Client-Spawn)
-- ─────────────────────────────────────────────────────────

RegisterNetEvent('prop_placement:requestSync', function()
    local src = source
    TriggerClientEvent('prop_placement:syncAll', src, GetPropList())
    DebugLog(('Sync an Spieler %d gesendet (%d Props)'):format(src, #GetPropList()))
end)

-- ─────────────────────────────────────────────────────────
-- NET EVENT: Prop platzieren
-- ─────────────────────────────────────────────────────────

RegisterNetEvent('prop_placement:place', function(itemName, posData)
    local src        = source
    local propConfig = Config.Props[itemName]

    -- ── Validierung ──────────────────────────────────────

    if not propConfig then
        lib.notify(src, { title = 'Fehler', description = 'Ungültiger Prop-Typ.', type = 'error' })
        return
    end

    -- Admin-Only Prüfung
    if propConfig.adminOnly and not IsAdmin(src) then
        lib.notify(src,
            { title = 'Keine Berechtigung', description = 'Diesen Prop können nur Admins platzieren.', type = 'error' })
        return
    end

    -- Job-Prüfung
    if propConfig.jobs and not IsAdmin(src) then
        local jobName = GetPlayerJobName(src)
        local hasJob  = false

        if jobName then
            for _, allowedJob in ipairs(propConfig.jobs) do
                if allowedJob == jobName then
                    hasJob = true
                    break
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

    -- Prop-Limit prüfen
    local identifier = GetIdentifier(src)
    if Config.MaxPropsPerPlayer > 0 and not IsAdmin(src) then
        if CountPlayerProps(identifier) >= Config.MaxPropsPerPlayer then
            lib.notify(src, {
                title       = 'Limit erreicht',
                description = ('Du hast bereits %d/%d Props platziert.'):format(
                    CountPlayerProps(identifier), Config.MaxPropsPerPlayer
                ),
                type        = 'warning',
            })
            return
        end
    end

    -- Item aus Inventar nehmen
    local success = exports.ox_inventory:RemoveItem(src, itemName, 1)
    if not success then
        lib.notify(src, {
            title       = 'Item nicht gefunden',
            description = 'Das Item wurde nicht in deinem Inventar gefunden.',
            type        = 'error',
        })
        return
    end

    -- ── Prop erstellen ────────────────────────────────────

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

    -- ── Datenbank speichern (nur wenn persistent) ─────────
    if propConfig.persistent then
        MySQL.insert(
            [[INSERT INTO prop_placement_props
              (id, item_name, model, x, y, z, rotation, owner_identifier, owner_job, persistent)
              VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?)]],
            {
                propId, itemName, propConfig.model,
                posData.x, posData.y, posData.z,
                posData.rotation or 0.0,
                identifier, jobName, 1,
            }
        )
    end

    -- ── An alle Clients broadcasten ────────────────────────
    TriggerClientEvent('prop_placement:propPlaced', -1, propData)

    lib.notify(src, {
        title       = 'Platziert! ✅',
        description = propConfig.label .. ' wurde erfolgreich platziert.',
        type        = 'success',
    })

    -- Logging
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

    -- Job-Check: gleicher Job darf entfernen wenn ownerOnly = false
    if not admin and not isOwner and ownerOnly then
        lib.notify(src, {
            title       = 'Keine Berechtigung',
            description = 'Nur der Besitzer oder ein Admin kann diesen Prop entfernen.',
            type        = 'error',
        })
        return
    end

    if not admin and not isOwner and not ownerOnly then
        -- Selben Job prüfen
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

    -- Item zurückgeben
    exports.ox_inventory:AddItem(src, prop.itemName, 1)

    -- Aus Memory & DB entfernen
    placedProps[propId] = nil
    MySQL.query('DELETE FROM prop_placement_props WHERE id = ?', { propId })

    -- An alle broadcasten
    TriggerClientEvent('prop_placement:propRemoved', -1, propId)

    lib.notify(src, {
        title       = 'Entfernt ✅',
        description = (propConfig and propConfig.label or prop.itemName) .. ' zurück ins Inventar gelegt.',
        type        = 'success',
    })

    -- Logging
    LogPropAction('remove', src, GetIdentifier(src), GetPlayerName(src) or 'Unbekannt',
        propId, prop.itemName, prop.model,
        { x = prop.x, y = prop.y, z = prop.z, rotation = prop.rotation },
        { removed_by = GetIdentifier(src), owner = prop.ownerIdentifier }
    )

    DebugLog(('Prop #%d von Spieler %d entfernt.'):format(propId, src))
end)

-- ─────────────────────────────────────────────────────────
-- NET EVENT: Admin – Prop-Item geben
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

    lib.notify(src, {
        title       = 'Item gegeben',
        description = ('%dx %s → Spieler %d'):format(amount, propConfig.label, targetId),
        type        = 'success',
    })
    lib.notify(targetId, {
        title       = 'Item erhalten',
        description = ('Du hast %dx %s erhalten.'):format(amount, propConfig.label),
        type        = 'success',
    })

    -- Logging
    LogPropAction('admin_give', src, GetIdentifier(src), GetPlayerName(src) or 'Unbekannt',
        nil, itemName, nil, nil,
        { target_id = targetId, target_name = GetPlayerName(targetId), amount = amount }
    )

    DebugLog(('Admin %d gab %dx %s an Spieler %d'):format(src, amount, itemName, targetId))
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

    lib.notify(src, {
        title       = 'Props gelöscht',
        description = count .. ' Props wurden entfernt.',
        type        = 'success',
    })

    -- Logging
    LogPropAction('admin_clear', src, GetIdentifier(src), GetPlayerName(src) or 'Konsole',
        nil, nil, nil, nil, { deleted_count = count }
    )

    print(('[prop_placement] Admin %d löschte alle %d Props.'):format(src, count))
end)

-- ─────────────────────────────────────────────────────────
-- NET EVENT: Admin-Menü anfordern
-- ─────────────────────────────────────────────────────────

RegisterNetEvent('prop_placement:requestAdminMenu', function()
    local src = source
    if IsAdmin(src) then
        TriggerClientEvent('prop_placement:openAdminMenu', src)
    else
        lib.notify(src, {
            title       = 'Keine Berechtigung',
            description = 'Das Admin-Menü ist nur für Admins zugänglich.',
            type        = 'error',
        })
    end
end)

-- ─────────────────────────────────────────────────────────
-- Server-Konsolen-Befehle (für Admins in der Konsole / RCON)
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
    print(('[prop_placement] Alle %d Props gelöscht (Konsolenbefehl).'):format(count))
end, true)

-- /giveprop [item] [menge] – gibt sich selbst ein Prop-Item (nur Admins & Konsole)
RegisterCommand('giveprop', function(src, args)
    if src ~= 0 and not IsAdmin(src) then
        lib.notify(src, { title = 'Keine Berechtigung', type = 'error' })
        return
    end

    local itemName = args[1]
    local amount   = tonumber(args[2]) or 1

    if not itemName then
        if src == 0 then
            print('[prop_placement] Verwendung: giveprop <item_name> [menge]')
            print('[prop_placement] Verfügbare Items:')
            for name in pairs(Config.Props) do print('  - ' .. name) end
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

    -- Bei Konsolenbefehl muss eine Ziel-ID angegeben werden
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
        lib.notify(src, {
            title       = 'Item erhalten ✅',
            description = ('%dx %s ins Inventar gelegt.'):format(amount, label),
            type        = 'success',
        })
    else
        print(('[prop_placement] %dx %s → Spieler %d gegeben.'):format(amount, label, target))
    end
end, false) -- false = auch ohne Ace erlaubt, Prüfung passiert im Code

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
