--[[
    prop_placement – shared/config.lua
    Globale Einstellungen – Props sind in shared/props.lua
]]

Config = {}

-- ─── Debug ────────────────────────────────────────────
Config.Debug = true

-- ─── Limits ───────────────────────────────────────────
Config.MaxPropsPerPlayer = 150

-- ─── Placement ────────────────────────────────────────
Config.Placement = {
    MaxDistance  = 10.0,
    Alpha        = 160,
    ZStep        = 0.05,
    ZMin         = -2.0,
    ZMax         = 5.0,
    RotationStep = 15.0,
    GroundSnap   = true,
}

-- ─── Cooldown ─────────────────────────────────────────
Config.PlacementCooldown = 1000

-- ─── Disconnect ───────────────────────────────────────
Config.RemoveOnDisconnect = false

-- ─── Streaming ────────────────────────────────────────
Config.Streaming = {
    Enabled       = true,
    SpawnRadius   = 150.0,
    DespawnRadius = 180.0,
    CheckInterval = 2000,
}

-- ─── Grid-System ──────────────────────────────────────
-- Props werden in Gitterzellen eingeteilt für effizienten Streaming-Check
-- GridSize sollte >= SpawnRadius sein
Config.Grid = {
    Enabled  = true,
    GridSize = 200.0, -- Größe einer Gitterzelle in Metern
}

-- ─── Model-Preloading ─────────────────────────────────
-- Props-Modelle beim Start vorladen für verzögerungsfreies Spawnen
Config.Preloading = {
    Enabled = true,
    Delay   = 3000, -- Wartezeit nach Resource-Start (ms)
}

-- ─── Snap-to-Grid ─────────────────────────────────────
Config.SnapToGrid = {
    Enabled  = true,
    GridSize = 0.5,
}

-- ─── ox_target ────────────────────────────────────────
Config.TargetDistance = 2.0

-- ─── Inventar-Keybind ─────────────────────────────────
Config.UseBuiltinInventoryKey = false
