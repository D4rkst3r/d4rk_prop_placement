--[[
    prop_placement – shared/config.lua
    Globale Einstellungen – Props sind in shared/props.lua
]]

Config = {}

-- ─── Debug ────────────────────────────────────────────
-- true = Konsolen-Logs aktivieren
Config.Debug = true

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

-- ─── Admin-Gruppen ────────────────────────────────────
-- Spieler mit dem Ace 'prop_placement.admin' gelten als Admin.
-- In server.cfg zuweisen:
--   add_ace group.admin prop_placement.admin allow
Config.AdminGroups = { 'admin', 'superadmin', 'god' }

-- ─── ox_target ────────────────────────────────────────
Config.TargetDistance = 2.0

-- ─── Inventar-Keybind ─────────────────────────────────
-- true  = TAB öffnet ox_inventory (nur zum Testen)
-- false = ausschalten wenn der Server ein eigenes Inventar-System hat
Config.UseBuiltinInventoryKey = false
