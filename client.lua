-- ============================================================
-- Vehicle Settings : colors, speed multiplier, indestructible, reset
-- Open the menu with F1.
-- Requires MenuV : '@menuv/menuv.lua' in the fxmanifest and `ensure menuv` first.
-- ============================================================

-- ------------------------------------------------------------
-- CONFIG
-- ------------------------------------------------------------
local SPEED_MIN = 1            -- 1 = original vehicle values
local SPEED_MAX = 10           -- highest multiplier accepted
local COLOR_MAX = 160          -- highest color ID
local HOLD_DELAY = 300         -- ms before a held arrow key starts repeating
local HOLD_INTERVAL = 50       -- ms between two repeats

-- Grip is multiplied by Speed x GRIP_BOOST, so it grows faster than the power.
-- 1.0 = same factor as the speed, 1.5 = 50% more grip than that.
-- If the vehicle still slides: raise it. If it feels glued and heavy: lower it.
local GRIP_BOOST = 1.5

-- Fields multiplied by the Speed value (power, gearbox, braking).
local SPEED_FIELDS = {
    'fInitialDriveForce',
    'fDriveInertia',
    'fInitialDriveMaxFlatVel',
    'fClutchChangeRateScaleUpShift',
    'fBrakeForce'
}

-- Fields multiplied by Speed x GRIP_BOOST (tyre grip).
-- fTractionCurveMin is the grip once the tyres slide: if only the Max was
-- multiplied, the grip collapsed as soon as the vehicle started to slip.
local GRIP_FIELDS = {
    'fTractionCurveMax',
    'fTractionCurveMin'
}

-- Read and saved, but NOT multiplied any more. They are not "strengths":
-- fTractionCurveLateral = shape of the lateral grip curve (an angle),
-- fBrakeBiasRear        = brake distribution between axles (a ratio),
-- fSuspensionUpperLimit = wheel travel (a distance in metres).
-- Multiplying them by up to 10 makes no physical sense. They are put back to
-- their original value, so a vehicle already modified by an older version is fixed.
-- Also left out on purpose: fSteeringLock, fTractionBiasFront, fBrakeBiasFront,
-- fSuspensionForce, fSuspensionCompDamp, fSuspensionReboundDamp, fMass,
-- vecInertiaMultiplier
local KEPT_FIELDS = {
    'fTractionCurveLateral',
    'fBrakeBiasRear',
    'fSuspensionUpperLimit'
}

-- Never multiplied: put back to its ORIGINAL value before every speed change.
-- ModifyVehicleTopSpeed rescales the drag, so it must start from the original
-- value each time, otherwise the changes pile up.
local DRAG_FIELD = 'fInitialDragCoeff'

-- ------------------------------------------------------------
-- STATE
-- ------------------------------------------------------------
local primary, secondary = 0, 0
local colorsChosen = false          -- colors are only applied once the player used a slider
local statValue = SPEED_MIN         -- speed multiplier (a number, not the menu item)
local indestructible = false

local originalHandling = {}         -- original values, stored per vehicle MODEL
local originalColors = {}           -- colors a vehicle had before we painted it
local protectedVehicles = {}        -- vehicles we made indestructible
local focusColor1, focusColor2 = false, false
local busy = false                  -- true while the keyboard is open or a reset is running

-- ------------------------------------------------------------
-- HELPERS
-- ------------------------------------------------------------
local function notify(message)
    BeginTextCommandThefeedPost('STRING')
    AddTextComponentSubstringPlayerName(message)
    EndTextCommandThefeedPostTicker(false, true)
end

-- Returns the vehicle the player is sitting in, or nil
local function getCurrentVehicle()
    local ped = PlayerPedId()

    if not IsPedInAnyVehicle(ped, false) then
        return nil
    end

    return GetVehiclePedIsIn(ped, false)
end

