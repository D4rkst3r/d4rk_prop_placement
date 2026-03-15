--[[
    prop_placement – shared/props.lua
    ════════════════════════════════════════════════════════

    HIER PROPS HINZUFÜGEN / BEARBEITEN
    ─────────────────────────────────────────────────────────
    Jeder Eintrag entspricht einem platzierbaren Prop.
    Das Item wird automatisch in ox_inventory registriert –
    kein manuelles Eintragen in items.lua nötig!

    FELDER:
    ────────
    label      = 'Anzeigename im Inventar'
    model      = 'gta5_prop_hash_name'     -- GTA5 Prop-Modell
    weight     = 1000                      -- Gewicht in Gramm
    adminOnly  = false                     -- true = nur Admins dürfen platzieren
    ownerOnly  = true                      -- true = nur Besitzer/Admin darf entfernen
                                           -- false = jeder darf entfernen
    persistent = true                      -- true = überlebt Server-Neustart (DB)
                                           -- false = nur bis Server-Neustart

    ICON:
    ──────
    Lege eine PNG (512x512) unter web/images/<item_name>.png ab.
    Kein Icon vorhanden? → ox_inventory zeigt ein Fragezeichen.

    PROP-MODELLE FINDEN:
    ──────────────────────
    https://forge.plebmasters.de/objects  (Suche + Vorschau)
    https://gta.fandom.com/wiki/Objects   (Liste mit Kategorien)
]]

Config.Props = {

    -- ── Allgemein ──────────────────────────────────────────
    ['wooden_crate'] = {
        label      = 'Holzkiste',
        model      = 'prop_box_wood01a',
        weight     = 2000,
        adminOnly  = false,
        ownerOnly  = true,
        persistent = true,
    },
    ['metal_crate'] = {
        label      = 'Metallkiste',
        model      = 'prop_box_ammo02a',
        weight     = 3000,
        adminOnly  = false,
        ownerOnly  = true,
        persistent = true,
    },
    ['plastic_bin'] = {
        label      = 'Mülleimer',
        model      = 'prop_bin_03a',
        weight     = 800,
        adminOnly  = false,
        ownerOnly  = true,
        persistent = true,
    },
    ['garden_chair'] = {
        label      = 'Gartenstuhl',
        model      = 'prop_chair_03',
        weight     = 1500,
        adminOnly  = false,
        ownerOnly  = true,
        persistent = true,
    },
    ['folding_table'] = {
        label      = 'Klapptisch',
        model      = 'prop_table_01a',
        weight     = 2500,
        adminOnly  = false,
        ownerOnly  = true,
        persistent = true,
    },

    -- ── Polizei / Einsatzkräfte ───────────────────────────
    ['traffic_cone'] = {
        label      = 'Verkehrskegel',
        model      = 'prop_roadcone01a',
        weight     = 500,
        adminOnly  = false,
        ownerOnly  = false,
        persistent = true,
    },
    ['police_barrier'] = {
        label      = 'Polizeiabsperrung',
        model      = 'prop_mp_barrier_01b',
        weight     = 3000,
        adminOnly  = false,
        ownerOnly  = false,
        persistent = true,
    },
    ['road_barrier'] = {
        label      = 'Straßensperre',
        model      = 'prop_mp_barrier_02b',
        weight     = 5000,
        adminOnly  = false,
        ownerOnly  = false,
        persistent = true,
    },
    ['spike_strip'] = {
        label      = 'Nagelstreifen',
        model      = 'prop_ld_stinger_s',
        weight     = 1000,
        adminOnly  = false,
        ownerOnly  = false,
        persistent = true,
    },

    -- ── Baustelle / Mechaniker ────────────────────────────
    ['worklight'] = {
        label      = 'Baustellenlampe',
        model      = 'prop_worklight_03a',
        weight     = 2000,
        adminOnly  = false,
        ownerOnly  = true,
        persistent = true,
    },
    ['generator'] = {
        label      = 'Generator',
        model      = 'prop_generator_01a',
        weight     = 8000,
        adminOnly  = false,
        ownerOnly  = true,
        persistent = true,
    },
    ['scaffolding'] = {
        label      = 'Baugerüst',
        model      = 'prop_scaffolding_01',
        weight     = 10000,
        adminOnly  = false,
        ownerOnly  = true,
        persistent = true,
    },

    -- ── Admin-Only ────────────────────────────────────────
    ['admin_barrier_large'] = {
        label      = 'Große Absperrung (Admin)',
        model      = 'prop_barrier_work05',
        weight     = 1,
        adminOnly  = true,
        ownerOnly  = false,
        persistent = true,
    },
    ['admin_tent'] = {
        label      = 'Zelt (Admin)',
        model      = 'prop_fbi_tent01',
        weight     = 1,
        adminOnly  = true,
        ownerOnly  = false,
        persistent = true,
    },
}
