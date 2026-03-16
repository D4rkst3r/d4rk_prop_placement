--[[
    ╔══════════════════════════════════════════════════════╗
    ║         prop_placement – server/logger.lua           ║
    ║   Logging + REST API + Dashboard                     ║
    ╚══════════════════════════════════════════════════════╝

    ENDPUNKTE:
    GET /prop_placement/dashboard          → Web-Dashboard
    GET /prop_placement/health             → Health-Check
    GET /prop_placement/stats              → Statistiken + 7-Tage-Aktivität
    GET /prop_placement/logs               → Logs (paginiert)
    GET /prop_placement/props              → Aktive Props (paginiert)
    DELETE /prop_placement/props/remove?id=X → Prop löschen
]]

Config.Logging = {
  Enabled   = true,
  ApiKey    = 'Z9ijq5p2rfk6BNVa6Vcv0OPqvMN5mkH3', -- ÄNDERN!
  PageSize  = 50,
  AutoPurge = 30,
}

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
-- Logging
-- ─────────────────────────────────────────────────────────

function LogPropAction(action, source, identifier, playerName, propId, itemName, model, coords, extra)
  if not Config.Logging.Enabled then return end
  MySQL.insert(
    'INSERT INTO prop_placement_logs (action,server_id,identifier,player_name,prop_id,item_name,model,coords,extra) VALUES (?,?,?,?,?,?,?,?,?)',
    { action, source, identifier, playerName, propId, itemName, model,
      coords and json.encode(coords) or nil,
      extra and json.encode(extra) or nil }
  )
end

-- Auto-Purge
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
-- Dashboard HTML
-- ─────────────────────────────────────────────────────────