-- Opens GTA's on-screen keyboard. Returns the typed text, or nil if cancelled.
local function askText(defaultText, maxLength)
    AddTextEntry('VEHSETTINGS_INPUT', 'Speed (whole number)')
    DisplayOnscreenKeyboard(1, 'VEHSETTINGS_INPUT', '', defaultText, '', '', '', maxLength)

    local status = UpdateOnscreenKeyboard()
    while status == 0 do
        DisableAllControlActions(0)
        Wait(0)
        status = UpdateOnscreenKeyboard()
    end

    -- 1 = validated, 2 = cancelled, 3 = keyboard not shown
    if status ~= 1 then
        return nil
    end

    return (GetOnscreenKeyboardResult() or ''):gsub('%s+', '')
end

-- ------------------------------------------------------------
-- APPLY SETTINGS TO A VEHICLE
-- ------------------------------------------------------------
local function applyColors(vehicle)
    local model = GetEntityModel(vehicle)
    local saved = originalColors[vehicle]

    -- Remember the vehicle's own colors the first time we paint it (used by Reset)
    if not saved or saved.model ~= model then
        local p, s = GetVehicleColours(vehicle)
        originalColors[vehicle] = { model = model, primary = p, secondary = s }
    end

    SetVehicleColours(vehicle, primary, secondary)
end

-- The result only depends on the current Speed value and on the ORIGINAL
-- values of the model, never on what was applied before: nothing can pile up.
local function applyHandling(vehicle)
    local model = GetEntityModel(vehicle)
    local original = originalHandling[model]

    -- Speed 1 on a vehicle we never touched: leave it alone
    if not original and statValue == SPEED_MIN then
        return
    end

    -- First time on this model: save its original values
    if not original then
        original = {}

        for _, list in ipairs({ SPEED_FIELDS, GRIP_FIELDS, KEPT_FIELDS, { DRAG_FIELD } }) do
            for _, field in ipairs(list) do
                original[field] = GetVehicleHandlingFloat(vehicle, 'CHandlingData', field)
            end
        end

        originalHandling[model] = original
    end

    -- Speed 1 gives exactly the original values (no grip boost either)
    local gripFactor = statValue == SPEED_MIN and 1.0 or statValue * GRIP_BOOST

    -- 1. Every field = ORIGINAL value x factor (never "current value x factor")
    for _, field in ipairs(SPEED_FIELDS) do
        SetVehicleHandlingFloat(vehicle, 'CHandlingData', field, original[field] * statValue)
    end

    for _, field in ipairs(GRIP_FIELDS) do
        SetVehicleHandlingFloat(vehicle, 'CHandlingData', field, original[field] * gripFactor)
    end

    for _, field in ipairs(KEPT_FIELDS) do
        SetVehicleHandlingFloat(vehicle, 'CHandlingData', field, original[field])
    end

    -- 2. Drag back to its original value
    SetVehicleHandlingFloat(vehicle, 'CHandlingData', DRAG_FIELD, original[DRAG_FIELD])

    -- 3. LAST: this native is what makes the new drive force / max speed
    --    actually take effect (transmission setup) and it updates the drag.
    --    Called before the fields above, it would use the PREVIOUS values.
    --    Speed 1 = 0% change = original vehicle.
    ModifyVehicleTopSpeed(vehicle, statValue == SPEED_MIN and 0.0 or statValue + 0.0)
end

local function applyProtection(vehicle)
    -- Never touch the damage flags of a vehicle unless we changed them before
    if not indestructible and not protectedVehicles[vehicle] then
        return
    end

    SetEntityCanBeDamaged(vehicle, not indestructible)
    SetEntityInvincible(vehicle, indestructible)
    SetVehicleEngineCanDegrade(vehicle, not indestructible)

    protectedVehicles[vehicle] = indestructible or nil
end

