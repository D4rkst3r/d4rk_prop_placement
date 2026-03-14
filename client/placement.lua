--[[
    ╔══════════════════════════════════════════════════════╗
    ║         prop_placement – client/placement.lua        ║
    ║   Platzierungs-Vorschau mit Ghost-Entity & Controls  ║
    ╚══════════════════════════════════════════════════════╝

    STEUERUNG:
    ──────────
    [E]          → Prop platzieren (bei gültiger Position)
    [Backspace]  → Abbrechen
    [Q]          → Links drehen
    [R]          → Rechts drehen
    [Scroll Up]  → Höhe erhöhen
    [Scroll Down]→ Höhe verringern
]]

local isPlacing       = false
local previewEntity   = nil
local currentRotation = 0.0
local zOffset         = 0.0
local placementValid  = false

-- FiveM Input-IDs
local KEY_CONFIRM    = 38    -- E
local KEY_CANCEL     = 177   -- Backspace / Delete
local KEY_ROT_LEFT   = 44    -- Q
local KEY_ROT_RIGHT  = 45    -- R (Reload – wird während Platzierung deaktiviert)
local KEY_SCROLL_UP  = 15    -- Mausrad hoch
local KEY_SCROLL_DOWN = 14   -- Mausrad runter

-- ─────────────────────────────────────────────────────────
-- Hilfsfunktionen
-- ─────────────────────────────────────────────────────────

--- Kamerarotation in Richtungsvektor umrechnen
local function RotToDirection(rot)
    local rad = math.pi / 180.0
    return vector3(
        -math.sin(rot.z * rad) * math.abs(math.cos(rot.x * rad)),
         math.cos(rot.z * rad) * math.abs(math.cos(rot.x * rad)),
         math.sin(rot.x * rad)
    )
end

--- Raycast von der Kamera aus ermitteln
--- @return hitPos vec3, hitGround bool
local function GetRaycastHit()
    local camCoords = GetGameplayCamCoord()
    local dir       = RotToDirection(GetGameplayCamRot(2))
    local dest      = camCoords + dir * Config.Placement.MaxDistance

    -- Flags: 1 = Welt, 16 = Fahrzeuge (excluded via ignore)
    local ignoreEnt = previewEntity or -1
    local ray       = StartShapeTestRay(camCoords, dest, 1 | 16, ignoreEnt, 0)
    local _, hit, hitPos = GetShapeTestResult(ray)

    if hit == 1 then
        return vector3(hitPos.x, hitPos.y, hitPos.z + zOffset), true
    end
    return vector3(dest.x, dest.y, dest.z + zOffset), false
end

--- Prüft ob die Position gültig ist
--- @param pos vec3
--- @return bool
local function IsValidPosition(pos)
    -- Kein Wasser
    if IsPointInWater(pos.x, pos.y, pos.z + 1.0) then
        return false
    end
    -- Nicht zu weit unter Boden (Z-Schwelle)
    local groundZ, found = GetGroundZFor_3dCoord(pos.x, pos.y, pos.z + 5.0, false)
    if found and pos.z < groundZ - 3.0 then
        return false
    end
    return true
end

--- Ghost-Entität und State sauber aufräumen
local function CleanupPreview()
    lib.hideTextUI()
    if previewEntity and DoesEntityExist(previewEntity) then
        SetEntityAlpha(previewEntity, 255, false)
        DeleteEntity(previewEntity)
    end
    previewEntity   = nil
    isPlacing       = false
    currentRotation = 0.0
    zOffset         = 0.0
    placementValid  = false
end

-- ─────────────────────────────────────────────────────────
-- Haupt-Platzierungsfunktion
-- ─────────────────────────────────────────────────────────

