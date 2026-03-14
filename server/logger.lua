--[[
    ╔══════════════════════════════════════════════════════╗
    ║         prop_placement – server/logger.lua           ║
    ║     Datenbank-Logging + REST HTTP API Endpunkt       ║
    ╚══════════════════════════════════════════════════════╝

    API ENDPUNKTE:
    ──────────────
    GET  /prop_placement/logs               → Alle Logs (paginiert)
    GET  /prop_placement/logs?page=2        → Seite 2 (je 50 Einträge)
    GET  /prop_placement/logs?action=place  → Nur Platzierungen
    GET  /prop_placement/logs?action=remove → Nur Entfernungen
    GET  /prop_placement/logs?item=traffic_cone
    GET  /prop_placement/logs?identifier=license:abc
    GET  /prop_placement/stats              → Statistiken (Top-Items, Counts)
    GET  /prop_placement/health             → Health-Check für Monitoring

    SICHERUNG:
    ──────────
    Setze Config.Logging.ApiKey auf einen sicheren Zufallsstring!
    Alle API-Anfragen brauchen den Header:  X-Api-Key: dein_key
    Oder als Query-Param:                   ?api_key=dein_key
]]

-- ─── Logging-Konfiguration ────────────────────────────────
Config.Logging = {
    Enabled    = true,

    -- API-Schlüssel – UNBEDINGT ÄNDERN!
    -- Generiere einen zufälligen Key z.B.: https://generate-random.org/api-key-generator
    ApiKey     = 'CHANGE_ME_USE_A_SECURE_RANDOM_KEY',

    -- Port auf dem die HTTP API läuft (FiveM nutzt den Ressource-HTTP-Handler)
    -- Erreichbar über: http://SERVER_IP:30120/prop_placement/...
    -- (30120 ist der Standard-FiveM-Port – kein separater Port nötig!)

    -- Wie viele Log-Einträge pro API-Seite
    PageSize   = 50,

    -- Logs nach X Tagen automatisch löschen (0 = deaktivieren)
    AutoPurge  = 30,
}

-- ─────────────────────────────────────────────────────────
-- Hilfsfunktionen
-- ─────────────────────────────────────────────────────────

local function JsonResponse(res, status, data)
    res.writeHead(status, { ['Content-Type'] = 'application/json' })
    res.send(json.encode(data))
end

local function CheckApiKey(req)
    local key = (req.headers and req.headers['x-api-key'])
               or (req.query and req.query['api_key'])
    return key == Config.Logging.ApiKey
end

-- ─────────────────────────────────────────────────────────
-- Logging-Funktion (wird aus server/main.lua aufgerufen)
-- ─────────────────────────────────────────────────────────

--- Logt eine Prop-Aktion in die Datenbank
--- @param action      string  'place' | 'remove' | 'admin_give' | 'admin_clear'
--- @param source      number  Server-ID des Spielers (0 = Konsole)
--- @param identifier  string  License-Identifier
--- @param playerName  string  Spieler-Name
--- @param propId      number|nil
--- @param itemName    string|nil
--- @param model       string|nil
--- @param coords      table|nil  { x, y, z, rotation }
--- @param extra       table|nil  Zusätzliche Daten als JSON
function LogPropAction(action, source, identifier, playerName, propId, itemName, model, coords, extra)
    if not Config.Logging.Enabled then return end

    local coordsJson = coords and json.encode(coords) or nil
    local extraJson  = extra  and json.encode(extra)  or nil

    MySQL.insert(
        [[INSERT INTO prop_placement_logs
          (action, server_id, identifier, player_name, prop_id, item_name, model, coords, extra)
          VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)]],
        {
            action, source, identifier, playerName,
            propId, itemName, model, coordsJson, extraJson,
        }
    )

    if Config.Debug then
        print(('[prop_placement][LOG] %s | %s (%s) | Item: %s | PropID: %s'):format(
            action, playerName, identifier, tostring(itemName), tostring(propId)
        ))
    end
end

-- ─────────────────────────────────────────────────────────
-- Auto-Purge alter Logs
-- ─────────────────────────────────────────────────────────

if Config.Logging.Enabled and Config.Logging.AutoPurge > 0 then
    CreateThread(function()
        while true do
            Wait(3600 * 1000) -- jede Stunde prüfen
            local deleted = MySQL.query.await(
                'DELETE FROM prop_placement_logs WHERE created_at < (NOW() - INTERVAL ? DAY)',
                { Config.Logging.AutoPurge }
            )
            if deleted and deleted.affectedRows and deleted.affectedRows > 0 then
                print(('[prop_placement] Auto-Purge: %d Logs älter als %d Tage gelöscht.'):format(
                    deleted.affectedRows, Config.Logging.AutoPurge
                ))
            end
        end
    end)
end

-- ─────────────────────────────────────────────────────────
-- HTTP API Handler
-- ─────────────────────────────────────────────────────────