-- Called when the checkbox changes: updates the current vehicle
-- and restores the ones we protected earlier if it was unchecked.
local function refreshProtection()
    for vehicle in pairs(protectedVehicles) do
        if DoesEntityExist(vehicle) then
            applyProtection(vehicle)
        else
            protectedVehicles[vehicle] = nil
        end
    end

    local vehicle = getCurrentVehicle()
    if vehicle then
        applyProtection(vehicle)
    end
end

-- Puts everything back to the vehicle's defaults (state + vehicles).
-- The menu items are refreshed by the Reset button handler below.
local function resetAll()
    statValue = SPEED_MIN
    indestructible = false
    colorsChosen = false

    -- Vehicles we repainted: back to their own original colors
    for vehicle, saved in pairs(originalColors) do
        if DoesEntityExist(vehicle) and GetEntityModel(vehicle) == saved.model then
            SetVehicleColours(vehicle, saved.primary, saved.secondary)
        end
    end

    originalColors = {}

    -- Damage flags back to normal on every vehicle we protected
    refreshProtection()

    local vehicle = getCurrentVehicle()

    if vehicle then
        -- Original handling values, drag and transmission recalculated
        applyHandling(vehicle)

        -- The sliders will show the colors the vehicle really has
        local p, s = GetVehicleColours(vehicle)
        primary = math.max(0, math.min(COLOR_MAX, p or 0))
        secondary = math.max(0, math.min(COLOR_MAX, s or 0))
    else
        primary, secondary = 0, 0
    end
end

-- ------------------------------------------------------------
-- MENU
-- ------------------------------------------------------------
local menu = MenuV:CreateMenu(
    'Vehicle Settings',
    'Color, speed and protection',
    'topleft',
    0, 120, 255,
    'size-125',
    'default',
    'menuv',
    'vehicle_settings',
    'native'
)

local color1 = menu:AddRange({
    icon = '🎨',
    label = 'Color 1',
    min = 0,
    max = COLOR_MAX,
    value = 0
})

local color2 = menu:AddRange({
    icon = '🎨',
    label = 'Color 2',
    min = 0,
    max = COLOR_MAX,
    value = 0
})

local speedButton = menu:AddButton({
    icon = '🚗',
    label = ('Speed : %d'):format(statValue),
    description = ('Press Enter, then type a whole number from %d to %d'):format(SPEED_MIN, SPEED_MAX)
})

local protectCheckbox = menu:AddCheckbox({
    icon = '🛡️',
    label = 'Indestructible',
    description = 'The vehicle no longer takes damage',
    value = false
})

local resetButton = menu:AddButton({
    icon = '🔄',
    label = 'Reset',
    description = 'Back to the default values of the vehicle'
})

local closeButton = menu:AddButton({
    icon = '❌',
    label = 'Close',
    description = 'Close the menu'
})

-- ------------------------------------------------------------
-- MENU EVENTS
-- ------------------------------------------------------------

-- 'change' fires every time the slider moves, with the new value
color1:On('change', function(item, newValue, oldValue)
    primary = tonumber(newValue) or 0
    colorsChosen = true

    local vehicle = getCurrentVehicle()
    if vehicle then
        applyColors(vehicle)
    end
end)

color2:On('change', function(item, newValue, oldValue)
    secondary = tonumber(newValue) or 0
    colorsChosen = true

    local vehicle = getCurrentVehicle()
    if vehicle then
        applyColors(vehicle)
    end
end)

-- MenuV has no text field, so Speed opens GTA's on-screen keyboard.
-- The menu is closed meanwhile so Enter/Backspace do not act on it.
speedButton:On('select', function()
    if busy then
        return
    end

    busy = true

    CreateThread(function()
        menu:Close()
        Wait(300)

        local text = askText(tostring(statValue), 3)

        if text == nil then
            notify('Speed unchanged.')
        else
            local value = text:match('^%d+$') and tonumber(text) or nil

            if value == nil or value < SPEED_MIN or value > SPEED_MAX then
                notify(('Enter a whole number from %d to %d.'):format(SPEED_MIN, SPEED_MAX))
            else
                statValue = value
                speedButton.Label = ('Speed : %d'):format(statValue)

                local vehicle = getCurrentVehicle()
                if vehicle then
                    applyHandling(vehicle)
                end

                notify(('Speed set to %d.'):format(statValue))
            end
        end

        Wait(200)
        busy = false
        menu:Open()
    end)
end)

