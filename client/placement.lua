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
    [G]          → Snap-to-Grid umschalten (wenn in Config aktiviert)
]]

local isPlacing       = false
local previewEntity   = nil
local currentRotation = 0.0
local zOffset         = 0.0
local placementValid  = false
local snapEnabled     = false -- Laufzeit-Toggle für Snap-to-Grid

-- FiveM Input-IDs
local KEY_CONFIRM     = 38  -- E
local KEY_CANCEL      = 177 -- Backspace / Delete
local KEY_ROT_LEFT    = 44  -- Q
local KEY_ROT_RIGHT   = 45  -- R
local KEY_SCROLL_UP   = 15  -- Mausrad hoch
local KEY_SCROLL_DOWN = 14  -- Mausrad runter
local KEY_SNAP        = 47  -- G

-- ─────────────────────────────────────────────────────────
-- Hilfsfunktionen
-- ─────────────────────────────────────────────────────────

local function RotToDirection(rot)
    local rad = math.pi / 180.0
    return vector3(
        -math.sin(rot.z * rad) * math.abs(math.cos(rot.x * rad)),
        math.cos(rot.z * rad) * math.abs(math.cos(rot.x * rad)),
        math.sin(rot.x * rad)
    )
end

--- Koordinate auf Raster einrasten
--- @param value number
--- @param gridSize number
--- @return number
local function SnapToGrid(value, gridSize)
    return math.floor(value / gridSize + 0.5) * gridSize
end

--- Position auf Raster einrasten (optional)
--- @param pos vector3
--- @return vector3
local function ApplySnap(pos)
    if not snapEnabled or not Config.SnapToGrid.Enabled then
        return pos
    end
    local g = Config.SnapToGrid.GridSize
    return vector3(
        SnapToGrid(pos.x, g),
        SnapToGrid(pos.y, g),
        pos.z -- Z nicht einrasten
    )
end

local function GetRaycastHit()
    local camCoords                    = GetGameplayCamCoord()
    local dir                          = RotToDirection(GetGameplayCamRot(2))
    local dest                         = camCoords + dir * Config.Placement.MaxDistance

    local playerPed                    = PlayerPedId()
    local ignoreEnt                    = previewEntity or playerPed

    local ray                          = StartShapeTestRay(camCoords, dest, 1 | 16 | 8, ignoreEnt, 0)
    local _, hit, hitPos, _, hitEntity = GetShapeTestResult(ray)

    if hit == 1 then
        local pos = vector3(hitPos.x, hitPos.y, hitPos.z + zOffset)
        return ApplySnap(pos), true
    end
    return ApplySnap(vector3(dest.x, dest.y, dest.z + zOffset)), false
end

local function IsValidPosition(pos)
    local found, groundZ = GetGroundZFor_3dCoord(pos.x, pos.y, pos.z + 5.0, false)
    if found and pos.z < groundZ - 5.0 then
        return false
    end
    return true
end

--- Prüft ob ein anderer Prop zu nah an der Position ist
--- @param pos vector3
--- @return bool  true = blockiert
local function IsBlockedByProp(pos)
    local playerPed = PlayerPedId()
    -- Radius von 0.5m für Kollisionsprüfung
    local obj = GetClosestObjectOfType(pos.x, pos.y, pos.z, 0.8, 0, false, true, false)
    if DoesEntityExist(obj) and obj ~= previewEntity then
        return true
    end
    return false
end

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
    snapEnabled     = false
end

-- ─────────────────────────────────────────────────────────
-- Haupt-Platzierungsfunktion
-- ─────────────────────────────────────────────────────────

