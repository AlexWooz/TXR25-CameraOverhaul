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
    setArmOffsets(state.offset)
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
                log("%s %6.1f km/h  yaw rate %7.1f deg/s  offset %6.2f  game slip %6.2f  cam-car %6.2f",
                    Config.Enabled and "ON " or "OFF", state.kmh, state.yawRate, state.offset, gameSlip, gap)
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
    end)
    log("chase cam %s", Config.Enabled and "ON" or "OFF (vanilla)")
end)

RegisterKeyBind(Key.F5, { ModifierKey.CONTROL }, function()
    state.debug = not state.debug
    log("debug log %s", state.debug and "ON" or "OFF")
end)

local function tuned()
    log("LagSpeed %.1f  MaxOffset %d", Config.LagSpeed, Config.MaxOffset)
end

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
