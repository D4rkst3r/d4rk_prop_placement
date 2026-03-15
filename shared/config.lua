--[[
    ╔══════════════════════════════════════════════════════╗
    ║           prop_placement – shared/config.lua         ║
    ╚══════════════════════════════════════════════════════╝

    PROP HINZUFÜGEN:
    ────────────────
    ['item_name'] = {
        label      = 'Anzeigename',
        model      = 'prop_modell_name',   -- GTA5 Prop-Hash-Name
        jobs       = nil,                  -- nil = alle | {'police','mechanic'} = Job-Einschränkung
        adminOnly  = false,                -- true = nur Admins können platzieren
        ownerOnly  = true,                 -- true = nur Besitzer/Admin darf entfernen
        persistent = true,                 -- true = überlebt Server-Neustart (DB-Speicherung)
    },

    ITEM IN OX_INVENTORY REGISTRIEREN:
    ─────────────────────────────────────
    Füge das Item in ox_inventory/data/items.lua ein:
    ['item_name'] = { label = 'Anzeigename', weight = 1000, stack = true },
]]

Config = {}

-- ─── Debug ────────────────────────────────────────────
Config.Debug = true

-- ─── Limits ───────────────────────────────────────────
-- Wie viele Props darf ein Spieler gleichzeitig platziert haben? (0 = unbegrenzt)
Config.MaxPropsPerPlayer = 15

-- ─── Placement-Einstellungen ──────────────────────────
Config.Placement = {
    MaxDistance  = 5.0,  -- Maximale Platzierungsdistanz vom Spieler (Meter)
    Alpha        = 160,  -- Ghost-Transparenz 0-255 (höher = sichtbarer)
    ZStep        = 0.05, -- Höhenänderung pro Mausrad-Tick (Meter)
    ZMin         = -2.0, -- Minimale manuelle Z-Absenkung
    ZMax         = 5.0,  -- Maximale manuelle Z-Anhebung
    RotationStep = 15.0, -- Grad pro Rotations-Tastendruck
    GroundSnap   = true, -- Prop auf Boden ausrichten
}

-- ─── Admin-Gruppen ────────────────────────────────────
-- Ace-Permission-Gruppen, die als Admin gelten
-- → Diese können alle Props entfernen, Prop-Items geben & haben kein Limit
Config.AdminGroups = { 'admin', 'superadmin', 'god' }

-- ─── Prop-Definitionen ────────────────────────────────
Config.Props = {

    -- ── Allgemein ──────────────────────────────────────
    ['wooden_crate'] = {
        label      = 'Holzkiste',
        model      = 'prop_box_wood01a',
        jobs       = nil,
        adminOnly  = false,
        ownerOnly  = true,
        persistent = true,
    },
    ['metal_crate'] = {
        label      = 'Metallkiste',
        model      = 'prop_box_ammo02a',
        jobs       = nil,
        adminOnly  = false,
        ownerOnly  = true,
        persistent = true,
    },
    ['plastic_bin'] = {
        label      = 'Mülleimer',
        model      = 'prop_bin_03a',
        jobs       = nil,
        adminOnly  = false,
        ownerOnly  = true,
        persistent = true,
    },
    ['garden_chair'] = {
        label      = 'Gartenstuhl',
        model      = 'prop_chair_03',
        jobs       = nil,
        adminOnly  = false,
        ownerOnly  = true,
        persistent = true,
    },
    ['folding_table'] = {
        label      = 'Klapptisch',
        model      = 'prop_table_01a',
        jobs       = nil,
        adminOnly  = false,
        ownerOnly  = true,
        persistent = true,
    },

    -- ── Polizei / Einsatzkräfte ─────────────────────────
    ['traffic_cone'] = {
        label      = 'Verkehrskegel',
        model      = 'prop_roadcone01a',
        jobs       = { 'police', 'ambulance', 'mechanic' },
        adminOnly  = false,
        ownerOnly  = false, -- jeder berechtigte Job kann entfernen
        persistent = true,
    },
    ['police_barrier'] = {
        label      = 'Polizeiabsperrung',
        model      = 'prop_mp_barrier_01b',
        jobs       = { 'police' },
        adminOnly  = false,
        ownerOnly  = false,
        persistent = true,
    },
    ['road_barrier'] = {
        label      = 'Straßensperre',
        model      = 'prop_mp_barrier_02b',
        jobs       = { 'police', 'mechanic' },
        adminOnly  = false,
        ownerOnly  = false,
        persistent = true,
    },
    ['spike_strip'] = {
        label      = 'Nagelstreifen',
        model      = 'prop_ld_stinger_s',
        jobs       = { 'police' },
        adminOnly  = false,
        ownerOnly  = false,
        persistent = true,
    },

    -- ── Baustelle / Mechaniker ──────────────────────────
    ['worklight'] = {
        label      = 'Baustellenlampe',
        model      = 'prop_worklight_03a',
        jobs       = { 'mechanic', 'construction' },
        adminOnly  = false,
        ownerOnly  = true,
        persistent = true,
    },
    ['generator'] = {
        label      = 'Generator',
        model      = 'prop_generator_01a',
        jobs       = { 'mechanic', 'construction' },
        adminOnly  = false,
        ownerOnly  = true,
        persistent = true,
    },
    ['scaffolding'] = {
        label      = 'Baugerüst',
        model      = 'prop_scaffolding_01',
        jobs       = { 'construction' },
        adminOnly  = false,
        ownerOnly  = true,
        persistent = true,
    },

    -- ── Admin-Only ──────────────────────────────────────
    ['admin_barrier_large'] = {
        label      = 'Große Absperrung (Admin)',
        model      = 'prop_barrier_work05',
        jobs       = nil,
        adminOnly  = true,
        ownerOnly  = false,
        persistent = true,
    },
    ['admin_tent'] = {
        label      = 'Zelt (Admin)',
        model      = 'prop_fbi_tent01',
        jobs       = nil,
        adminOnly  = true,
        ownerOnly  = false,
        persistent = true,
    },
}

-- ─── ox_target Optionen ───────────────────────────────
Config.TargetDistance = 2.0 -- Interaktionsdistanz an platzierten Props

-- ─── Inventar-Keybind ─────────────────────────────────
-- true  = eigener TAB-Keybind zum Öffnen (nur zum Testen / falls kein anderes System)
-- false = deaktivieren wenn der Server ein eigenes Inventar-System hat
Config.UseBuiltinInventoryKey = false