function StartPropPlacement(itemName, propConfig)
    if isPlacing then
        lib.notify({ title = 'Hinweis', description = 'Du platzierst bereits etwas!', type = 'warning' })
        return
    end

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
    snapEnabled     = Config.SnapToGrid.Enabled -- Standard aus Config

    local pos       = GetEntityCoords(PlayerPedId())
    previewEntity   = CreateObject(model, pos.x, pos.y, pos.z, false, false, false)

    SetEntityCollision(previewEntity, false, false)
    SetEntityCompletelyDisableCollision(previewEntity, false, true)
    SetEntityAlpha(previewEntity, Config.Placement.Alpha, false)
    SetEntityInvincible(previewEntity, true)
    FreezeEntityPosition(previewEntity, true)
    SetEntityCanBeDamaged(previewEntity, false)
    SetEntityHasGravity(previewEntity, false)
    NetworkSetEntityInvisibleToNetwork(previewEntity, true)

    SetModelAsNoLongerNeeded(model)

    CreateThread(function()
        local lastRotateTime = 0
        local lastSnapToggle = 0

        while isPlacing do
            DisableControlAction(0, KEY_ROT_LEFT, true)
            DisableControlAction(0, KEY_ROT_RIGHT, true)
            DisableControlAction(0, 25, true)
            if Config.SnapToGrid.Enabled then
                DisableControlAction(0, KEY_SNAP, true)
            end

            local hitPos, hitGround = GetRaycastHit()
            local blocked           = IsBlockedByProp(hitPos)
            placementValid          = hitGround and IsValidPosition(hitPos) and not blocked

            SetEntityCoordsNoOffset(previewEntity, hitPos.x, hitPos.y, hitPos.z, false, false, false)
            SetEntityRotation(previewEntity, 0.0, 0.0, currentRotation, 2, true)

            -- Marker-Farbe: grün = gültig, orange = blockiert, rot = ungültig
            local r, g, b
            if placementValid then
                r, g, b = 0, 200, 0   -- Grün
            elseif blocked then
                r, g, b = 220, 120, 0 -- Orange (blockiert durch anderes Prop)
            else
                r, g, b = 220, 0, 0   -- Rot (ungültige Position)
            end

            DrawMarker(1,
                hitPos.x, hitPos.y, hitPos.z,
                0.0, 0.0, 0.0,
                0.0, 0.0, 0.0,
                0.6, 0.6, 0.08,
                r, g, b, 140,
                false, false, 2, nil, nil, false
            )

            -- Snap-to-Grid Raster anzeigen
            if snapEnabled and Config.SnapToGrid.Enabled then
                local g = Config.SnapToGrid.GridSize
                -- Kleine Marker an Rasterpunkten in der Nähe
                for dx = -2, 2 do
                    for dy = -2, 2 do
                        local gx = SnapToGrid(hitPos.x, g) + dx * g
                        local gy = SnapToGrid(hitPos.y, g) + dy * g
                        DrawMarker(1, gx, gy, hitPos.z,
                            0.0, 0.0, 0.0, 0.0, 0.0, 0.0,
                            0.05, 0.05, 0.02,
                            100, 100, 255, 80,
                            false, false, 2, nil, nil, false
                        )
                    end
                end
            end

            -- HelpText
            local snapText = ''
            if Config.SnapToGrid.Enabled then
                snapText = ('  •  **[G]** Snap: **%s**'):format(snapEnabled and 'AN' or 'AUS')
            end
            local statusText = placementValid and '' or (blocked and '  ⚠ Blockiert' or '  ✗ Ungültig')

            lib.showTextUI(
                ('**[E]** Platzieren  •  **[Backspace]** Abbrechen\n**[Q]** ↺ Drehen  •  **[R]** ↻ Drehen  •  **[Scroll]** Höhe: **%.2fm**%s%s')
                :format(zOffset, snapText, statusText),
                { position = 'bottom-center', icon = 'fas fa-cube' }
            )

            -- ── Platzieren (E) ───────────────────────────────
            if IsDisabledControlJustPressed(0, KEY_CONFIRM) or IsControlJustPressed(0, KEY_CONFIRM) then
                if placementValid then
                    TriggerServerEvent('prop_placement:place', itemName, {
                        x        = hitPos.x,
                        y        = hitPos.y,
                        z        = hitPos.z,
                        rotation = currentRotation,
                    })
                    CleanupPreview()
                    return
                else
                    local reason = blocked and 'Position ist durch einen anderen Prop blockiert.' or
                        'Hier kann kein Prop platziert werden.'
                    lib.notify({ title = 'Ungültige Position', description = reason, type = 'warning', duration = 2000 })
                end
            end

            -- ── Abbrechen (Backspace) ────────────────────────
            if IsControlJustPressed(0, KEY_CANCEL) then
                lib.notify({ title = 'Abgebrochen', description = 'Platzierung abgebrochen.', type = 'inform', duration = 2000 })
                CleanupPreview()
                return
            end

            -- ── Snap-to-Grid Toggle (G) ──────────────────────
            if Config.SnapToGrid.Enabled then
                if IsDisabledControlJustPressed(0, KEY_SNAP) or IsControlJustPressed(0, KEY_SNAP) then
                    local now = GetGameTimer()
                    if (now - lastSnapToggle) >= 300 then
                        snapEnabled    = not snapEnabled
                        lastSnapToggle = now
                        lib.notify({
                            title       = 'Snap-to-Grid',
                            description = snapEnabled and 'Aktiviert' or 'Deaktiviert',
                            type        = 'inform',
                            duration    = 1500,
                        })
                    end
                end
            end

            -- ── Links drehen (Q) ─────────────────────────────
            if IsDisabledControlPressed(0, KEY_ROT_LEFT) then
                local now = GetGameTimer()
                if (now - lastRotateTime) >= 80 then
                    currentRotation = (currentRotation + Config.Placement.RotationStep) % 360.0
                    lastRotateTime  = now
                end
            end

            -- ── Rechts drehen (R) ────────────────────────────
            if IsDisabledControlPressed(0, KEY_ROT_RIGHT) then
                local now = GetGameTimer()
                if (now - lastRotateTime) >= 80 then
                    currentRotation = (currentRotation - Config.Placement.RotationStep + 360.0) % 360.0
                    lastRotateTime  = now
                end
            end

            -- ── Höhe hoch ────────────────────────────────────
            if IsDisabledControlJustPressed(0, KEY_SCROLL_UP) or IsControlJustPressed(0, KEY_SCROLL_UP) then
                zOffset = math.min(Config.Placement.ZMax, zOffset + Config.Placement.ZStep)
            end

            -- ── Höhe runter ──────────────────────────────────
            if IsDisabledControlJustPressed(0, KEY_SCROLL_DOWN) or IsControlJustPressed(0, KEY_SCROLL_DOWN) then
                zOffset = math.max(Config.Placement.ZMin, zOffset - Config.Placement.ZStep)
            end

            Wait(0)
        end

        CleanupPreview()
    end)
end

function CancelPlacementExternal()
    if isPlacing then
        isPlacing = false
        CleanupPreview()
    end
end

function IsCurrentlyPlacing()
    return isPlacing
end
