--[[
    prop_placement – shared/config.lua
    Globale Einstellungen – Props sind in shared/props.lua
]]

Config = {}

-- ─── Debug ────────────────────────────────────────────
-- true = Konsolen-Logs aktivieren (nur für Entwicklung!)
Config.Debug = false

-- ─── Limits ───────────────────────────────────────────
-- Wie viele Props darf ein Spieler gleichzeitig haben? (0 = unbegrenzt)
Config.MaxPropsPerPlayer = 15

-- ─── Placement-Einstellungen ──────────────────────────
Config.Placement = {
    MaxDistance  = 10.0, -- Platzierungs-Reichweite in Metern
    Alpha        = 160,  -- Ghost-Transparenz (0-255)
    ZStep        = 0.05, -- Höhenänderung pro Scroll-Tick
    ZMin         = -2.0, -- Maximale Absenkung
    ZMax         = 5.0,  -- Maximale Anhebung
    RotationStep = 15.0, -- Grad pro Tastendruck (Q/R)
    GroundSnap   = true, -- Prop auf Boden einrasten
}

-- ─── Cooldown ─────────────────────────────────────────
-- Mindestzeit in ms zwischen zwei Platzierungen (0 = deaktiviert)
Config.PlacementCooldown = 1000

-- ─── Disconnect ───────────────────────────────────────
-- true  = Props eines Spielers werden beim Disconnect entfernt
-- false = Props bleiben bestehen
Config.RemoveOnDisconnect = false

-- ─── Streaming ────────────────────────────────────────
-- Props werden nur in der Nähe des Spielers gespawnt
Config.Streaming = {
    Enabled       = true,
    SpawnRadius   = 150.0, -- Props innerhalb dieser Distanz spawnen
    DespawnRadius = 180.0, -- Props außerhalb dieser Distanz despawnen
    CheckInterval = 2000,  -- Wie oft prüfen (ms)
}

-- ─── Snap-to-Grid ─────────────────────────────────────
-- Props rasten auf einem Raster ein beim Platzieren
Config.SnapToGrid = {
    Enabled  = false,
    GridSize = 0.5, -- Rasterabstand in Metern
}

-- ─── ox_target ────────────────────────────────────────
Config.TargetDistance = 2.0

-- ─── Inventar-Keybind ─────────────────────────────────
-- true  = TAB öffnet ox_inventory (nur zum Testen)
-- false = ausschalten wenn der Server ein eigenes Inventar-System hat
Config.UseBuiltinInventoryKey = false
