# 🧱 prop_placement – Modulares Prop Placement System

Standalone Prop-Platzierungssystem für FiveM mit  
**ox_lib** · **ox_inventory** · **ox_target** · **oxmysql**

---

## 📦 Features

| Feature | Details |
|---|---|
| Ghost-Vorschau | Transparente Vorschau-Entität beim Platzieren |
| Farbiger Marker | Grün = gültig, Rot = ungültig |
| Rotation | Q / R Tasten – stufenweise einstellbar |
| Höhenverstellung | Mausrad – mit konfigurierbaren Grenzen |
| Job-Binding | Props auf bestimmte Jobs beschränkbar |
| Admin-System | Ace Permissions – Props geben, alles löschen |
| Persistenz | Wählbar pro Prop (DB oder nur Session) |
| Framework-agnostisch | Kein spezifisches Framework nötig |
| Performance | Props werden gestaffelt geladen, Ghost nur lokal |

---

## 🔧 Installation

### 1. SQL ausführen
```sql
-- Inhalt von sql/install.sql in deine Datenbank importieren
```

### 2. Items in ox_inventory registrieren
Öffne `ox_inventory/data/items.lua` und füge die Items aus dem  
Kommentar-Block in `sql/install.sql` hinzu.

### 3. Ressource installieren
Lege den Ordner `prop_placement` in deinen `resources`-Ordner  
und trage ihn in `server.cfg` ein:
```
ensure prop_placement
```

### 4. Ace Permissions (Admin-Gruppen)
```cfg
# In server.cfg – Beispiel
add_ace group.admin prop_placement.admin allow
add_principal identifier.license:DEINE_LICENSE group.admin
```

---

## 🎮 Steuerung (Platzierungs-Modus)

| Taste | Aktion |
|---|---|
| `E` | Prop platzieren |
| `Backspace` | Platzierung abbrechen |
| `Q` | Gegen Uhrzeigersinn drehen |
| `R` | Im Uhrzeigersinn drehen |
| `Scroll Up` | Höhe erhöhen |
| `Scroll Down` | Höhe verringern |

---

## ⚙️ Konfiguration (`shared/config.lua`)

### Globale Einstellungen
```lua
Config.MaxPropsPerPlayer = 15  -- 0 = unbegrenzt
Config.Placement.MaxDistance  = 5.0   -- Platzierungs-Reichweite
Config.Placement.RotationStep = 15.0  -- Grad pro Tastendruck
Config.Placement.ZStep        = 0.05  -- Meter pro Scroll-Tick
```

### Neuen Prop hinzufügen
```lua
Config.Props['mein_item'] = {
    label      = 'Mein Prop',           -- Anzeigename
    model      = 'prop_box_wood01a',    -- GTA5 Prop-Modell
    jobs       = nil,                   -- nil = alle | {'police'} = Job-eingeschränkt
    adminOnly  = false,                 -- true = nur Admins
    ownerOnly  = true,                  -- true = nur Besitzer/Admin kann entfernen
    persistent = true,                  -- true = DB-Speicherung
}
```

Dann das Item in `ox_inventory/data/items.lua` eintragen – fertig!

### Job-System
```lua
-- Nur Polizei & Mechaniker
jobs = { 'police', 'mechanic' }

-- Alle können platzieren
jobs = nil

-- Nur Admins
adminOnly = true
```

---

## 💻 Admin-Befehle

| Befehl | Beschreibung |
|---|---|
| `/propadmin` | Admin-Menü öffnen (Props geben, alle löschen) |
| `prop_clearall` (Konsole/RCON) | Alle Props sofort löschen |
| `prop_list` (Konsole/RCON) | Alle Props auflisten |

---

## 🔌 Abhängigkeiten

| Ressource | Pflicht | Hinweis |
|---|---|---|
| `ox_lib` | ✅ | Notifications, UI, Context Menu |
| `ox_inventory` | ✅ | Item-Verwaltung, UseItem-Hook |
| `ox_target` | ✅ | Interaktion mit platzierten Props |
| `oxmysql` | ✅ | Datenbank-Persistenz |

---

## 🔍 Framework-Unterstützung (Job-Erkennung)

Die Job-Erkennung ist **automatisch** – das System probiert:
1. `ox_core`
2. `es_extended` (ESX)
3. `qb-core` (QBCore)
4. Kein Job (Props ohne Job-Restriction sind für alle nutzbar)

---

## 🐛 Debug-Modus

```lua
Config.Debug = true  -- in shared/config.lua
```

Aktiviert zusätzliche Konsolen-Logs und den `/propdebug`-Befehl.

---

## 📁 Dateistruktur

```
prop_placement/
├── fxmanifest.lua
├── shared/
│   └── config.lua          ← Konfiguration & Prop-Definitionen
├── client/
│   ├── placement.lua       ← Ghost-Preview, Controls
│   └── main.lua            ← Sync, Spawning, ox_target, Admin-UI
├── server/
│   └── main.lua            ← Validierung, DB, Events, Admin-Logic
└── sql/
    └── install.sql         ← DB-Schema + ox_inventory Items
```
