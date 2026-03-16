--[[
    ╔══════════════════════════════════════════════════════╗
    ║         prop_placement – server/logger.lua           ║
    ║     Datenbank-Logging + REST API + Web-Dashboard     ║
    ╚══════════════════════════════════════════════════════╝

    ENDPUNKTE:
    ──────────
    GET /prop_placement/dashboard  → Web-Dashboard (kein Key nötig)
    GET /prop_placement/health     → Health-Check
    GET /prop_placement/stats      → Statistiken
    GET /prop_placement/logs       → Logs (paginiert)

    AUTH:
    ─────
    Header:      X-Api-Key: dein_key
    Query-Param: ?api_key=dein_key
]]

Config.Logging = {
    Enabled   = true,
    ApiKey    = 'Z9ijq5p2rfk6BNVa6Vcv0OPqvMN5mkH3', -- ÄNDERN!
    PageSize  = 50,
    AutoPurge = 30,
}

-- ─────────────────────────────────────────────────────────
-- Hilfsfunktionen
-- ─────────────────────────────────────────────────────────

local function JsonResponse(res, status, data)
    res.writeHead(status, { ['Content-Type'] = 'application/json' })
    res.send(json.encode(data))
end

local function HtmlResponse(res, html)
    res.writeHead(200, { ['Content-Type'] = 'text/html; charset=utf-8' })
    res.send(html)
end

local function ParseRequest(fullPath)
    local path     = fullPath:match('^([^%?]+)') or fullPath
    local query    = {}
    local queryStr = fullPath:match('%?(.+)$')
    if queryStr then
        for key, value in queryStr:gmatch('([^&=]+)=([^&]*)') do
            query[key] = value
        end
    end
    return path, query
end

local function CheckApiKey(req, query)
    local key = (req.headers and req.headers['x-api-key']) or query['api_key']
    return key == Config.Logging.ApiKey
end

-- ─────────────────────────────────────────────────────────
-- Logging-Funktion
-- ─────────────────────────────────────────────────────────

function LogPropAction(action, source, identifier, playerName, propId, itemName, model, coords, extra)
    if not Config.Logging.Enabled then return end

    local coordsJson = coords and json.encode(coords) or nil
    local extraJson  = extra and json.encode(extra) or nil

    MySQL.insert(
        [[INSERT INTO prop_placement_logs
          (action, server_id, identifier, player_name, prop_id, item_name, model, coords, extra)
          VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)]],
        { action, source, identifier, playerName, propId, itemName, model, coordsJson, extraJson }
    )

    if Config.Debug then
        print(('[prop_placement][LOG] %s | %s | Item: %s | PropID: %s'):format(
            action, playerName, tostring(itemName), tostring(propId)
        ))
    end
end

-- ─────────────────────────────────────────────────────────
-- Auto-Purge
-- ─────────────────────────────────────────────────────────

if Config.Logging.Enabled and Config.Logging.AutoPurge > 0 then
    CreateThread(function()
        while true do
            Wait(3600 * 1000)
            local deleted = MySQL.query.await(
                'DELETE FROM prop_placement_logs WHERE created_at < (NOW() - INTERVAL ? DAY)',
                { Config.Logging.AutoPurge }
            )
            if deleted and deleted.affectedRows and deleted.affectedRows > 0 then
                print(('[prop_placement] Auto-Purge: %d Logs gelöscht.'):format(deleted.affectedRows))
            end
        end
    end)
end

-- ─────────────────────────────────────────────────────────
-- Web-Dashboard HTML
-- Wichtig: kein string.format verwenden da % im HTML Probleme macht
-- Stattdessen __API_KEY__ Platzhalter und gsub
-- ─────────────────────────────────────────────────────────