--- Startet den Platzierungs-Modus
--- @param itemName string   ox_inventory Item-Name
--- @param propConfig table  Config.Props[itemName]
function StartPropPlacement(itemName, propConfig)
    if isPlacing then
        lib.notify({ title = 'Hinweis', description = 'Du platzierst bereits etwas!', type = 'warning' })
        return
    end

    -- Modell laden
    local model = GetHashKey(propConfig.model)
    RequestModel(model)

    local timeout = 0
    while not HasModelLoaded(model) do
        Wait(100)
        timeout = timeout + 1
        if timeout > 100 then
            lib.notify({ title = 'Fehler', description = 'Modell konnte nicht geladen werden.', type = 'error' })
            SetModelAsNoLongerNeeded(model)
            return
        end
    end

    isPlacing       = true
    currentRotation = 0.0
    zOffset         = 0.0

    -- Ghost-Entität erstellen
    local pos = GetEntityCoords(PlayerPedId())
    previewEntity = CreateObject(model, pos.x, pos.y, pos.z, false, false, false)

    SetEntityCollision(previewEntity, false, false)
    SetEntityAlpha(previewEntity, Config.Placement.Alpha, false)
    SetEntityInvincible(previewEntity, true)
    FreezeEntityPosition(previewEntity, true)
    SetEntityCanBeDamaged(previewEntity, false)
    SetEntityHasGravity(previewEntity, false)
    NetworkSetEntityInvisibleToNetwork(previewEntity, true)  -- nur lokal sichtbar

    SetModelAsNoLongerNeeded(model)

    -- Platzierungs-Thread
    CreateThread(function()
        local lastRotateTime = 0  -- Debounce für Rotation

        while isPlacing do
            -- Störende Controls während Platzierung deaktivieren
            DisableControlAction(0, KEY_ROT_LEFT,  true)  -- Q (Cover)
            DisableControlAction(0, KEY_ROT_RIGHT, true)  -- R (Reload)
            DisableControlAction(0, 25,            true)  -- Zielen (damit Scroll nicht ADS aktiviert)

            -- Raycast-Position ermitteln
            local hitPos, hitGround = GetRaycastHit()
            placementValid = hitGround and IsValidPosition(hitPos)

            -- Ghost-Entität positionieren
            SetEntityCoordsNoOffset(previewEntity, hitPos.x, hitPos.y, hitPos.z, false, false, false)
            SetEntityRotation(previewEntity, 0.0, 0.0, currentRotation, 2, true)

            -- Boden-Marker (grün = gültig, rot = ungültig)
            local r, g, b = placementValid and 0 or 220, placementValid and 200 or 0, 0
            DrawMarker(
                1,                                              -- Typ: senkrechter Zylinder
                hitPos.x, hitPos.y, hitPos.z,                  -- Position
                0.0, 0.0, 0.0,                                  -- Richtung
                0.0, 0.0, 0.0,                                  -- Rotation
                0.6, 0.6, 0.08,                                 -- Größe
                r, g, b, 140,                                   -- Farbe + Alpha
                false, false, 2, nil, nil, false
            )

            -- Hilfemenü
            lib.showTextUI(
                ('<b>[E]</b> Platzieren &emsp; <b>[Backspace]</b> Abbrechen\n' ..
                 '<b>[Q]</b> ↺ Drehen &emsp; <b>[R]</b> ↻ Drehen &emsp; ' ..
                 '<b>[Scroll]</b> Höhe: <b>%.2fm</b>'):format(zOffset),
                { position = 'bottom-center', icon = 'fas fa-cube' }
            )

            -- ── Platzieren (E) ─────────────────────────────────
            if IsDisabledControlJustPressed(0, KEY_CONFIRM) or IsControlJustPressed(0, KEY_CONFIRM) then
                if placementValid then
                    -- Position einfrieren & ans Netz senden
                    TriggerServerEvent('prop_placement:place', itemName, {
                        x        = hitPos.x,
                        y        = hitPos.y,
                        z        = hitPos.z,
                        rotation = currentRotation,
                    })
                    CleanupPreview()
                    return
                else
                    lib.notify({
                        title       = 'Ungültige Position',
                        description = 'Hier kann kein Prop platziert werden.',
                        type        = 'warning',
                        duration    = 2000,
                    })
                end
            end

            -- ── Abbrechen (Backspace) ──────────────────────────
            if IsControlJustPressed(0, KEY_CANCEL) then
                lib.notify({ title = 'Abgebrochen', description = 'Platzierung abgebrochen.', type = 'inform', duration = 2000 })
                CleanupPreview()
                return
            end

            -- ── Links drehen (Q) ──────────────────────────────
            if IsDisabledControlPressed(0, KEY_ROT_LEFT) then
                local now = GetGameTimer()
                if (now - lastRotateTime) >= 80 then
                    currentRotation = (currentRotation + Config.Placement.RotationStep) % 360.0
                    lastRotateTime  = now
                end
            end

            -- ── Rechts drehen (R) ─────────────────────────────
            if IsDisabledControlPressed(0, KEY_ROT_RIGHT) then
                local now = GetGameTimer()
                if (now - lastRotateTime) >= 80 then
                    currentRotation = (currentRotation - Config.Placement.RotationStep + 360.0) % 360.0
                    lastRotateTime  = now
                end
            end

            -- ── Höhe hoch (Scroll Up) ─────────────────────────
            if IsDisabledControlJustPressed(0, KEY_SCROLL_UP) or IsControlJustPressed(0, KEY_SCROLL_UP) then
                zOffset = math.min(Config.Placement.ZMax, zOffset + Config.Placement.ZStep)
            end

            -- ── Höhe runter (Scroll Down) ─────────────────────
            if IsDisabledControlJustPressed(0, KEY_SCROLL_DOWN) or IsControlJustPressed(0, KEY_SCROLL_DOWN) then
                zOffset = math.max(Config.Placement.ZMin, zOffset - Config.Placement.ZStep)
            end

            Wait(0)
        end

        CleanupPreview()
    end)
end

--- Platzierung von außen abbrechen (z.B. bei Tod)
function CancelPlacementExternal()
    if isPlacing then
        isPlacing = false
        CleanupPreview()
    end
end

--- Gibt zurück ob gerade platziert wird
function IsCurrentlyPlacing()
    return isPlacing
end