protectCheckbox:On('change', function(item, newValue, oldValue)
    indestructible = newValue == true
    refreshProtection()
end)

-- Reset: the menu is closed while the items are updated, because MenuV's UI
-- ignores 0 / false when an OPEN menu is updated, but shows them on opening.
resetButton:On('select', function()
    if busy then
        return
    end

    busy = true

    CreateThread(function()
        menu:Close()
        Wait(200)

        resetAll()

        color1.Value = primary
        color2.Value = secondary
        speedButton.Label = ('Speed : %d'):format(statValue)
        protectCheckbox.Value = false

        notify('Vehicle settings reset.')

        Wait(200)
        busy = false
        menu:Open()
    end)
end)

closeButton:On('select', function(item)
    menu:Close()
end)

-- Track which slider is highlighted (used by the hold-to-scroll loop below).
-- Two separate flags: when moving between sliders, 'leave' and 'enter'
-- may arrive in any order.
color1:On('enter', function() focusColor1 = true end)
color1:On('leave', function() focusColor1 = false end)
color2:On('enter', function() focusColor2 = true end)
color2:On('leave', function() focusColor2 = false end)

-- The menu always opens on its first item (Color 1)
menu:On('open', function()
    focusColor1, focusColor2 = true, false
end)

menu:On('close', function()
    focusColor1, focusColor2 = false, false
end)

-- Open with F1 (pick a key not used by another resource)
menu:OpenWith('KEYBOARD', 'F1')

-- ------------------------------------------------------------
-- NEW VEHICLE DETECTION
-- ------------------------------------------------------------
CreateThread(function()
    local previousVehicle = nil

    while true do
        Wait(250)

        local vehicle = getCurrentVehicle()

        if vehicle and vehicle ~= previousVehicle then
            applyHandling(vehicle)
            applyProtection(vehicle)

            if colorsChosen then
                applyColors(vehicle)
            end
        end

        previousVehicle = vehicle
    end
end)

-- ------------------------------------------------------------
-- HOLD-TO-SCROLL ON THE COLOR SLIDERS
-- MenuV only reacts once per key press (it has no key repeat).
-- While an arrow key is held on a slider, we re-send MenuV's own key
-- commands (+menuv_left / +menuv_right) so it behaves like repeated presses.
-- ------------------------------------------------------------
CreateThread(function()
    local heldKey, heldSince, nextRepeat, repeated = nil, 0, 0, false

    while true do
        if focusColor1 or focusColor2 then
            Wait(0)

            local key = nil
            if IsDisabledControlPressed(0, 175) then      -- right arrow
                key = 'right'
            elseif IsDisabledControlPressed(0, 174) then  -- left arrow
                key = 'left'
            end

            local now = GetGameTimer()

            if key ~= heldKey then
                -- Key pressed, released or switched side: make sure MenuV sees it as released
                if repeated and heldKey then
                    ExecuteCommand('-menuv_' .. heldKey)
                end

                heldKey, heldSince, repeated = key, now, false
            elseif key and now - heldSince >= HOLD_DELAY and now >= nextRepeat then
                nextRepeat = now + HOLD_INTERVAL
                repeated = true

                ExecuteCommand('-menuv_' .. key)
                ExecuteCommand('+menuv_' .. key)
            end
        else
            -- Not on a slider anymore: release anything still held
            if repeated and heldKey then
                ExecuteCommand('-menuv_' .. heldKey)
            end

            heldKey, repeated = nil, false
            Wait(100)
        end
    end
end)