local DASHBOARD_HTML = [[<!DOCTYPE html>
<html lang="de">
<head>
<meta charset="UTF-8">
<meta name="viewport" content="width=device-width, initial-scale=1.0">
<title>prop_placement Dashboard</title>
<style>
  * { box-sizing: border-box; margin: 0; padding: 0; }
  body { font-family: 'Segoe UI', sans-serif; background: #0f1117; color: #e2e8f0; min-height: 100vh; }
  header { background: #1a1d2e; border-bottom: 1px solid #2d3748; padding: 16px 32px; display: flex; align-items: center; gap: 12px; }
  header h1 { font-size: 1.25rem; font-weight: 600; }
  .badge { background: #2d3748; padding: 2px 8px; border-radius: 12px; font-size: 0.75rem; }
  .badge.green { background: #1a3a2a; color: #68d391; }
  .badge.red   { background: #3a1a1a; color: #fc8181; }
  .container { padding: 24px 32px; max-width: 1400px; margin: 0 auto; }
  .grid { display: grid; grid-template-columns: repeat(auto-fit, minmax(200px, 1fr)); gap: 16px; margin-bottom: 24px; }
  .card { background: #1a1d2e; border: 1px solid #2d3748; border-radius: 8px; padding: 20px; }
  .card h3 { font-size: 0.8rem; color: #718096; text-transform: uppercase; letter-spacing: 0.05em; margin-bottom: 8px; }
  .card .value { font-size: 2rem; font-weight: 700; color: #63b3ed; }
  .section { background: #1a1d2e; border: 1px solid #2d3748; border-radius: 8px; margin-bottom: 24px; overflow: hidden; }
  .section-header { padding: 16px 20px; border-bottom: 1px solid #2d3748; display: flex; justify-content: space-between; align-items: center; }
  .section-header h2 { font-size: 0.95rem; font-weight: 600; }
  .filters { display: flex; gap: 8px; flex-wrap: wrap; }
  .filters select, .filters input { background: #2d3748; border: 1px solid #4a5568; color: #e2e8f0; padding: 6px 10px; border-radius: 6px; font-size: 0.85rem; outline: none; }
  table { width: 100%; border-collapse: collapse; font-size: 0.85rem; }
  th { padding: 10px 16px; text-align: left; font-weight: 500; color: #718096; font-size: 0.75rem; text-transform: uppercase; border-bottom: 1px solid #2d3748; }
  td { padding: 10px 16px; border-bottom: 1px solid #1e2235; }
  tr:last-child td { border-bottom: none; }
  tr:hover td { background: #1e2235; }
  .action-badge { padding: 2px 8px; border-radius: 4px; font-size: 0.75rem; font-weight: 500; }
  .action-place       { background: #1a3a2a; color: #68d391; }
  .action-remove      { background: #3a1a1a; color: #fc8181; }
  .action-admin_give  { background: #1a2a3a; color: #63b3ed; }
  .action-admin_clear { background: #3a2a1a; color: #f6ad55; }
  .pagination { display: flex; gap: 8px; padding: 12px 16px; justify-content: center; border-top: 1px solid #2d3748; flex-wrap: wrap; }
  .pagination button { background: #2d3748; border: none; color: #e2e8f0; padding: 6px 12px; border-radius: 6px; cursor: pointer; font-size: 0.85rem; }
  .pagination button:hover { background: #4a5568; }
  .pagination button.active { background: #3182ce; }
  .pagination button:disabled { opacity: 0.4; cursor: default; }
  .loading { text-align: center; padding: 40px; color: #718096; }
  .top-list { padding: 8px 0; }
  .top-item { display: flex; justify-content: space-between; padding: 8px 20px; border-bottom: 1px solid #1e2235; font-size: 0.85rem; }
  .top-item:last-child { border-bottom: none; }
  .top-item .count { color: #63b3ed; font-weight: 600; }
  .refresh-btn { background: #2d3748; border: 1px solid #4a5568; color: #e2e8f0; padding: 6px 12px; border-radius: 6px; cursor: pointer; font-size: 0.8rem; margin-left: auto; }
  .refresh-btn:hover { background: #4a5568; }
  #statusDot { width: 8px; height: 8px; border-radius: 50%; background: #68d391; display: inline-block; }
  #statusDot.offline { background: #fc8181; }
  .two-col { display: grid; grid-template-columns: 1fr 1fr; gap: 16px; margin-bottom: 24px; }
</style>
</head>
<body>
<header>
  <span id="statusDot"></span>
  <h1>🧱 prop_placement</h1>
  <span class="badge" id="serverStatus">Verbinde...</span>
  <button class="refresh-btn" onclick="loadAll()">↻ Aktualisieren</button>
</header>
<div class="container">
  <div class="grid">
    <div class="card"><h3>Logs gesamt</h3><div class="value" id="statTotal">–</div></div>
    <div class="card"><h3>Letzte 24h</h3><div class="value" id="stat24h">–</div></div>
    <div class="card"><h3>Platzierungen</h3><div class="value" id="statPlace">–</div></div>
    <div class="card"><h3>Entfernungen</h3><div class="value" id="statRemove">–</div></div>
  </div>

  <div class="two-col">
    <div class="section">
      <div class="section-header"><h2>🏆 Top Props</h2></div>
      <div class="top-list" id="topItems"><div class="loading">Lädt...</div></div>
    </div>
    <div class="section">
      <div class="section-header"><h2>👤 Top Spieler</h2></div>
      <div class="top-list" id="topPlacers"><div class="loading">Lädt...</div></div>
    </div>
  </div>

  <div class="section">
    <div class="section-header">
      <h2>📋 Logs</h2>
      <div class="filters">
        <select id="filterAction" onchange="currentPage=1;loadLogs()">
          <option value="">Alle Aktionen</option>
          <option value="place">Platziert</option>
          <option value="remove">Entfernt</option>
          <option value="admin_give">Admin Give</option>
          <option value="admin_clear">Admin Clear</option>
        </select>
        <input id="filterItem"   placeholder="Item..."    oninput="currentPage=1;loadLogs()" style="width:130px">
        <input id="filterPlayer" placeholder="Spieler..." oninput="currentPage=1;loadLogs()" style="width:130px">
      </div>
    </div>
    <div id="logsTable"><div class="loading">Lädt...</div></div>
    <div class="pagination" id="pagination"></div>
  </div>
</div>

<script>
const API_KEY = '__API_KEY__';
const BASE    = window.location.origin;
let currentPage = 1;

async function apiFetch(path) {
  const sep = path.includes('?') ? '&' : '?';
  const res = await fetch(BASE + path + sep + 'api_key=' + API_KEY);
  return res.json();
}

async function loadHealth() {
  try {
    const d = await apiFetch('/prop_placement/health');
    const dot   = document.getElementById('statusDot');
    const badge = document.getElementById('serverStatus');
    if (d.status === 'ok') {
      dot.className   = '';
      badge.textContent = 'Online – Uptime: ' + Math.floor(d.uptime) + 's';
      badge.className = 'badge green';
    } else {
      dot.className   = 'offline';
      badge.textContent = 'Fehler';
      badge.className = 'badge red';
    }
  } catch(e) {
    document.getElementById('statusDot').className       = 'offline';
    document.getElementById('serverStatus').textContent  = 'Offline';
    document.getElementById('serverStatus').className    = 'badge red';
  }
}

async function loadStats() {
  try {
    const d = await apiFetch('/prop_placement/stats');
    document.getElementById('statTotal').textContent  = d.total_logs ?? '–';
    document.getElementById('stat24h').textContent    = d.last_24h   ?? '–';
    const place  = (d.by_action || []).find(a => a.action === 'place');
    const remove = (d.by_action || []).find(a => a.action === 'remove');
    document.getElementById('statPlace').textContent  = place  ? place.count  : 0;
    document.getElementById('statRemove').textContent = remove ? remove.count : 0;

    document.getElementById('topItems').innerHTML =
      (d.top_items || []).map(i =>
        '<div class="top-item"><span>' + i.item_name + '</span><span class="count">' + i.count + 'x</span></div>'
      ).join('') || '<div class="loading">Keine Daten</div>';

    document.getElementById('topPlacers').innerHTML =
      (d.top_placers || []).map(p =>
        '<div class="top-item"><span>' + (p.player_name || '?') + '</span><span class="count">' + p.count + 'x</span></div>'
      ).join('') || '<div class="loading">Keine Daten</div>';
  } catch(e) { console.error('Stats Fehler:', e); }
}

async function loadLogs() {
  const action = document.getElementById('filterAction').value;
  const item   = document.getElementById('filterItem').value;
  const player = document.getElementById('filterPlayer').value;

  let url = '/prop_placement/logs?page=' + currentPage;
  if (action) url += '&action=' + encodeURIComponent(action);
  if (item)   url += '&item='   + encodeURIComponent(item);
  if (player) url += '&player=' + encodeURIComponent(player);

  document.getElementById('logsTable').innerHTML = '<div class="loading">Lädt...</div>';

  try {
    const d = await apiFetch(url);
    if (!d.data || d.data.length === 0) {
      document.getElementById('logsTable').innerHTML = '<div class="loading">Keine Logs gefunden.</div>';
      document.getElementById('pagination').innerHTML = '';
      return;
    }

    const rows = d.data.map(function(log) {
      const date   = new Date(log.created_at).toLocaleString('de-DE');
      const actCls = 'action-' + log.action;
      const coords = log.coords
        ? (log.coords.x ? log.coords.x.toFixed(1) : '?') + ' / '
        + (log.coords.y ? log.coords.y.toFixed(1) : '?') + ' / '
        + (log.coords.z ? log.coords.z.toFixed(1) : '?')
        : '–';
      const shortId = log.identifier
        ? log.identifier.replace('license:', '').substring(0, 12) + '...'
        : '–';
      return '<tr>'
        + '<td>' + log.id + '</td>'
        + '<td><span class="action-badge ' + actCls + '">' + log.action + '</span></td>'
        + '<td>' + (log.player_name || '–') + '</td>'
        + '<td style="font-size:0.75rem;color:#718096">' + shortId + '</td>'
        + '<td>' + (log.item_name || '–') + '</td>'
        + '<td style="font-size:0.75rem">' + coords + '</td>'
        + '<td style="color:#718096;font-size:0.75rem">' + date + '</td>'
        + '</tr>';
    }).join('');

    document.getElementById('logsTable').innerHTML =
      '<table><thead><tr>'
      + '<th>#</th><th>Aktion</th><th>Spieler</th><th>License</th><th>Item</th><th>Position</th><th>Zeit</th>'
      + '</tr></thead><tbody>' + rows + '</tbody></table>';

    const p = d.pagination;
    let pHtml = '<button onclick="gotoPage(' + (p.page - 1) + ')"' + (p.page <= 1 ? ' disabled' : '') + '>Zurück</button>';
    const start = Math.max(1, p.page - 2);
    const end   = Math.min(p.total_pages, p.page + 2);
    for (let i = start; i <= end; i++) {
      pHtml += '<button onclick="gotoPage(' + i + ')"' + (i === p.page ? ' class="active"' : '') + '>' + i + '</button>';
    }
    pHtml += '<button onclick="gotoPage(' + (p.page + 1) + ')"' + (p.page >= p.total_pages ? ' disabled' : '') + '>Weiter</button>';
    pHtml += '<span style="color:#718096;font-size:0.8rem;margin-left:8px">' + p.total + ' Einträge</span>';
    document.getElementById('pagination').innerHTML = pHtml;
  } catch(e) {
    document.getElementById('logsTable').innerHTML = '<div class="loading">Fehler beim Laden.</div>';
    console.error('Logs Fehler:', e);
  }
}

function gotoPage(p) {
  currentPage = p;
  loadLogs();
}

function loadAll() {
  loadHealth();
  loadStats();
  loadLogs();
}

loadAll();
setInterval(loadAll, 30000);
</script>
</body>
</html>]]

local function GetDashboardHtml(apiKey)
    -- gsub statt string.format um Probleme mit % im HTML zu vermeiden
    return DASHBOARD_HTML:gsub('__API_KEY__', apiKey)
end

-- ─────────────────────────────────────────────────────────
-- HTTP API Handler
-- ─────────────────────────────────────────────────────────

SetHttpHandler(function(req, res)
    res.writeHead(200, {
        ['Access-Control-Allow-Origin']  = '*',
        ['Access-Control-Allow-Headers'] = 'X-Api-Key, Content-Type',
        ['Access-Control-Allow-Methods'] = 'GET, OPTIONS',
    })

    if req.method == 'OPTIONS' then
        res.send(''); return
    end
    if req.method ~= 'GET' then
        JsonResponse(res, 405, { error = 'Method Not Allowed' })
        return
    end

    local path, query = ParseRequest(req.path or '/')

    -- Dashboard braucht keinen API-Key
    if path == '/prop_placement/dashboard' or path == '/dashboard' then
        HtmlResponse(res, GetDashboardHtml(Config.Logging.ApiKey))
        return
    end

    if not CheckApiKey(req, query) then
        JsonResponse(res, 401, { error = 'Unauthorized - invalid or missing API key' })
        return
    end

    -- ── Health ──────────────────────────────────────────
    if path == '/prop_placement/health' or path == '/health' then
        JsonResponse(res, 200, {
            status    = 'ok',
            resource  = GetCurrentResourceName(),
            uptime    = GetGameTimer() / 1000,
            timestamp = os.time(),
        })
        return
    end

    -- ── Stats ───────────────────────────────────────────
    if path == '/prop_placement/stats' or path == '/stats' then
        local total      = MySQL.query.await('SELECT COUNT(*) as c FROM prop_placement_logs')
        local byAction   = MySQL.query.await('SELECT action, COUNT(*) as count FROM prop_placement_logs GROUP BY action')
        local topItems   = MySQL.query.await([[
            SELECT item_name, COUNT(*) as count FROM prop_placement_logs
            WHERE action = 'place' AND item_name IS NOT NULL
            GROUP BY item_name ORDER BY count DESC LIMIT 10
        ]])
        local topPlacers = MySQL.query.await([[
            SELECT player_name, identifier, COUNT(*) as count FROM prop_placement_logs
            WHERE action = 'place' GROUP BY identifier ORDER BY count DESC LIMIT 10
        ]])
        local recentDay  = MySQL.query.await([[
            SELECT COUNT(*) as c FROM prop_placement_logs
            WHERE created_at >= (NOW() - INTERVAL 24 HOUR)
        ]])

        JsonResponse(res, 200, {
            total_logs   = total and total[1] and total[1].c or 0,
            last_24h     = recentDay and recentDay[1] and recentDay[1].c or 0,
            by_action    = byAction or {},
            top_items    = topItems or {},
            top_placers  = topPlacers or {},
            generated_at = os.time(),
        })
        return
    end

    -- ── Logs ────────────────────────────────────────────
    if path == '/prop_placement/logs' or path == '/logs' then
        local page       = math.max(1, tonumber(query.page) or 1)
        local pageSize   = Config.Logging.PageSize
        local offset     = (page - 1) * pageSize

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

        local countParams = {}
        for _, v in ipairs(params) do table.insert(countParams, v) end
        local countResult = MySQL.query.await(
            'SELECT COUNT(*) as total FROM prop_placement_logs ' .. where, countParams)
        local total = countResult and countResult[1] and countResult[1].total or 0

        local dataParams = {}
        for _, v in ipairs(params) do table.insert(dataParams, v) end
        table.insert(dataParams, pageSize)
        table.insert(dataParams, offset)

        local logs = MySQL.query.await(
            'SELECT * FROM prop_placement_logs ' .. where ..
            ' ORDER BY created_at DESC LIMIT ? OFFSET ?',
            dataParams
        ) or {}

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
            data         = logs,
            pagination   = {
                page        = page,
                page_size   = pageSize,
                total       = total,
                total_pages = math.ceil(total / pageSize),
            },
            filters      = {
                action     = query.action or nil,
                item       = query.item or nil,
                identifier = query.identifier or nil,
                player     = query.player or nil,
            },
            generated_at = os.time(),
        })
        return
    end

    JsonResponse(res, 404, {
        error     = 'Not Found',
        available = {
            '/prop_placement/dashboard',
            '/prop_placement/health',
            '/prop_placement/logs',
            '/prop_placement/stats',
        }
    })
end)

print('[prop_placement] HTTP API aktiv')
print('[prop_placement] Dashboard: http://SERVER_IP:30120/prop_placement/dashboard')