SetHttpHandler(function(req, res)
    -- CORS-Header für Web-Panels
    res.writeHead(200, {
        ['Access-Control-Allow-Origin']  = '*',
        ['Access-Control-Allow-Headers'] = 'X-Api-Key, Content-Type',
        ['Access-Control-Allow-Methods'] = 'GET, OPTIONS',
    })

    -- OPTIONS Preflight (Browser CORS)
    if req.method == 'OPTIONS' then
        res.send('')
        return
    end

    -- Nur GET erlaubt
    if req.method ~= 'GET' then
        JsonResponse(res, 405, { error = 'Method Not Allowed' })
        return
    end

    -- API-Key prüfen
    if not CheckApiKey(req) then
        JsonResponse(res, 401, { error = 'Unauthorized – invalid or missing API key' })
        return
    end

    local path  = req.path or '/'
    local query = req.query or {}

    -- ──────────────────────────────────────────────────────
    -- GET /prop_placement/health
    -- ──────────────────────────────────────────────────────
    if path == '/prop_placement/health' then
        JsonResponse(res, 200, {
            status    = 'ok',
            resource  = GetCurrentResourceName(),
            uptime    = GetGameTimer() / 1000,
            timestamp = os.time(),
        })
        return
    end

    -- ──────────────────────────────────────────────────────
    -- GET /prop_placement/stats
    -- ──────────────────────────────────────────────────────
    if path == '/prop_placement/stats' then
        local total      = MySQL.query.await('SELECT COUNT(*) as c FROM prop_placement_logs')
        local byAction   = MySQL.query.await('SELECT action, COUNT(*) as count FROM prop_placement_logs GROUP BY action')
        local topItems   = MySQL.query.await([[
            SELECT item_name, COUNT(*) as count
            FROM prop_placement_logs
            WHERE action = 'place' AND item_name IS NOT NULL
            GROUP BY item_name ORDER BY count DESC LIMIT 10
        ]])
        local topPlacers = MySQL.query.await([[
            SELECT player_name, identifier, COUNT(*) as count
            FROM prop_placement_logs
            WHERE action = 'place'
            GROUP BY identifier ORDER BY count DESC LIMIT 10
        ]])
        local recentDay  = MySQL.query.await([[
            SELECT COUNT(*) as c FROM prop_placement_logs
            WHERE created_at >= (NOW() - INTERVAL 24 HOUR)
        ]])

        JsonResponse(res, 200, {
            total_logs     = total and total[1] and total[1].c or 0,
            last_24h       = recentDay and recentDay[1] and recentDay[1].c or 0,
            by_action      = byAction  or {},
            top_items      = topItems  or {},
            top_placers    = topPlacers or {},
            generated_at   = os.time(),
        })
        return
    end

    -- ──────────────────────────────────────────────────────
    -- GET /prop_placement/logs
    -- ──────────────────────────────────────────────────────
    if path == '/prop_placement/logs' then
        local page       = math.max(1, tonumber(query.page) or 1)
        local pageSize   = Config.Logging.PageSize
        local offset     = (page - 1) * pageSize

        -- Filter aufbauen
        local conditions = {}
        local params     = {}

        if query.action and query.action ~= '' then
            table.insert(conditions, 'action = ?')
            table.insert(params, query.action)
        end
        if query.item and query.item ~= '' then
            table.insert(conditions, 'item_name = ?')
            table.insert(params, query.item)
        end
        if query.identifier and query.identifier ~= '' then
            table.insert(conditions, 'identifier = ?')
            table.insert(params, query.identifier)
        end
        if query.player and query.player ~= '' then
            table.insert(conditions, 'player_name LIKE ?')
            table.insert(params, '%' .. query.player .. '%')
        end
        if query.from and query.from ~= '' then
            table.insert(conditions, 'created_at >= ?')
            table.insert(params, query.from)
        end
        if query.to and query.to ~= '' then
            table.insert(conditions, 'created_at <= ?')
            table.insert(params, query.to)
        end

        local where = #conditions > 0 and ('WHERE ' .. table.concat(conditions, ' AND ')) or ''

        -- Gesamtanzahl für Pagination
        local countParams = {}
        for _, v in ipairs(params) do table.insert(countParams, v) end

        local countResult = MySQL.query.await(
            'SELECT COUNT(*) as total FROM prop_placement_logs ' .. where,
            countParams
        )
        local total = countResult and countResult[1] and countResult[1].total or 0

        -- Daten abfragen
        local dataParams = {}
        for _, v in ipairs(params) do table.insert(dataParams, v) end
        table.insert(dataParams, pageSize)
        table.insert(dataParams, offset)

        local logs = MySQL.query.await(
            'SELECT * FROM prop_placement_logs ' .. where ..
            ' ORDER BY created_at DESC LIMIT ? OFFSET ?',
            dataParams
        ) or {}

        -- Coords & Extra dekodieren
        for _, entry in ipairs(logs) do
            if entry.coords then
                local ok, decoded = pcall(json.decode, entry.coords)
                entry.coords = ok and decoded or entry.coords
            end
            if entry.extra then
                local ok, decoded = pcall(json.decode, entry.extra)
                entry.extra = ok and decoded or entry.extra
            end
        end

        JsonResponse(res, 200, {
            data       = logs,
            pagination = {
                page       = page,
                page_size  = pageSize,
                total      = total,
                total_pages = math.ceil(total / pageSize),
            },
            filters = {
                action     = query.action     or nil,
                item       = query.item       or nil,
                identifier = query.identifier or nil,
                player     = query.player     or nil,
                from       = query.from       or nil,
                to         = query.to         or nil,
            },
            generated_at = os.time(),
        })
        return
    end

    -- 404 für unbekannte Pfade
    JsonResponse(res, 404, { error = 'Not Found', available = {
        '/prop_placement/health',
        '/prop_placement/logs',
        '/prop_placement/stats',
    }})
end)

print('[prop_placement] HTTP API aktiv → http://SERVER_IP:30120/prop_placement/logs')