local DASHBOARD_HTML = [==[<!DOCTYPE html>
<html lang="de">
<head>
<meta charset="UTF-8">
<meta name="viewport" content="width=device-width, initial-scale=1.0">
<title>prop_placement · Admin</title>
<link rel="preconnect" href="https://fonts.googleapis.com">
<link href="https://fonts.googleapis.com/css2?family=JetBrains+Mono:wght@400;600;700&family=Syne:wght@400;600;700;800&display=swap" rel="stylesheet">
<script src="https://cdnjs.cloudflare.com/ajax/libs/Chart.js/4.4.1/chart.umd.min.js"></script>
<style>
:root {
  --bg:#07080f; --s1:#0d0f1a; --s2:#12162a; --s3:#181d31;
  --border:#1e2540; --border2:#252d45;
  --text:#c8d0e8; --muted:#4a5275;
  --teal:#00d4aa; --teal2:#00a884;
  --amber:#f59e0b; --red:#f43f5e; --blue:#3b82f6; --purple:#a78bfa; --green:#22c55e;
}
*{box-sizing:border-box;margin:0;padding:0}
body{font-family:'Syne',sans-serif;background:var(--bg);color:var(--text);min-height:100vh}
header{background:var(--s1);border-bottom:1px solid var(--border);padding:0 28px;height:54px;display:flex;align-items:center;gap:14px;position:sticky;top:0;z-index:200}
.logo{font-size:1rem;font-weight:800;letter-spacing:-.03em;color:#fff;display:flex;align-items:center;gap:8px}
.logo-icon{width:28px;height:28px;background:linear-gradient(135deg,var(--teal),var(--blue));border-radius:6px;display:flex;align-items:center;justify-content:center;font-size:14px}
.dot{width:7px;height:7px;border-radius:50%;background:var(--teal);box-shadow:0 0 8px var(--teal);flex-shrink:0}
.dot.dead{background:var(--red);box-shadow:0 0 8px var(--red)}
.mono{font-family:'JetBrains Mono',monospace}
#uptime{font-family:'JetBrains Mono',monospace;font-size:.72rem;color:var(--muted)}
.hdr-right{margin-left:auto;display:flex;align-items:center;gap:8px}
.pill{font-size:.7rem;font-weight:600;padding:3px 10px;border-radius:20px;border:1px solid}
.pill-teal{color:var(--teal);border-color:var(--teal2);background:#00d4aa15}
.pill-red{color:var(--red);border-color:#7f1d2a;background:#f43f5e10}
.pill-gray{color:var(--muted);border-color:var(--border);background:var(--s2)}
.btn{background:var(--s3);border:1px solid var(--border2);color:var(--text);padding:7px 14px;border-radius:8px;cursor:pointer;font-size:.78rem;font-family:'Syne',sans-serif;font-weight:600;transition:all .15s;letter-spacing:.01em}
.btn:hover{background:var(--border);border-color:#2e3760}
.btn-red{background:#1a0810;border-color:#7f1d2a;color:var(--red)}
.btn-red:hover{background:#240b14}
.btn-sm{padding:4px 10px;font-size:.72rem}
.wrap{padding:20px 28px;max-width:1700px;margin:0 auto}
.stat-row{display:grid;grid-template-columns:repeat(5,1fr);gap:12px;margin-bottom:20px}
.scard{background:var(--s1);border:1px solid var(--border);border-radius:10px;padding:18px 20px;position:relative;overflow:hidden;transition:border-color .2s}
.scard:hover{border-color:var(--border2)}
.scard::after{content:'';position:absolute;bottom:0;left:0;right:0;height:2px}
.scard.c-teal::after{background:linear-gradient(90deg,var(--teal),transparent)}
.scard.c-amber::after{background:linear-gradient(90deg,var(--amber),transparent)}
.scard.c-red::after{background:linear-gradient(90deg,var(--red),transparent)}
.scard.c-blue::after{background:linear-gradient(90deg,var(--blue),transparent)}
.scard.c-purple::after{background:linear-gradient(90deg,var(--purple),transparent)}
.scard-label{font-size:.65rem;font-weight:700;text-transform:uppercase;letter-spacing:.1em;color:var(--muted);margin-bottom:10px}
.scard-val{font-family:'JetBrains Mono',monospace;font-size:2rem;font-weight:700;line-height:1;color:#fff}
.scard-sub{font-size:.68rem;color:var(--muted);margin-top:6px}
.scard-glyph{position:absolute;right:14px;top:14px;font-size:1.4rem;opacity:.15}
.panel{background:var(--s1);border:1px solid var(--border);border-radius:10px;overflow:hidden;margin-bottom:20px}
.ph{padding:12px 18px;border-bottom:1px solid var(--border);display:flex;align-items:center;gap:10px}
.ph h2{font-size:.82rem;font-weight:700;letter-spacing:.02em;color:#fff;flex:1}
.ph-right{display:flex;align-items:center;gap:8px;margin-left:auto}
.g2{display:grid;grid-template-columns:1fr 1fr;gap:20px;margin-bottom:20px}
.g31{display:grid;grid-template-columns:1fr 360px;gap:20px;margin-bottom:20px}
.chart-box{padding:16px 18px;height:264px}
.chart-box-sm{padding:14px 18px;height:220px}

/* ── Map ── */
.map-wrap{padding:12px 14px;position:relative}
/* FIX: Canvas bekommt explizite display-Größe per CSS, Buffer-Größe per JS */
#propMap{display:block;width:100%;height:420px;border-radius:8px;border:1px solid var(--border);cursor:crosshair}
.map-leg{display:flex;flex-wrap:wrap;gap:10px;padding:8px 16px 12px}
.leg-item{display:flex;align-items:center;gap:5px;font-size:.7rem;color:var(--muted)}
.leg-dot{width:8px;height:8px;border-radius:50%;flex-shrink:0}
#mapTip{position:fixed;background:var(--s2);border:1px solid var(--border2);border-radius:8px;padding:10px 13px;font-size:.76rem;pointer-events:none;z-index:999;display:none;min-width:190px;line-height:1.6;box-shadow:0 8px 24px #000a}
#mapTip strong{color:var(--teal);font-family:'JetBrains Mono',monospace}

/* No-props overlay */
.map-empty{position:absolute;top:50%;left:50%;transform:translate(-50%,-50%);color:var(--muted);font-size:.85rem;text-align:center;pointer-events:none}

.tlist-item{display:flex;align-items:center;gap:8px;padding:8px 18px;border-bottom:1px solid #0a0c16}
.tlist-item:last-child{border-bottom:none}
.tlist-rank{font-family:'JetBrains Mono',monospace;font-size:.65rem;color:var(--muted);width:20px;flex-shrink:0}
.tlist-name{font-size:.8rem;flex:1;white-space:nowrap;overflow:hidden;text-overflow:ellipsis}
.tlist-count{font-family:'JetBrains Mono',monospace;font-size:.78rem;font-weight:700;color:var(--teal)}
.filters{display:flex;gap:7px;flex-wrap:wrap;align-items:center}
.filters select,.filters input{background:var(--s2);border:1px solid var(--border);color:var(--text);padding:6px 10px;border-radius:7px;font-size:.78rem;outline:none;font-family:'Syne',sans-serif}
.filters select:focus,.filters input:focus{border-color:var(--teal2)}
.tbl-wrap{overflow-x:auto}
table{width:100%;border-collapse:collapse;font-size:.8rem}
th{padding:9px 14px;text-align:left;font-weight:700;font-size:.62rem;text-transform:uppercase;letter-spacing:.08em;color:var(--muted);border-bottom:1px solid var(--border);white-space:nowrap}
td{padding:8px 14px;border-bottom:1px solid #0a0c16;vertical-align:middle}
tr:last-child td{border-bottom:none}
tr:hover td{background:#0c0f1c}
.badge{padding:2px 8px;border-radius:4px;font-size:.68rem;font-weight:700;font-family:'JetBrains Mono',monospace}
.b-place{background:#0a2018;color:#4ade80;border:1px solid #0f3525}
.b-remove{background:#200a10;color:#f87171;border:1px solid #4a1020}
.b-admin_give{background:#0a1428;color:#60a5fa;border:1px solid #0f2048}
.b-admin_clear{background:#200f00;color:#fbbf24;border:1px solid #4a2800}
.b-allgemein{background:#0a1428;color:#60a5fa;border:1px solid #0f2048}
.b-polizei{background:#200a10;color:#f87171;border:1px solid #4a1020}
.b-baustelle{background:#200f00;color:#fbbf24;border:1px solid #4a2800}
.b-admin{background:#150a28;color:#c084fc;border:1px solid #300a50}
.b-default{background:#0a2018;color:#4ade80;border:1px solid #0f3525}
.pager{display:flex;gap:5px;padding:11px 14px;justify-content:center;border-top:1px solid var(--border);flex-wrap:wrap;align-items:center}
.pager button{background:var(--s2);border:1px solid var(--border);color:var(--text);padding:4px 9px;border-radius:6px;cursor:pointer;font-size:.75rem;min-width:30px;font-family:'JetBrains Mono',monospace}
.pager button:hover{background:var(--s3)}
.pager button.on{background:var(--teal2);border-color:var(--teal);color:#000;font-weight:700}
.pager button:disabled{opacity:.3;cursor:default}
.pager-info{font-family:'JetBrains Mono',monospace;font-size:.68rem;color:var(--muted);margin-left:8px}
.empty{text-align:center;padding:36px;color:var(--muted);font-size:.8rem}
.coord{font-family:'JetBrains Mono',monospace;font-size:.7rem;color:var(--muted)}
.recent-item{display:flex;align-items:center;gap:8px;padding:7px 16px;border-bottom:1px solid #0a0c16;font-size:.78rem}
.recent-item:last-child{border-bottom:none}
.recent-name{flex:1;white-space:nowrap;overflow:hidden;text-overflow:ellipsis}
.recent-time{font-family:'JetBrains Mono',monospace;font-size:.68rem;color:var(--muted)}
@media(max-width:1300px){.stat-row{grid-template-columns:repeat(3,1fr)}.g31{grid-template-columns:1fr}}
@media(max-width:900px){.stat-row{grid-template-columns:repeat(2,1fr)}.g2{grid-template-columns:1fr}}
</style>
</head>
<body>
<div id="mapTip"></div>
<header>
  <div class="logo"><div class="logo-icon">🧱</div>prop_placement</div>
  <span id="dot" class="dot dead"></span>
  <span id="uptime" class="mono">–</span>
  <span id="statusPill" class="pill pill-gray">Verbinde...</span>
  <div class="hdr-right">
    <span id="activePill" class="pill pill-teal">– Props aktiv</span>
    <button class="btn" onclick="loadAll()">↻ Refresh</button>
  </div>
</header>
<div class="wrap">

  <div class="stat-row">
    <div class="scard c-teal">
      <div class="scard-label">Props aktiv</div>
      <div class="scard-val" id="sActive">–</div>
      <div class="scard-sub" id="sActiveSub">geladen</div>
      <span class="scard-glyph">📦</span>
    </div>
    <div class="scard c-blue">
      <div class="scard-label">Logs gesamt</div>
      <div class="scard-val" id="sTotal">–</div>
      <div class="scard-sub">in der DB</div>
      <span class="scard-glyph">📋</span>
    </div>
    <div class="scard c-purple">
      <div class="scard-label">Letzte 24h</div>
      <div class="scard-val" id="s24h">–</div>
      <div class="scard-sub">Aktionen</div>
      <span class="scard-glyph">🕐</span>
    </div>
    <div class="scard c-amber">
      <div class="scard-label">Platzierungen</div>
      <div class="scard-val" id="sPlace">–</div>
      <div class="scard-sub">gesamt</div>
      <span class="scard-glyph">✅</span>
    </div>
    <div class="scard c-red">
      <div class="scard-label">Entfernungen</div>
      <div class="scard-val" id="sRemove">–</div>
      <div class="scard-sub">gesamt</div>
      <span class="scard-glyph">🗑</span>
    </div>
  </div>

  <div class="g2">
    <div class="panel">
      <div class="ph"><h2>📈 Aktivität – letzte 7 Tage</h2></div>
      <div class="chart-box"><canvas id="actChart"></canvas></div>
    </div>
    <div class="panel">
      <div class="ph"><h2>🏆 Top Props</h2></div>
      <div id="topItems"><div class="empty">Lädt...</div></div>
      <div class="ph" style="border-top:1px solid var(--border)"><h2>👤 Top Spieler</h2></div>
      <div id="topPlayers"><div class="empty">Lädt...</div></div>
    </div>
  </div>

  <div class="g31">
    <div class="panel">
      <div class="ph">
        <h2>🗺️ Prop-Karte</h2>
        <span class="pill pill-gray" id="mapCount">0 Props</span>
      </div>
      <div class="map-wrap" id="mapWrap">
        <canvas id="propMap" width="800" height="420"></canvas>
        <div id="mapEmptyMsg" class="map-empty" style="display:none">Keine Props platziert</div>
      </div>
      <div class="map-leg" id="mapLeg"></div>
    </div>
    <div style="display:flex;flex-direction:column;gap:20px">
      <div class="panel" style="flex:0 0 auto">
        <div class="ph"><h2>📊 Verteilung</h2></div>
        <div class="chart-box-sm" id="distBox">
          <canvas id="distChart"></canvas>
        </div>
        <div id="distEmpty" class="empty" style="display:none;padding:20px">Keine Props aktiv</div>
      </div>
      <div class="panel" style="flex:1">
        <div class="ph"><h2>⚡ Letzte Aktionen</h2></div>
        <div id="recentActs"><div class="empty">Lädt...</div></div>
      </div>
    </div>
  </div>

  <div class="panel">
    <div class="ph">
      <h2>📦 Aktive Props</h2>
      <div class="ph-right filters">
        <input id="pFItem"  placeholder="Item..." oninput="propsP=1;loadProps()" style="width:110px">
        <input id="pFOwner" placeholder="Owner ID..." oninput="propsP=1;loadProps()" style="width:140px">
      </div>
    </div>
    <div class="tbl-wrap" id="propsTbl"><div class="empty">Lädt...</div></div>
    <div class="pager" id="propsPager"></div>
  </div>

  <div class="panel">
    <div class="ph">
      <h2>📋 Logs</h2>
      <div class="ph-right filters">
        <select id="fAction" onchange="logsP=1;loadLogs()">
          <option value="">Alle</option>
          <option value="place">Platziert</option>
          <option value="remove">Entfernt</option>
          <option value="admin_give">Admin Give</option>
          <option value="admin_clear">Admin Clear</option>
        </select>
        <input id="fItem"   placeholder="Item..."    oninput="logsP=1;loadLogs()" style="width:110px">
        <input id="fPlayer" placeholder="Spieler..." oninput="logsP=1;loadLogs()" style="width:120px">
      </div>
    </div>
    <div class="tbl-wrap" id="logsTbl"><div class="empty">Lädt...</div></div>
    <div class="pager" id="logsPager"></div>
  </div>

</div>

<script>
const KEY = '__API_KEY__';
const B   = window.location.origin;
let logsP = 1, propsP = 1;
let allMapProps = [];
let actCh = null, distCh = null;

async function api(path) {
  const sep = path.includes('?') ? '&' : '?';
  const r = await fetch(B + path + sep + 'api_key=' + KEY);
  if (!r.ok) throw new Error('HTTP ' + r.status);
  return r.json();
}

function fmt(n) { return (+(n||0)).toLocaleString('de-DE'); }

// ── Kategorie-Farben ──────────────────────────────────────
const CAT_COLOR = {
  'Allgemein':'#60a5fa', 'Polizei':'#f87171',
  'Baustelle':'#fbbf24', 'Admin':'#c084fc', 'Sonstiges':'#4ade80',
};
function catColor(c) { return CAT_COLOR[c] || CAT_COLOR['Sonstiges']; }
function catBadge(c) {
  return ({Allgemein:'b-allgemein',Polizei:'b-polizei',Baustelle:'b-baustelle',Admin:'b-admin'})[c] || 'b-default';
}

// ── Health ────────────────────────────────────────────────
async function loadHealth() {
  try {
    const d = await api('/prop_placement/health');
    document.getElementById('dot').className = d.status === 'ok' ? 'dot' : 'dot dead';
    const pill = document.getElementById('statusPill');
    if (d.status === 'ok') {
      pill.className = 'pill pill-teal'; pill.textContent = 'Online';
      const u = Math.floor(d.uptime);
      document.getElementById('uptime').textContent =
        Math.floor(u/3600)+'h '+Math.floor((u%3600)/60)+'m '+u%60+'s Uptime';
    } else { pill.className='pill pill-red'; pill.textContent='Fehler'; }
  } catch {
    document.getElementById('dot').className = 'dot dead';
    document.getElementById('statusPill').className = 'pill pill-red';
    document.getElementById('statusPill').textContent = 'Offline';
  }
}

// ── Stats ─────────────────────────────────────────────────
async function loadStats() {
  try {
    const d = await api('/prop_placement/stats');
    document.getElementById('sTotal').textContent  = fmt(d.total_logs);
    document.getElementById('s24h').textContent    = fmt(d.last_24h);
    const pl = (d.by_action||[]).find(a=>a.action==='place');
    const rm = (d.by_action||[]).find(a=>a.action==='remove');
    document.getElementById('sPlace').textContent  = fmt(pl ? pl.count : 0);
    document.getElementById('sRemove').textContent = fmt(rm ? rm.count : 0);

    document.getElementById('topItems').innerHTML =
      (d.top_items||[]).slice(0,6).map((i,n) =>
        `<div class="tlist-item"><span class="tlist-rank">#${n+1}</span><span class="tlist-name">${i.item_name}</span><span class="tlist-count">${fmt(i.count)}×</span></div>`
      ).join('') || '<div class="empty">Keine Daten</div>';

    document.getElementById('topPlayers').innerHTML =
      (d.top_placers||[]).slice(0,5).map((p,n) =>
        `<div class="tlist-item"><span class="tlist-rank">#${n+1}</span><span class="tlist-name">${p.player_name||'?'}</span><span class="tlist-count">${fmt(p.count)}×</span></div>`
      ).join('') || '<div class="empty">Keine Daten</div>';

    buildActChart(d.activity_7d||[]);
  } catch(e) { console.error('Stats Fehler:', e); }
}

// ── Aktivitäts-Chart ──────────────────────────────────────
function buildActChart(data) {
  const ctx = document.getElementById('actChart');
  if (!ctx) return;
  if (actCh) { actCh.destroy(); actCh = null; }

  // Leere Daten: 7 Tage mit 0
  if (!data.length) {
    const labels = [];
    for (let i = 6; i >= 0; i--) {
      const d = new Date(); d.setDate(d.getDate() - i);
      labels.push(d.toLocaleDateString('de-DE',{weekday:'short',day:'2-digit',month:'2-digit'}));
    }
    data = labels.map(l => ({ date: l, place: 0, remove: 0 }));
  }

  const labels  = data.map(d => { try { const dt=new Date(d.date); return dt.toLocaleDateString('de-DE',{weekday:'short',day:'2-digit',month:'2-digit'}); } catch{return d.date;} });
  const places  = data.map(d => +(d.place  || 0));
  const removes = data.map(d => +(d.remove || 0));

  actCh = new Chart(ctx.getContext('2d'), {
    type: 'bar',
    data: {
      labels,
      datasets: [
        { label:'Platziert', data:places,  backgroundColor:'#22c55e90', borderColor:'#22c55e', borderWidth:1, borderRadius:3 },
        { label:'Entfernt',  data:removes, backgroundColor:'#f43f5e90', borderColor:'#f43f5e', borderWidth:1, borderRadius:3 },
      ]
    },
    options: {
      responsive:true, maintainAspectRatio:false,
      plugins:{ legend:{ labels:{ color:'#4a5275', font:{size:11,family:'JetBrains Mono'} } } },
      scales:{
        x:{ ticks:{color:'#4a5275',font:{size:10}}, grid:{color:'#12162a'} },
        y:{ ticks:{color:'#4a5275',font:{size:10}}, grid:{color:'#12162a'}, beginAtZero:true },
      }
    }
  });
}

// ── Verteilungs-Chart ─────────────────────────────────────
function buildDistChart(props) {
  const distBox   = document.getElementById('distBox');
  const distEmpty = document.getElementById('distEmpty');
  const ctx       = document.getElementById('distChart');
  if (!ctx) return;

  if (distCh) { distCh.destroy(); distCh = null; }

  // Leere Daten abfangen
  if (!props || !props.length) {
    distBox.style.display   = 'none';
    distEmpty.style.display = 'block';
    return;
  }
  distBox.style.display   = 'block';
  distEmpty.style.display = 'none';

  const cats = {};
  props.forEach(p => { const c = p.category||'Sonstiges'; cats[c] = (cats[c]||0)+1; });

  const labels = Object.keys(cats);
  const data   = Object.values(cats);
  if (!labels.length) { distBox.style.display='none'; distEmpty.style.display='block'; return; }

  const colors = labels.map(c => catColor(c));
  distCh = new Chart(ctx.getContext('2d'), {
    type: 'doughnut',
    data: {
      labels,
      datasets: [{ data, backgroundColor: colors.map(c=>c+'bb'), borderColor: colors, borderWidth:1 }]
    },
    options: {
      responsive:true, maintainAspectRatio:false,
      plugins:{ legend:{ position:'right', labels:{ color:'#4a5275', font:{size:10}, boxWidth:10, padding:8 } } },
      cutout:'62%',
    }
  });
}

// ── GTA5 Karten-Bild vorladen ─────────────────────────────
// Falls das Bild nicht lädt → Fallback auf dunkles Gitter
const MAP_BG = new Image();
MAP_BG.crossOrigin = 'anonymous';
// Öffentlich verfügbares GTA5 Satellitenbild – kann durch lokale Datei ersetzt werden
// z.B. nui://prop_placement/web/images/map.jpg (512x512 oder größer)
MAP_BG.src = 'https://i.imgur.com/wxqSSeL.jpeg';
let mapImgReady = false;
MAP_BG.onload  = () => { mapImgReady = true; requestAnimationFrame(() => drawMap(allMapProps)); };
MAP_BG.onerror = () => { console.warn('[prop_placement] Karten-Bild konnte nicht geladen werden – Fallback auf Gitter.'); };
const MX0=-4000, MX1=4500, MY0=-4500, MY1=8500;

function w2c(wx, wy, W, H) {
  return [
    (wx - MX0) / (MX1 - MX0) * W,
    (1 - (wy - MY0) / (MY1 - MY0)) * H
  ];
}

function drawMap(props) {
  const canvas   = document.getElementById('propMap');
  const emptyMsg = document.getElementById('mapEmptyMsg');
  if (!canvas) return;

  // FIX: Parent-Breite verwenden, da getBoundingClientRect bei Canvas unzuverlässig ist
  // Höhe ist fix 420px (matching HTML-Attribut)
  const parent = canvas.parentElement;
  const W = (parent ? parent.clientWidth - 24 : 800) || 800;
  const H = 420;

  // Canvas-Buffer-Größe setzen (muss explizit gesetzt werden, CSS-Größe reicht nicht)
  canvas.width  = W;
  canvas.height = H;

  const ctx = canvas.getContext('2d');
  ctx.clearRect(0, 0, W, H);

  // Hintergrund: GTA5 Satellitenbild oder Fallback-Gitter
  if (mapImgReady) {
    // Karten-Bild skaliert auf Canvas zeichnen
    ctx.drawImage(MAP_BG, 0, 0, W, H);
    // Leichte Abdunklung für bessere Dot-Sichtbarkeit
    ctx.fillStyle = 'rgba(0, 0, 0, 0.30)';
    ctx.fillRect(0, 0, W, H);
  } else {
    // Fallback: dunkler Gradient
    const grad = ctx.createLinearGradient(0, 0, 0, H);
    grad.addColorStop(0, '#080a14');
    grad.addColorStop(1, '#05070e');
    ctx.fillStyle = grad;
    ctx.fillRect(0, 0, W, H);
  }

  // Gitterlinien (dezent, nur bei Fallback wirklich sichtbar)
  ctx.strokeStyle = mapImgReady ? 'rgba(255,255,255,0.06)' : '#0d1020';
  ctx.lineWidth = 1;
  for (let gx = MX0; gx <= MX1; gx += 1000) {
    const [cx] = w2c(gx, 0, W, H);
    ctx.beginPath(); ctx.moveTo(cx, 0); ctx.lineTo(cx, H); ctx.stroke();
  }
  for (let gy = MY0; gy <= MY1; gy += 1000) {
    const [,cy] = w2c(0, gy, W, H);
    ctx.beginPath(); ctx.moveTo(0, cy); ctx.lineTo(W, cy); ctx.stroke();
  }

  // Referenzpunkte (Los Santos, Sandy Shores, Paleto Cove)
  const refs = [
    {wx:200,  wy:-700, label:'LS'},
    {wx:1800, wy:3500, label:'SS'},
    {wx:-1200,wy:2600, label:'PC'},
  ];
  refs.forEach(r => {
    const [cx, cy] = w2c(r.wx, r.wy, W, H);
    // Hintergrund-Kreis
    ctx.beginPath(); ctx.arc(cx, cy, 16, 0, Math.PI*2);
    ctx.fillStyle = 'rgba(0,0,0,0.55)'; ctx.fill();
    ctx.strokeStyle = 'rgba(255,255,255,0.25)'; ctx.lineWidth = 1; ctx.stroke();
    // Label
    ctx.fillStyle = 'rgba(255,255,255,0.7)';
    ctx.font = 'bold 9px "JetBrains Mono", monospace';
    ctx.textAlign = 'center'; ctx.textBaseline = 'middle';
    ctx.fillText(r.label, cx, cy);
  });

  // Leere Karte: Meldung anzeigen
  if (!props || !props.length) {
    emptyMsg.style.display = 'block';
    document.getElementById('mapLeg').innerHTML = '';
    document.getElementById('mapCount').textContent = '0 Props';
    return;
  }
  emptyMsg.style.display = 'none';

  // Props zeichnen
  props.forEach(p => {
    const [cx, cy] = w2c(p.x, p.y, W, H);
    const col = catColor(p.category);

    // Äußerer Glow-Ring
    ctx.beginPath(); ctx.arc(cx, cy, 10, 0, Math.PI*2);
    ctx.fillStyle = col + '18'; ctx.fill();

    // Mittlerer Glow
    ctx.beginPath(); ctx.arc(cx, cy, 6, 0, Math.PI*2);
    ctx.fillStyle = col + '40'; ctx.fill();

    // Kern-Dot
    ctx.beginPath(); ctx.arc(cx, cy, 4, 0, Math.PI*2);
    ctx.fillStyle = col; ctx.fill();

    // Weißer Highlight-Punkt in der Mitte
    ctx.beginPath(); ctx.arc(cx - 1, cy - 1, 1.2, 0, Math.PI*2);
    ctx.fillStyle = 'rgba(255,255,255,0.6)'; ctx.fill();
  });

  // Legende
  const cats = {};
  props.forEach(p => { const c = p.category||'Sonstiges'; cats[c]=(cats[c]||0)+1; });
  document.getElementById('mapLeg').innerHTML =
    Object.entries(cats).map(([c,n]) =>
      `<div class="leg-item"><div class="leg-dot" style="background:${catColor(c)}"></div>${c}: ${n}</div>`
    ).join('');
  document.getElementById('mapCount').textContent = fmt(props.length) + ' Props';
}

// Map Tooltip & Click
const mapCanvas = document.getElementById('propMap');
const mapTip    = document.getElementById('mapTip');
if (mapCanvas) {
  mapCanvas.addEventListener('mousemove', e => {
    const r  = mapCanvas.getBoundingClientRect();
    const scX = mapCanvas.width  / r.width;
    const scY = mapCanvas.height / r.height;
    const mx = (e.clientX - r.left) * scX;
    const my = (e.clientY - r.top)  * scY;
    let found = null;
    for (const p of allMapProps) {
      const [cx, cy] = w2c(p.x, p.y, mapCanvas.width, mapCanvas.height);
      if (Math.hypot(mx-cx, my-cy) < 14) { found = p; break; }
    }
    if (found) {
      mapTip.style.display = 'block';
      mapTip.style.left    = (e.clientX+14)+'px';
      mapTip.style.top     = (e.clientY-8)+'px';
      const sid = (found.ownerIdentifier||'?').replace('license:','').slice(0,16);
      mapTip.innerHTML = `<strong>#${found.id} · ${found.itemName}</strong><br>
        <span style="color:var(--muted)">X ${(+found.x).toFixed(1)} · Y ${(+found.y).toFixed(1)} · Z ${(+found.z).toFixed(1)}</span><br>
        <span style="color:var(--muted)">Owner: ${sid}...</span><br>
        <span style="color:var(--red);font-size:.7rem">Klicken zum Löschen</span>`;
    } else {
      mapTip.style.display = 'none';
    }
  });
  mapCanvas.addEventListener('mouseleave', () => { mapTip.style.display='none'; });
  mapCanvas.addEventListener('click', e => {
    const r  = mapCanvas.getBoundingClientRect();
    const mx = (e.clientX - r.left) * (mapCanvas.width  / r.width);
    const my = (e.clientY - r.top)  * (mapCanvas.height / r.height);
    for (const p of allMapProps) {
      const [cx, cy] = w2c(p.x, p.y, mapCanvas.width, mapCanvas.height);
      if (Math.hypot(mx-cx, my-cy) < 14) { delProp(p.id, p.itemName); break; }
    }
  });
}

// FIX: ResizeObserver auf Parent-Element, nicht Canvas selbst
if (window.ResizeObserver) {
  const mapParent = document.getElementById('mapWrap');
  if (mapParent) {
    new ResizeObserver(() => {
      requestAnimationFrame(() => drawMap(allMapProps));
    }).observe(mapParent);
  }
}

// ── Props laden ───────────────────────────────────────────
async function loadProps() {
  const fi = document.getElementById('pFItem').value.toLowerCase();
  const fo = document.getElementById('pFOwner').value.toLowerCase();
  document.getElementById('propsTbl').innerHTML = '<div class="empty">Lädt...</div>';
  try {
    const d = await api('/prop_placement/props?page='+propsP+'&pageSize=20');
    allMapProps = d.all_map_props || [];
    const total = +(d.total || 0);

    document.getElementById('sActive').textContent    = fmt(total);
    document.getElementById('sActiveSub').textContent = 'aktive Props';
    document.getElementById('activePill').textContent = fmt(total) + ' Props aktiv';

    // FIX: Karte nach einem Tick zeichnen, damit Layout fertig ist
    requestAnimationFrame(() => {
      drawMap(allMapProps);
      buildDistChart(allMapProps);
    });

    let rows = d.props || [];
    if (fi) rows = rows.filter(p => (p.itemName||'').toLowerCase().includes(fi));
    if (fo) rows = rows.filter(p => (p.ownerIdentifier||'').toLowerCase().includes(fo));

    if (!rows.length) {
      document.getElementById('propsTbl').innerHTML = '<div class="empty">Keine Props gefunden.</div>';
      document.getElementById('propsPager').innerHTML = '';
      return;
    }

    document.getElementById('propsTbl').innerHTML = `<table>
      <thead><tr><th>#</th><th>Item</th><th>Kategorie</th><th>Koordinaten</th><th>Rotation</th><th>Besitzer</th><th>Persist.</th><th>Aktion</th></tr></thead>
      <tbody>${rows.map(p => {
        const sid = p.ownerIdentifier ? p.ownerIdentifier.replace('license:','').slice(0,12)+'...' : '–';
        return `<tr>
          <td class="mono">#${p.id}</td>
          <td><span class="badge ${catBadge(p.category)}">${p.itemName}</span></td>
          <td style="font-size:.72rem;color:var(--muted)">${p.category||'?'}</td>
          <td class="coord">${(+p.x).toFixed(1)}, ${(+p.y).toFixed(1)}, ${(+p.z).toFixed(1)}</td>
          <td class="mono">${(+p.rotation).toFixed(1)}°</td>
          <td class="mono">${sid}</td>
          <td style="color:${p.persistent?'var(--green)':'var(--amber)'}">${p.persistent?'💾':'⚡'}</td>
          <td><button class="btn btn-red btn-sm" onclick="delProp(${p.id},'${p.itemName}')">🗑 Löschen</button></td>
        </tr>`;
      }).join('')}</tbody>
    </table>`;

    makePager('propsPager', d.page, d.totalPages, d.total, 'goProp');
  } catch(e) {
    document.getElementById('propsTbl').innerHTML = '<div class="empty">Fehler beim Laden der Props.</div>';
    console.error('Props Fehler:', e);
  }
}

async function delProp(id, name) {
  if (!confirm('Prop #'+id+' ('+name+') löschen?\n\nDas Item wird NICHT zurückgelegt.')) return;
  try {
    const d = await api('/prop_placement/props/remove?id='+id);
    if (d.success) { await loadProps(); loadStats(); }
    else alert('Fehler: '+(d.error||'Unbekannt'));
  } catch { alert('Verbindungsfehler.'); }
}

function goProp(p) { propsP=p; loadProps(); }

// ── Letzte Aktionen ───────────────────────────────────────
async function loadRecent() {
  try {
    const d = await api('/prop_placement/logs?page=1');
    document.getElementById('recentActs').innerHTML =
      (d.data||[]).slice(0,7).map(log => {
        const t = new Date(log.created_at).toLocaleTimeString('de-DE',{hour:'2-digit',minute:'2-digit'});
        return `<div class="recent-item">
          <span class="badge b-${log.action}" style="min-width:70px;text-align:center">${log.action}</span>
          <span class="recent-name">${log.player_name||'?'} · ${log.item_name||'–'}</span>
          <span class="recent-time">${t}</span>
        </div>`;
      }).join('') || '<div class="empty">Keine Aktionen</div>';
  } catch {}
}

// ── Logs ─────────────────────────────────────────────────
async function loadLogs() {
  const action = document.getElementById('fAction').value;
  const item   = document.getElementById('fItem').value;
  const player = document.getElementById('fPlayer').value;
  let url = '/prop_placement/logs?page='+logsP;
  if (action) url += '&action='+encodeURIComponent(action);
  if (item)   url += '&item='+encodeURIComponent(item);
  if (player) url += '&player='+encodeURIComponent(player);

  document.getElementById('logsTbl').innerHTML = '<div class="empty">Lädt...</div>';
  try {
    const d = await api(url);
    if (!d.data || !d.data.length) {
      document.getElementById('logsTbl').innerHTML = '<div class="empty">Keine Logs.</div>';
      document.getElementById('logsPager').innerHTML = '';
      return;
    }
    document.getElementById('logsTbl').innerHTML = `<table>
      <thead><tr><th>#</th><th>Aktion</th><th>Spieler</th><th>License</th><th>Item</th><th>Koordinaten</th><th>Zeit</th></tr></thead>
      <tbody>${d.data.map(log => {
        const dt  = new Date(log.created_at).toLocaleString('de-DE');
        const sid = log.identifier ? log.identifier.replace('license:','').slice(0,12)+'...' : '–';
        const co  = log.coords ? `${(+(log.coords.x||0)).toFixed(1)}, ${(+(log.coords.y||0)).toFixed(1)}, ${(+(log.coords.z||0)).toFixed(1)}` : '–';
        return `<tr>
          <td class="mono">${log.id}</td>
          <td><span class="badge b-${log.action}">${log.action}</span></td>
          <td>${log.player_name||'–'}</td>
          <td class="mono">${sid}</td>
          <td>${log.item_name||'–'}</td>
          <td class="coord">${co}</td>
          <td class="mono" style="font-size:.7rem">${dt}</td>
        </tr>`;
      }).join('')}</tbody>
    </table>`;
    const p = d.pagination;
    makePager('logsPager', p.page, p.total_pages, p.total, 'goLog');
  } catch(e) {
    document.getElementById('logsTbl').innerHTML = '<div class="empty">Fehler beim Laden.</div>';
  }
}

function goLog(p) { logsP=p; loadLogs(); }

// ── Pagination ────────────────────────────────────────────
function makePager(id, page, total, count, fn) {
  if (!total || total <= 1) { document.getElementById(id).innerHTML=''; return; }
  let h = `<button onclick="${fn}(${page-1})" ${page<=1?'disabled':''}>‹</button>`;
  const s = Math.max(1,page-2), e = Math.min(total,page+2);
  if (s>1) h += `<button onclick="${fn}(1)">1</button>`+(s>2?`<span style="padding:0 4px;color:var(--muted)">…</span>`:'');
  for (let i=s;i<=e;i++) h += `<button onclick="${fn}(${i})" ${i===page?'class="on"':''}>${i}</button>`;
  if (e<total) h += (e<total-1?`<span style="padding:0 4px;color:var(--muted)">…</span>`:'')+`<button onclick="${fn}(${total})">${total}</button>`;
  h += `<button onclick="${fn}(${page+1})" ${page>=total?'disabled':''}>›</button>`;
  h += `<span class="pager-info">${fmt(count)} Einträge</span>`;
  document.getElementById(id).innerHTML = h;
}

// ── Init ─────────────────────────────────────────────────
async function loadAll() {
  await Promise.all([loadHealth(), loadStats(), loadProps(), loadRecent(), loadLogs()]);
}

// FIX: Erst nach vollständigem Laden starten
window.addEventListener('load', () => {
  loadAll();
  setInterval(loadAll, 30000);
});

// FIX: Karte bei Window-Resize neu zeichnen
window.addEventListener('resize', () => {
  requestAnimationFrame(() => drawMap(allMapProps));
});
</script>
</body>
</html>]==]

local function BuildDashboard()
  return DASHBOARD_HTML:gsub('__API_KEY__', Config.Logging.ApiKey)
end

-- ─────────────────────────────────────────────────────────
-- HTTP Handler
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
    JsonResponse(res, 405, { error = 'Method Not Allowed' }); return
  end

  local path, query = ParseRequest(req.path or '/')

  -- DEBUG: Jeden eingehenden Request loggen (entfernen wenn alles funktioniert)
  print(('[prop_placement][HTTP] Pfad: "%s" | Methode: %s | Raw: "%s"'):format(
    path, req.method, tostring(req.path)))

  -- Dashboard (kein Key nötig)
  if path == '/prop_placement/dashboard' or path == '/dashboard' then
    HtmlResponse(res, BuildDashboard()); return
  end

  -- Auth
  if not CheckApiKey(req, query) then
    JsonResponse(res, 401, { error = 'Unauthorized' }); return
  end

  -- Health
  if path == '/prop_placement/health' or path == '/health' then
    JsonResponse(res, 200, {
      status    = 'ok',
      resource  = GetCurrentResourceName(),
      uptime    = GetGameTimer() / 1000,
      timestamp = os.time(),
    }); return
  end

  -- Stats (inkl. 7-Tage-Aktivität)
  if path == '/prop_placement/stats' or path == '/stats' then
    local total      = MySQL.query.await('SELECT COUNT(*) as c FROM prop_placement_logs')
    local byAction   = MySQL.query.await('SELECT action, COUNT(*) as count FROM prop_placement_logs GROUP BY action')
    local topItems   = MySQL.query.await([[
            SELECT item_name, COUNT(*) as count FROM prop_placement_logs
            WHERE action='place' AND item_name IS NOT NULL
            GROUP BY item_name ORDER BY count DESC LIMIT 10]])
    local topPlacers = MySQL.query.await([[
            SELECT player_name, identifier, COUNT(*) as count FROM prop_placement_logs
            WHERE action='place' GROUP BY identifier ORDER BY count DESC LIMIT 10]])
    local recentDay  = MySQL.query.await([[
            SELECT COUNT(*) as c FROM prop_placement_logs WHERE created_at >= (NOW() - INTERVAL 24 HOUR)]])
    local raw7d      = MySQL.query.await([[
            SELECT DATE(created_at) as dy, action, COUNT(*) as count
            FROM prop_placement_logs
            WHERE created_at >= DATE_SUB(CURDATE(), INTERVAL 6 DAY)
              AND action IN ('place','remove')
            GROUP BY DATE(created_at), action ORDER BY dy ASC]])

    local byDate     = {}
    if raw7d then
      for _, row in ipairs(raw7d) do
        local d = tostring(row.dy):sub(1, 10)
        if not byDate[d] then byDate[d] = { date = d, place = 0, remove = 0 } end
        if row.action == 'place' then
          byDate[d].place = row.count
        elseif row.action == 'remove' then
          byDate[d].remove = row.count
        end
      end
    end
    local activity7d = {}
    for _, v in pairs(byDate) do table.insert(activity7d, v) end
    table.sort(activity7d, function(a, b) return a.date < b.date end)

    JsonResponse(res, 200, {
      total_logs   = total and total[1] and total[1].c or 0,
      last_24h     = recentDay and recentDay[1] and recentDay[1].c or 0,
      by_action    = byAction or {},
      top_items    = topItems or {},
      top_placers  = topPlacers or {},
      activity_7d  = activity7d,
      generated_at = os.time(),
    }); return
  end

  -- Debug-Endpunkt: zeigt rohen State ohne Auth-Zwang (nur wenn Config.Debug = true)
  if path == '/prop_placement/debug' or path == '/debug' then
    if not Config.Debug then
      JsonResponse(res, 403, { error = 'Debug-Modus nicht aktiv. Config.Debug = true setzen.' }); return
    end

    -- DB direkt prüfen
    local dbCount          = MySQL.query.await('SELECT COUNT(*) as c FROM prop_placement_props')
    local dbSample         = MySQL.query.await('SELECT id, item_name, x, y, z FROM prop_placement_props LIMIT 5')

    -- Global-Funktionen prüfen
    local hasGetAll        = type(GetAllPlacedProps) == 'function'
    local hasRemoveFn      = type(RemovePropFromServer) == 'function'

    -- Config prüfen
    local propsConfigCount = 0
    local propsSample      = {}
    if Config and Config.Props then
      for k, v in pairs(Config.Props) do
        propsConfigCount = propsConfigCount + 1
        if propsConfigCount <= 3 then
          table.insert(propsSample, { key = k, category = v.category or '?' })
        end
      end
    end

    -- In-memory Props (falls Global verfügbar)
    local inMemoryCount = 0
    local inMemorySample = {}
    if hasGetAll then
      local all = GetAllPlacedProps()
      for _, p in pairs(all) do
        inMemoryCount = inMemoryCount + 1
        if inMemoryCount <= 3 then
          table.insert(inMemorySample, { id = p.id, itemName = p.itemName })
        end
      end
    end

    JsonResponse(res, 200, {
      debug = true,
      db = {
        total_props = dbCount and dbCount[1] and dbCount[1].c or 0,
        sample_rows = dbSample or {},
      },
      globals = {
        GetAllPlacedProps    = hasGetAll,
        RemovePropFromServer = hasRemoveFn,
      },
      in_memory = {
        available = hasGetAll,
        count     = inMemoryCount,
        sample    = inMemorySample,
      },
      config = {
        props_defined = propsConfigCount,
        sample        = propsSample,
        debug_flag    = Config.Debug,
      },
      server = {
        resource  = GetCurrentResourceName(),
        uptime    = GetGameTimer() / 1000,
        timestamp = os.time(),
      }
    }); return
  end

  -- Props: Prop löschen (DB + in-memory über Global falls verfügbar)
  if path == '/prop_placement/props/remove' or path == '/props/remove' then
    local propId = tonumber(query.id)
    if not propId then
      JsonResponse(res, 400, { error = 'id parameter required' }); return
    end

    -- Erst DB-Eintrag holen für Log
    local existing = MySQL.query.await('SELECT * FROM prop_placement_props WHERE id = ?', { propId })
    local propInfo = existing and existing[1]

    -- In-memory State über Global aktualisieren (falls verfügbar)
    if type(RemovePropFromServer) == 'function' then
      RemovePropFromServer(propId)
    else
      -- Fallback: nur DB löschen + Clients benachrichtigen
      MySQL.query('DELETE FROM prop_placement_props WHERE id = ?', { propId })
      TriggerClientEvent('prop_placement:propRemoved', -1, propId)
    end

    if propInfo then
      LogPropAction('admin_clear', 0, 'dashboard', 'Dashboard', propId,
        propInfo.item_name, propInfo.model,
        { x = propInfo.x, y = propInfo.y, z = propInfo.z },
        { source = 'http_dashboard' })
      JsonResponse(res, 200, { success = true, prop_id = propId })
    else
      JsonResponse(res, 404, { success = false, error = 'Prop #' .. propId .. ' nicht in DB gefunden' })
    end
    return
  end

  -- Props: Liste (direkt aus DB – zuverlässig, kein Cross-Script-Global nötig)
  if path == '/prop_placement/props' or path == '/props' then
    local page     = math.max(1, tonumber(query.page) or 1)
    local pageSize = math.max(1, math.min(tonumber(query.pageSize) or 20, 100))
    local offset   = (page - 1) * pageSize

    -- Gesamtzahl
    local countR   = MySQL.query.await('SELECT COUNT(*) as total FROM prop_placement_props')
    local total    = countR and countR[1] and countR[1].total or 0

    print(('[prop_placement][DEBUG] /props aufgerufen – DB-Count: %d | page: %d | pageSize: %d'):format(
      total, page, pageSize))

    -- Paginierte Props für Tabelle
    local rows = MySQL.query.await(
      'SELECT * FROM prop_placement_props ORDER BY id ASC LIMIT ? OFFSET ?',
      { pageSize, offset }
    ) or {}

    print(('[prop_placement][DEBUG] DB-Query zurück – Rows: %d'):format(#rows))

    -- Alle Props lightweight für Karte
    local allRows = MySQL.query.await(
      'SELECT id, item_name, x, y, z, owner_identifier FROM prop_placement_props ORDER BY id ASC'
    ) or {}

    print(('[prop_placement][DEBUG] allRows für Karte: %d'):format(#allRows))

    -- Kategorie aus Config.Props anreichern
    local function getCategory(itemName)
      if Config and Config.Props and Config.Props[itemName] then
        return Config.Props[itemName].category or 'Sonstiges'
      end
      return 'Sonstiges'
    end

    local pageProps = {}
    for _, row in ipairs(rows) do
      table.insert(pageProps, {
        id              = row.id,
        itemName        = row.item_name,
        model           = row.model,
        x               = row.x,
        y               = row.y,
        z               = row.z,
        rotation        = row.rotation,
        ownerIdentifier = row.owner_identifier,
        persistent      = row.persistent == 1,
        category        = getCategory(row.item_name),
      })
    end

    local mapProps = {}
    for _, row in ipairs(allRows) do
      table.insert(mapProps, {
        id              = row.id,
        itemName        = row.item_name,
        x               = row.x,
        y               = row.y,
        z               = row.z,
        category        = getCategory(row.item_name),
        ownerIdentifier = row.owner_identifier,
      })
    end

    JsonResponse(res, 200, {
      props         = pageProps,
      all_map_props = mapProps,
      total         = total,
      page          = page,
      totalPages    = math.max(1, math.ceil(total / pageSize)),
      generated_at  = os.time(),
    }); return
  end

  -- Logs
  if path == '/prop_placement/logs' or path == '/logs' then
    local page               = math.max(1, tonumber(query.page) or 1)
    local pageSize           = Config.Logging.PageSize
    local offset             = (page - 1) * pageSize
    local conditions, params = {}, {}

    if query.action and query.action ~= '' then
      table.insert(conditions, 'action = ?'); table.insert(params, query.action)
    end
    if query.item and query.item ~= '' then
      table.insert(conditions, 'item_name = ?'); table.insert(params, query.item)
    end
    if query.identifier and query.identifier ~= '' then
      table.insert(conditions, 'identifier = ?'); table.insert(params, query.identifier)
    end
    if query.player and query.player ~= '' then
      table.insert(conditions, 'player_name LIKE ?'); table.insert(params, '%' .. query.player .. '%')
    end
    if query.from and query.from ~= '' then
      table.insert(conditions, 'created_at >= ?'); table.insert(params, query.from)
    end
    if query.to and query.to ~= '' then
      table.insert(conditions, 'created_at <= ?'); table.insert(params, query.to)
    end

    local where = #conditions > 0 and ('WHERE ' .. table.concat(conditions, ' AND ')) or ''

    local cp = {}; for _, v in ipairs(params) do table.insert(cp, v) end
    local cr = MySQL.query.await('SELECT COUNT(*) as total FROM prop_placement_logs ' .. where, cp)
    local total = cr and cr[1] and cr[1].total or 0

    local dp = {}; for _, v in ipairs(params) do table.insert(dp, v) end
    table.insert(dp, pageSize); table.insert(dp, offset)

    local logs = MySQL.query.await(
      'SELECT * FROM prop_placement_logs ' .. where .. ' ORDER BY created_at DESC LIMIT ? OFFSET ?', dp
    ) or {}

    for _, entry in ipairs(logs) do
      if entry.coords then
        local ok, d = pcall(json.decode, entry.coords); entry.coords = ok and d or entry.coords
      end
      if entry.extra then
        local ok, d = pcall(json.decode, entry.extra); entry.extra = ok and d or entry.extra
      end
    end

    JsonResponse(res, 200, {
      data         = logs,
      pagination   = { page = page, page_size = pageSize, total = total, total_pages = math.ceil(total / pageSize) },
      generated_at = os.time(),
    }); return
  end

  JsonResponse(res, 404, {
    error = 'Not Found',
    available = {
      '/prop_placement/dashboard',
      '/prop_placement/health',
      '/prop_placement/stats',
      '/prop_placement/props',
      '/prop_placement/props/remove?id=X',
      '/prop_placement/logs',
      '/prop_placement/debug  (nur wenn Config.Debug = true)',
    }
  })
end)

print('[prop_placement] HTTP API aktiv')
print('[prop_placement] Dashboard: http://SERVER_IP:30120/prop_placement/dashboard')
