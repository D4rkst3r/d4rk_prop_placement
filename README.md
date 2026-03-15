# prop_placement - Modulares Prop Placement System

Standalone Prop-Platzierungssystem fuer FiveM mit
**ox_lib** - **ox_inventory** - **ox_target** - **oxmysql**

---

## Features

| Feature                 | Details                                              |
| ----------------------- | ---------------------------------------------------- |
| Ghost-Vorschau          | Transparente Vorschau-Entitaet beim Platzieren       |
| Farbiger Marker         | Gruen = gueltig, Rot = ungueltig                     |
| Rotation                | Q / R Tasten                                         |
| Hoehenverstellung       | Mausrad                                              |
| Admin-System            | Ace Permissions                                      |
| Persistenz              | Waehlbar pro Prop (DB oder nur Session)              |
| Auto Item-Registrierung | Items werden automatisch in ox_inventory registriert |
| Icon-Unterstuetzung     | PNG Icons aus web/images/                            |

---

## Installation

### 1. SQL ausfuehren

```sql
-- Inhalt von sql/install.sql importieren
```

### 2. Ressource installieren

```
ensure prop_placement
```

### 3. Ace Permissions in server.cfg

```cfg
add_ace group.admin prop_placement.admin allow
```

---

## Prop hinzufuegen (nur eine Datei!)

Oeffne `shared/props.lua` und trage ein:

```lua
['mein_prop'] = {
    label      = 'Mein Prop',
    model      = 'prop_box_wood01a',
    weight     = 1000,
    adminOnly  = false,
    ownerOnly  = true,
    persistent = true,
},
```

Icon ablegen unter: `web/images/mein_prop.png` (512x512px)

Fertig - kein items.lua anfassen, kein Neustart noetig ausser dem Server!

---

## Icons

- Format: PNG, 512x512px, transparenter Hintergrund
- Pfad: `web/images/<item_name>.png`
- Kein Icon? ox_inventory zeigt ein Fragezeichen - kein Fehler
- Prop-Modelle finden: https://forge.plebmasters.de/objects

---

## Steuerung

| Taste     | Aktion         |
| --------- | -------------- |
| E         | Platzieren     |
| Backspace | Abbrechen      |
| Q         | Links drehen   |
| R         | Rechts drehen  |
| Scroll    | Hoehe anpassen |

---

## Admin-Befehle

| Befehl                     | Beschreibung                             |
| -------------------------- | ---------------------------------------- |
| `/propadmin`               | Admin-Menue (Props geben, alle loeschen) |
| `/giveprop <item> [menge]` | Item geben                               |
| `prop_clearall` (Konsole)  | Alle Props loeschen                      |
| `prop_list` (Konsole)      | Alle Props auflisten                     |

---

## API

```
GET http://SERVER_IP:30120/prop_placement/logs
GET http://SERVER_IP:30120/prop_placement/stats
GET http://SERVER_IP:30120/prop_placement/health
```

Header: `X-Api-Key: dein_key` (in server/logger.lua setzen)

---

## Dateistruktur

```
prop_placement/
├── fxmanifest.lua
├── shared/
│   ├── config.lua       <- Globale Einstellungen
│   └── props.lua        <- Props hier bearbeiten!
├── client/
│   ├── placement.lua
│   ├── main.lua
│   └── inventory.lua
├── server/
│   ├── main.lua
│   └── logger.lua
├── web/
│   └── images/          <- Icons hier ablegen (item_name.png)
└── sql/
    └── install.sql
```

---

## Abhaengigkeiten

| Ressource    | Pflicht |
| ------------ | ------- |
| ox_lib       | ja      |
| ox_inventory | ja      |
| ox_target    | ja      |
| oxmysql      | ja      |
