--[[
    prop_placement – shared/props.lua
    ════════════════════════════════════════════════════════

    FELDER:
    ────────
    label      = 'Anzeigename im Inventar'
    model      = 'gta5_prop_hash_name'
    weight     = 1000
    category   = 'Kategoriename'   -- Für Admin-Menü Gruppierung
    adminOnly  = false
    ownerOnly  = true
    persistent = true

    PROP-MODELLE FINDEN:
    https://forge.plebmasters.de/objects
]]

Config.Props = {

    -- ── Allgemein ──────────────────────────────────────────
    ['wooden_crate'] = {
        label      = 'Holzkiste',
        model      = 'prop_box_wood01a',
        weight     = 2000,
        category   = 'Allgemein',
        adminOnly  = false,
        ownerOnly  = true,
        persistent = true,
    },
    ['metal_crate'] = {
        label      = 'Metallkiste',
        model      = 'prop_box_ammo02a',
        weight     = 3000,
        category   = 'Allgemein',
        adminOnly  = false,
        ownerOnly  = true,
        persistent = true,
    },
    ['plastic_bin'] = {
        label      = 'Mülleimer',
        model      = 'prop_bin_03a',
        weight     = 800,
        category   = 'Allgemein',
        adminOnly  = false,
        ownerOnly  = true,
        persistent = true,
    },
    ['garden_chair'] = {
        label      = 'Gartenstuhl',
        model      = 'prop_chair_03',
        weight     = 1500,
        category   = 'Allgemein',
        adminOnly  = false,
        ownerOnly  = true,
        persistent = true,
    },
    ['folding_table'] = {
        label      = 'Klapptisch',
        model      = 'prop_table_01a',
        weight     = 2500,
        category   = 'Allgemein',
        adminOnly  = false,
        ownerOnly  = true,
        persistent = true,
    },

    -- ── Polizei / Einsatzkräfte ───────────────────────────
    ['traffic_cone'] = {
        label      = 'Verkehrskegel',
        model      = 'prop_roadcone01a',
        weight     = 500,
        category   = 'Polizei',
        adminOnly  = false,
        ownerOnly  = false,
        persistent = true,
    },
    ['police_barrier'] = {
        label      = 'Polizeiabsperrung',
        model      = 'prop_mp_barrier_01b',
        weight     = 3000,
        category   = 'Polizei',
        adminOnly  = false,
        ownerOnly  = false,
        persistent = true,
    },
    ['road_barrier'] = {
        label      = 'Straßensperre',
        model      = 'prop_mp_barrier_02b',
        weight     = 5000,
        category   = 'Polizei',
        adminOnly  = false,
        ownerOnly  = false,
        persistent = true,
    },
    ['spike_strip'] = {
        label      = 'Nagelstreifen',
        model      = 'prop_ld_stinger_s',
        weight     = 1000,
        category   = 'Polizei',
        adminOnly  = false,
        ownerOnly  = false,
        persistent = true,
    },

    -- ── Baustelle / Mechaniker ────────────────────────────
    ['worklight'] = {
        label      = 'Baustellenlampe',
        model      = 'prop_worklight_03a',
        weight     = 2000,
        category   = 'Baustelle',
        adminOnly  = false,
        ownerOnly  = true,
        persistent = true,
    },
    ['generator'] = {
        label      = 'Generator',
        model      = 'prop_generator_01a',
        weight     = 8000,
        category   = 'Baustelle',
        adminOnly  = false,
        ownerOnly  = true,
        persistent = true,
    },
    ['scaffolding'] = {
        label      = 'Baugerüst',
        model      = 'prop_scaffolding_01',
        weight     = 10000,
        category   = 'Baustelle',
        adminOnly  = false,
        ownerOnly  = true,
        persistent = true,
    },

    -- ── Admin-Only ────────────────────────────────────────
    ['admin_barrier_large'] = {
        label      = 'Große Absperrung',
        model      = 'prop_barrier_work05',
        weight     = 1,
        category   = 'Admin',
        adminOnly  = true,
        ownerOnly  = false,
        persistent = true,
    },
    ['admin_tent'] = {
        label      = 'Zelt',
        model      = 'prop_fbi_tent01',
        weight     = 1,
        category   = 'Admin',
        adminOnly  = true,
        ownerOnly  = false,
        persistent = true,
    },
}
