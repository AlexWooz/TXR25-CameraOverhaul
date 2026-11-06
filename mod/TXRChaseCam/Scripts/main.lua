-- TXRChaseCam: loose chase camera for Tokyo Xtreme Racer.
--
-- The vanilla chase camera (OutCamera on the car's CameraArm, a BP_CameraArm_C) is rigidly
-- attached to the car body; the only swing it has is the slip-angle offset while sliding.
-- This mod keeps a "camera heading" that trails the car's heading through a first-order lag,
-- and feeds the difference into the arm's own SetYawOffset() every frame. The camera then
-- falls behind when the car turns in, showing the side of the car, and catches up on exit.
-- The game's slip-angle swing keeps working on top of it.
--
-- Keys (keyboard, for tuning):
--   Ctrl+F6          toggle the mod on/off (to compare with vanilla)
--   Ctrl+Up/Down     LagSpeed +/- 0.5   (higher = stiffer, catches up faster)
--   Ctrl+Right/Left  MaxOffset +/- 5    (max degrees the camera can trail)
--   Ctrl+F5          toggle debug log (4x/s: speed, yaw rate, offset)
--   Ctrl+PgUp/PgDn   close-view distance +/- 25
--   Ctrl+Home/End    close-view height +/- 10
--
-- Right stick (controller): orbit around the car in the chase and far views. Left/right spins
-- the camera, down swings it to the front, releasing eases it back. See the Orbit section.

local Config = {
    Enabled = true,
    -- How fast the camera heading catches up with the car's heading (1/s).
    -- In a steady turn the camera trails by about yaw_rate / LagSpeed degrees,
    -- e.g. 20 deg/s of turning at LagSpeed 2.5 gives 8 degrees.
    LagSpeed = 2.5,
    -- Hard limit on how far the camera can trail, in degrees.
    MaxOffset = 20,
    -- Below MinSpeedKmh there is no trailing; it fades in up to FullSpeedKmh.
    MinSpeedKmh = 20,
    FullSpeedKmh = 60,
    -- Multiplier on our offset once the game's own slip-angle swing is at full strength, since
    -- it already turns the camera in drifts. It fades in with that swing (not on drift_started,
    -- which flips in one frame and made the camera snap).
    DriftScale = 0.5,
    -- The game's swing reaches full strength at this many degrees (arm's stop_slip_angle).
    GameSlipMax = 30,
    -- A heading jump bigger than this in one frame (respawn, teleport, replay) resets the lag.
    SnapResetDegrees = 60,
    -- Extra distance and height for the close chase view (CameraArm, ~450 units behind by
    -- default), passed to the arm's SetTargetLengthOffset / SetRelativeLocationZOffset.
    CloseDistanceOffset = 100,
    CloseHeightOffset = 0,

    -- Right-stick orbit (chase and far views). The game only reports the stick past ~75%
    -- deflection, as separate look-left/right/back signals (nothing for up).
    --   "direct": the camera looks where the stick points (stick right -> camera on the car's
    --             left looking right, stick down -> looking back at the car's front). The angle
    --             is rebuilt from those signals assuming the stick is pushed to the edge.
    --   "spin":   holding left/right spins the camera around the car, down swings it to the front.
    -- Releasing the stick eases the camera back behind the car in both modes.
    OrbitEnabled = true,
    OrbitMode = "direct",
    OrbitFollowSpeed = 10,     -- direct: how fast the camera reaches the stick angle (1/s)
    OrbitSpeed = 150,          -- spin: degrees per second at full deflection
    OrbitInvert = false,       -- flip left/right
    OrbitReturnDelay = 0.03,   -- seconds after release before easing back (bridges gaps between signals)
    OrbitReturnSpeed = 12,     -- how fast it eases back (1/s); 12 covers 90 degrees in about 0.25 s
}

local function log(fmt, ...)
    print(string.format("[TXRChaseCam] " .. fmt .. "\n", ...))
end

local function valid(obj)
    return obj ~= nil and obj:IsValid()
end

local function wrap(a) return (a + 180) % 360 - 180 end

local function clamp(x, lo, hi)
    if x < lo then return lo end
    if x > hi then return hi end
    return x
end

-- State -------------------------------------------------------------------

local state = {
    pc = nil,
    pawnAddr = nil,
    pawn = nil,
    armAddrs = {},     -- addresses of the player car's BP_CameraArm_C components
    arms = {},
    mainArm = nil,     -- the "CameraArm" one, read for the game's slip swing
    camYaw = nil,      -- lagged camera heading (world yaw)
    lastCarYaw = nil,
    offset = 0,
    yawRate = 0,
    kmh = 0,
    debug = false,
}

local function resetLag()
    state.camYaw = nil
    state.lastCarYaw = nil
    state.offset = 0
end

local function setArmOffsets(offset)
    for _, arm in ipairs(state.arms) do
        if valid(arm) then arm:SetYawOffset(offset) end
    end
end

-- Finds the player's car and its camera arms again when the pawn changes.
local function refreshPawn()
    if not valid(state.pc) then
        state.pc = FindFirstOf("PlayerController")
        if not valid(state.pc) then return false end
    end
    local pawn = state.pc.Pawn
    if not valid(pawn) then return false end
    local addr = pawn:GetAddress()
    if addr == state.pawnAddr then return true end

    state.pawnAddr = addr
    state.pawn = pawn
    state.arms, state.armAddrs, state.mainArm = {}, {}, nil
    for _, arm in ipairs(FindAllOf("BP_CameraArm_C") or {}) do
        local owner = arm:GetOwner()
        if valid(owner) and owner:GetAddress() == addr then
            table.insert(state.arms, arm)
            state.armAddrs[arm:GetAddress()] = true
            -- "CameraArm" carries the default chase camera; "CameraArmForFar" is clamped at 10 degrees.
            if arm:GetFName():ToString() == "CameraArm" then state.mainArm = arm end
        end
    end
    state.mainArm = state.mainArm or state.arms[1]
    resetLag()
    log("car %s: found %d camera arm(s)", pawn:GetFName():ToString(), #state.arms)
    return true
end

-- Per-frame update --------------------------------------------------------

local function update(dt)
    if dt <= 0 or dt > 0.25 then return end
    local pawn = state.pawn
    if not valid(pawn) then return end

    local carYaw = pawn:K2_GetActorRotation().Yaw
    local v = pawn:GetVelocity()
    local kmh = math.sqrt(v.X * v.X + v.Y * v.Y) * 0.036
    state.kmh = kmh

    if state.camYaw == nil then
        state.camYaw = carYaw
        state.lastCarYaw = carYaw
    end

    local step = wrap(carYaw - state.lastCarYaw)
    state.lastCarYaw = carYaw
    if math.abs(step) > Config.SnapResetDegrees then
        resetLag()
        state.camYaw, state.lastCarYaw = carYaw, carYaw
        return
    end
    state.yawRate = step / dt

    -- First-order lag of the camera heading toward the car heading.
    local alpha = 1 - math.exp(-Config.LagSpeed * dt)
    state.camYaw = wrap(state.camYaw + wrap(carYaw - state.camYaw) * alpha)

    -- Keep the trailing angle inside MaxOffset by dragging the camera heading along.
    local trail = clamp(wrap(state.camYaw - carYaw), -Config.MaxOffset, Config.MaxOffset)
    state.camYaw = wrap(carYaw + trail)

    local speedFade = clamp((kmh - Config.MinSpeedKmh) / math.max(Config.FullSpeedKmh - Config.MinSpeedKmh, 1), 0, 1)
    -- The arm's slip_angle is the game's own (already smoothed) swing, so fading by it is continuous.
    local gameSlip = 0
    pcall(function() gameSlip = state.mainArm.slip_angle end)
    local slipFrac = clamp(math.abs(gameSlip) / Config.GameSlipMax, 0, 1)
    local driftScale = 1 + (Config.DriftScale - 1) * slipFrac

    state.offset = trail * speedFade * driftScale

    local orbitYaw = updateOrbit(dt)
    setArmOffsets(state.offset + orbitYaw)

    applyCloseViewOffsets()
end

-- Orbit -------------------------------------------------------------------

-- Latest look signal per direction, written by the input hooks: { mag = 0..1, at = os.clock() }.
local look = { Left = nil, Right = nil, Back = nil }
-- lastSide: which side (-1 left, 1 right) the stick was last on, to resolve "down only".
-- lowerHalf: whether the stick was last below horizontal, to resolve "side only".
local orbit = { yaw = 0, lastInputAt = -1, lastSide = 0, lowerHalf = false }

-- Rebuilds the look angle (0 = forward, +90 = right, 180 = back) from the thresholded
-- signals, assuming the stick is at the edge of its gate. Returns nil when nothing fires.
local function stickLookAngle(x, back)
    if x == 0 and back == 0 then return nil end
    local fwd
    if back > 0 then
        if x == 0 then
            x = orbit.lastSide * math.sqrt(math.max(0, 1 - back * back))
        end
        fwd = -back
    else
        local y = math.sqrt(math.max(0, 1 - x * x))
        fwd = orbit.lowerHalf and -y or y
    end
    if x ~= 0 then orbit.lastSide = x > 0 and 1 or -1 end
    orbit.lowerHalf = fwd < 0
    return math.deg(math.atan(x, fwd))
end

local function lookActive(dir)
    local l = look[dir]
    -- Events fire every frame while held, so 50 ms without one means released.
    return l ~= nil and os.clock() - l.at < 0.05, l and l.mag or 0
end

-- Only the chase (camera_type 0) and far (8) views orbit; cockpit and bonnet stay vanilla.
local function orbitView(pawn)
    local ok, t = pcall(function() return pawn.camera_type end)
    if not ok then return nil end
    if t == 0 then return pawn.OutCamera end
    if t == 8 then return pawn.FarCamera end
    return nil
end

function updateOrbit(dt)
    local pawn = state.pawn
    local mainCam = Config.OrbitEnabled and orbitView(pawn) or nil
    if mainCam == nil then
        orbit.yaw = 0
        return 0
    end

    local now = os.clock()
    local backOn, backMag = lookActive("Back")
    local rightOn, rightMag = lookActive("Right")
    local leftOn, leftMag = lookActive("Left")
    local held = backOn or rightOn or leftOn

    if Config.OrbitMode == "direct" then
        local x = (rightOn and clamp(rightMag, 0, 1) or 0) - (leftOn and clamp(leftMag, 0, 1) or 0)
        if Config.OrbitInvert then x = -x end
        local target = stickLookAngle(x, backOn and clamp(backMag, 0, 1) or 0)
        if target ~= nil then
            orbit.yaw = wrap(orbit.yaw + wrap(target - orbit.yaw) * (1 - math.exp(-Config.OrbitFollowSpeed * dt)))
            orbit.lastInputAt = now
        elseif now - orbit.lastInputAt > Config.OrbitReturnDelay then
            orbit.yaw = wrap(orbit.yaw) * math.exp(-Config.OrbitReturnSpeed * dt)
            if math.abs(orbit.yaw) < 0.05 then orbit.yaw = 0 end
            orbit.lastSide, orbit.lowerHalf = 0, false
        end
        suppressGameLookCamera(pawn, mainCam, held)
        return orbit.yaw
    end

    -- Spin mode. Signals start at ~0.75; map 0.75..1 to 40%..100% speed.
    local function rate(mag) return 0.4 + 0.6 * clamp((mag - 0.75) / 0.25, 0, 1) end
    local x = (rightOn and rate(rightMag) or 0) - (leftOn and rate(leftMag) or 0)
    if Config.OrbitInvert then x = -x end

    if backOn then
        -- Swing toward the front (180), the short way round.
        local target = orbit.yaw >= 0 and 180 or -180
        local stepMax = Config.OrbitSpeed * dt
        orbit.yaw = orbit.yaw + clamp(target - orbit.yaw, -stepMax, stepMax)
        orbit.lastInputAt = now
    elseif x ~= 0 then
        orbit.yaw = wrap(orbit.yaw + x * Config.OrbitSpeed * dt)
        orbit.lastInputAt = now
    elseif now - orbit.lastInputAt > Config.OrbitReturnDelay then
        orbit.yaw = wrap(orbit.yaw) * math.exp(-Config.OrbitReturnSpeed * dt)
        if math.abs(orbit.yaw) < 0.05 then orbit.yaw = 0 end
    end

    suppressGameLookCamera(pawn, mainCam, held)
    return orbit.yaw
end

-- While the stick is held (or the camera hasn't come back yet), keep the game's fixed look
-- camera (RearCamera) off and the chase/far camera on, so our orbit is what's shown.
function suppressGameLookCamera(pawn, mainCam, held)
    if not held and orbit.yaw == 0 then return end
    local rear = pawn.RearCamera
    if valid(rear) and rear:IsActive() then
        rear:Deactivate()
        mainCam:Activate(false)
    end
end

-- Hooks the controller's Enhanced Input events for the look actions
-- (InpActEvt_IA_NIG_ViewLeft/Right/Back_K2Node_EnhancedInputActionEvent_N). ViewLeft reports
-- 1 + x (0.25 at the threshold, 0 at full left), the others report the magnitude.
local inputLib = nil
local inputHookedClass = nil

function hookLookInput()
    local pc = state.pc
    if not valid(pc) then return false end
    local cls = pc:GetClass()
    local classPath = cls:GetFullName():match("%s(.+)$")
    if inputHookedClass == classPath then return true end
    inputLib = inputLib or StaticFindObject("/Script/EnhancedInput.Default__EnhancedInputLibrary")
    local count = 0
    cls:ForEachFunction(function(fn)
        local n = fn:GetFName():ToString()
        local dir = n:match("^InpActEvt_IA_NIG_View(%a+)_K2Node_EnhancedInputActionEvent_%d+$")
        if dir == "Left" or dir == "Right" or dir == "Back" then
            local ok = pcall(RegisterHook, classPath .. ":" .. n, function(_, value)
                local v = 0
                pcall(function() v = inputLib:Conv_InputActionValueToAxis2D(value:get()).X end)
                local mag = dir == "Left" and (1 - v) or v
                look[dir] = { mag = mag, at = os.clock() }
            end)
            if ok then count = count + 1 end
        end
    end)
    if count == 0 then return false end
    inputHookedClass = classPath
    log("hooked %d look input event(s) on %s", count, cls:GetFName():ToString())
    return true
end

-- Distance/height for the close view. Only called when a value changes (or the car changes):
-- calling the setters every frame changed how the camera moved in turns.
local applied = { arm = nil, distance = 0, height = 0 }
function applyCloseViewOffsets()
    local main = state.mainArm
    if not valid(main) or main:GetFName():ToString() ~= "CameraArm" then return end
    local addr = main:GetAddress()
    if applied.arm ~= addr then
        applied = { arm = addr, distance = 0, height = 0 } -- a fresh arm starts at 0
    end
    if applied.distance ~= Config.CloseDistanceOffset then
        main:SetTargetLengthOffset(Config.CloseDistanceOffset)
        applied.distance = Config.CloseDistanceOffset
    end
    if applied.height ~= Config.CloseHeightOffset then
        main:SetRelativeLocationZOffset(Config.CloseHeightOffset)
        applied.height = Config.CloseHeightOffset
    end
end

-- Hooking the arm's tick --------------------------------------------------
-- The arm Blueprint's ReceiveTick runs once per frame per arm. We run our update once per
-- frame (on the first player arm that ticks) so the offset is in place for the arm's own math.

local hooked = false

local function onArmTick(ctx, deltaSeconds)
    if not Config.Enabled then return end
    local arm = ctx:get()
    if not refreshPawn() then return end
    if not state.armAddrs[arm:GetAddress()] then return end
    -- Each player arm ticks once per frame; only update on the first one.
    if arm:GetAddress() ~= state.arms[1]:GetAddress() then return end
    if inputHookedClass == nil and Config.OrbitEnabled then
        local okH, errH = pcall(hookLookInput)
        if not okH then
            log("look input hook failed: %s", tostring(errH))
            Config.OrbitEnabled = false
        end
    end
    local ok, err = pcall(update, deltaSeconds:get())
    if not ok then log("update failed: %s", tostring(err)) end
end

local function tryHook()
    if hooked then return true end
    local arm = FindFirstOf("BP_CameraArm_C")
    if not valid(arm) then return false end
    -- "BlueprintGeneratedClass /Game/.../BP_CameraArm.BP_CameraArm_C" -> path after the space
    local classPath = arm:GetClass():GetFullName():match("%s(.+)$")
    local fnPath = classPath .. ":ReceiveTick"
    local ok, err = pcall(RegisterHook, fnPath, onArmTick)
    if not ok then
        log("could not hook %s: %s", fnPath, tostring(err))
        return false
    end
    hooked = true
    log("hooked %s", fnPath)
    return true
end

-- The arm Blueprint only loads once a car spawns, so keep trying until it exists.
LoopAsync(1000, function()
    ExecuteInGameThread(function() pcall(tryHook) end)
    return hooked
end)

-- Debug log ---------------------------------------------------------------

-- "cam-car" is measured from the camera manager, so it shows whether the offset turns the
-- camera the intended way (it should be close to offset, plus the game's own slip swing).
LoopAsync(250, function()
    if state.debug then
        ExecuteInGameThread(function()
            pcall(function()
                local gap = wrap(state.pc.PlayerCameraManager:GetCameraRotation().Yaw - state.pawn:K2_GetActorRotation().Yaw)
                local gameSlip = 0
                pcall(function() gameSlip = state.mainArm.slip_angle end)
                log("%s %6.1f km/h  yaw rate %7.1f deg/s  offset %6.2f  orbit %7.1f  game slip %6.2f  cam-car %6.2f",
                    Config.Enabled and "ON " or "OFF", state.kmh, state.yawRate, state.offset, orbit.yaw, gameSlip, gap)
            end)
        end)
    end
    return false
end)

-- Keys --------------------------------------------------------------------

RegisterKeyBind(Key.F6, { ModifierKey.CONTROL }, function()
    Config.Enabled = not Config.Enabled
    ExecuteInGameThread(function()
        resetLag()
        pcall(setArmOffsets, 0)
        pcall(function()
            state.mainArm:SetTargetLengthOffset(0)
            state.mainArm:SetRelativeLocationZOffset(0)
            applied = { arm = state.mainArm:GetAddress(), distance = 0, height = 0 }
        end)
    end)
    log("chase cam %s", Config.Enabled and "ON" or "OFF (vanilla)")
end)

RegisterKeyBind(Key.F5, { ModifierKey.CONTROL }, function()
    state.debug = not state.debug
    log("debug log %s", state.debug and "ON" or "OFF")
end)

local function tuned()
    log("LagSpeed %.1f  MaxOffset %d  CloseDistanceOffset %d  CloseHeightOffset %d",
        Config.LagSpeed, Config.MaxOffset, Config.CloseDistanceOffset, Config.CloseHeightOffset)
end

RegisterKeyBind(Key.PAGE_UP, { ModifierKey.CONTROL }, function()
    Config.CloseDistanceOffset = Config.CloseDistanceOffset + 25
    tuned()
end)
RegisterKeyBind(Key.PAGE_DOWN, { ModifierKey.CONTROL }, function()
    Config.CloseDistanceOffset = Config.CloseDistanceOffset - 25
    tuned()
end)
RegisterKeyBind(Key.HOME, { ModifierKey.CONTROL }, function()
    Config.CloseHeightOffset = Config.CloseHeightOffset + 10
    tuned()
end)
RegisterKeyBind(Key.END, { ModifierKey.CONTROL }, function()
    Config.CloseHeightOffset = Config.CloseHeightOffset - 10
    tuned()
end)

RegisterKeyBind(Key.UP_ARROW, { ModifierKey.CONTROL }, function()
    Config.LagSpeed = Config.LagSpeed + 0.5
    tuned()
end)
RegisterKeyBind(Key.DOWN_ARROW, { ModifierKey.CONTROL }, function()
    Config.LagSpeed = math.max(0.5, Config.LagSpeed - 0.5)
    tuned()
end)
RegisterKeyBind(Key.RIGHT_ARROW, { ModifierKey.CONTROL }, function()
    Config.MaxOffset = math.min(45, Config.MaxOffset + 5)
    tuned()
end)
RegisterKeyBind(Key.LEFT_ARROW, { ModifierKey.CONTROL }, function()
    Config.MaxOffset = math.max(0, Config.MaxOffset - 5)
    tuned()
end)

log("loaded (LagSpeed %.1f, MaxOffset %d). Ctrl+F6 toggle, Ctrl+arrows tune, Ctrl+F5 debug", Config.LagSpeed, Config.MaxOffset)
