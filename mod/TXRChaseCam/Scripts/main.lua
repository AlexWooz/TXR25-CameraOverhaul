-- TXRChaseCam: loose chase camera for Tokyo Xtreme Racer.
--
-- The vanilla chase camera (OutCamera on the car's CameraArm, a BP_CameraArm_C) is rigidly
-- attached to the car body; the only swing it has is the slip-angle offset while sliding.
-- This mod keeps a "camera heading" that trails the car's heading through a first-order lag,
-- and feeds the difference into the arm's own SetYawOffset() every frame. The camera then
-- falls behind when the car turns in, showing the side of the car, and catches up on exit.
-- The game's slip-angle swing keeps working on top of it.
--
-- Settings: the defaults are in the Config table below; players override them in
-- Scripts/config.lua (loaded on start and on UE4SS hot reload).
--
-- Keys:
--   Ctrl+F6          toggle the mod on/off (to compare with vanilla)
-- With DevKeys = true (config.lua), also:
--   Ctrl+Up/Down     LagSpeed +/- 0.5   (higher = stiffer, catches up faster)
--   Ctrl+Right/Left  MaxOffset +/- 5    (max degrees the camera can trail)
--   Ctrl+F5          toggle debug log (4x/s: speed, yaw rate, offset)
--   Ctrl+PgUp/PgDn   close-view distance +/- 25
--   Ctrl+Home/End    close-view height +/- 10
--   Ctrl+Ins/Del     nitro FOV +/- 5
--   Ctrl+] / [       game's vertical shake scale +/- 0.1
--   Ctrl+= / -       speed shake strength +/- 0.1
--   Ctrl+B           motion blur + boost fringe/vignette on/off
--
-- Right stick (controller): orbit around the car in the chase and far views. Left/right spins
-- the camera, down swings it to the front, releasing eases it back. See the Orbit section.

local Config = {
    Enabled = true,
    -- Tuning keys (Ctrl+arrows, PgUp/PgDn, ...) and the Ctrl+F5 debug log. Off for players.
    DevKeys = false,
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

    -- FOV while boosting (car's nitro_camera_fov; vanilla 120, normal is 90). The "camera goes
    -- far back" feel on nitro is this FOV; the arm's own pull-back is only ~10 units.
    NitroFov = 105,
    -- The game's own shake is a vertical bounce (BP_LinearShake on the arm, 80-250 km/h);
    -- VerticalShakeScale multiplies it through the arm's SetShakeCoef. Our shake replaces most of it.
    VerticalShakeScale = 0.25,

    -- Speed shake: smooth noise on the camera's own rotation (the arm carries the camera, the
    -- camera's relative rotation is otherwise untouched by the game). A fast vibration plus a
    -- slower sway; both get stronger AND faster with speed between ShakeMinKmh and ShakeMaxKmh
    -- (intensity ramps as speed^ShakeCurve, so it's calm when cruising and builds near the top).
    ShakeStrength = 1.0,       -- overall multiplier (Ctrl+= / Ctrl+-)
    ShakeMinKmh = 40,
    ShakeMaxKmh = 280,
    ShakeCurve = 1.3,
    ShakeHzMin = 5,            -- vibration frequency at ShakeMinKmh -> ShakeHzMax at ShakeMaxKmh
    ShakeHzMax = 14,
    ShakePitch = 0.25,         -- degrees at ShakeMaxKmh
    ShakeYaw = 0.20,
    ShakeRoll = 0.35,
    SwayHzMin = 0.6,           -- sway frequency, same idea
    SwayHzMax = 2.0,
    SwayYaw = 0.35,
    SwayRoll = 0.45,

    -- Boost (detected from the car's nitro_charge dropping). Starting a boost gives a short kick
    -- (extra shake and FOV) that decays; holding it adds a little shake, fringe and vignette.
    BoostKickShake = 2.5,      -- extra shake multiplier at the kick's peak
    BoostKickFov = 8,          -- extra degrees on top of NitroFov at the kick's peak
    BoostKickDecay = 3,        -- 1/s
    BoostHoldShake = 0.5,      -- extra shake multiplier while boosting
    BoostFringe = 1.5,         -- chromatic aberration while boosting (0 = off)
    BoostVignette = 0.25,      -- extra vignette while boosting (0 = off)

    -- Acceleration feel: widens the arm's own acceleration movement range [min, max] =
    -- [-AccelPushIn, AccelPullback] (vanilla [0, 10]): the camera falls back further when
    -- accelerating and closes in a little when braking.
    AccelPullback = 50,
    AccelPushIn = 15,

    -- Motion blur that grows with speed (r.MotionBlur.Amount; 0 = leave the game's). Only
    -- visible if motion blur is enabled in the game's graphics options.
    MotionBlurMax = 0.4,       -- blur amount at ShakeMaxKmh
    PostFx = true,             -- motion blur + boost fringe/vignette (Ctrl+B)

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
    -- With the TXRChaseCamInput C++ mod installed, direct mode reads the real stick through
    -- XInput (any angle, any deflection past this dead zone) instead of the game's signals.
    OrbitStickDeadZone = 0.3,
    -- Real stick only: a partial push turns the camera partway (half right ~ 45 degrees),
    -- reaching the full angle at OrbitStickFullAt deflection. false = direction only.
    OrbitScaleWithDeflection = true,
    OrbitStickFullAt = 0.95,
    OrbitSpeed = 150,          -- spin: degrees per second at full deflection
    OrbitInvert = false,       -- flip left/right
    OrbitReturnDelay = 0.03,   -- seconds after release before easing back (bridges gaps between signals)
    OrbitReturnSpeed = 12,     -- how fast it eases back (1/s); 12 covers 90 degrees in about 0.25 s

    -- Blend instead of hard-cutting when the view returns to the car (e.g. after the
    -- leave-garage pan, which vanilla ends with a cut).
    SmoothViewCuts = true,
    ViewCutBlendTime = 1.2,    -- seconds
    ViewCutBlendExp = 2,       -- ease-in/out sharpness
}

local function log(fmt, ...)
    print(string.format("[TXRChaseCam] " .. fmt .. "\n", ...))
end

-- Player config -------------------------------------------------------------
-- Scripts/config.lua returns a table of overrides, e.g. return { NitroFov = 110 }. It's loaded
-- by path next to this file (not require, so a "config" module elsewhere can't shadow it).
-- Unknown names and wrong types are reported and ignored; a broken file keeps the defaults.
do
    local source = (debug and debug.getinfo) and (debug.getinfo(1, "S").source or "") or ""
    local dir = source:match("^@(.*[\\/])") or ""
    local path = dir .. "config.lua"
    local f = io and io.open(path, "r")
    if io and f == nil then
        log("no config.lua next to main.lua, using defaults")
    else
        if f then f:close() end
        local ok, user = pcall(dofile, path)
        if not ok then
            log("config.lua has an error, using defaults: %s", tostring(user))
        elseif type(user) ~= "table" then
            log("config.lua must end with 'return { ... }', using defaults")
        else
            local applied = 0
            for k, v in pairs(user) do
                if Config[k] == nil then
                    log("config.lua: unknown setting '%s' ignored", tostring(k))
                elseif type(v) ~= type(Config[k]) then
                    log("config.lua: '%s' should be a %s, ignored", k, type(Config[k]))
                else
                    Config[k] = v
                    applied = applied + 1
                end
            end
            log("config.lua: %d setting(s) applied", applied)
        end
    end
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
    local boost = updateBoost(dt, pawn)
    applyNitroFov(pawn, Config.BoostKickFov * boost.kick)
    applyVerticalShake()
    applyAccelFeel()
    applySpeedShake(dt, kmh, pawn, boost)
    applyPostFx(kmh, pawn, boost)
    debugTick(dt)
end

-- Nitro FOV and shake -------------------------------------------------------
-- Like the distance/height setters, these only write when the game's value differs from ours,
-- so the game is free to reset them (new car, menus) and we put them back.

local vanilla = { nitroFov = nil, nitroOffset = nil, maxMove = {}, minMove = {}, camRot = {} }

function applyNitroFov(pawn, extra)
    local ok, cur = pcall(function() return pawn.nitro_camera_fov end)
    if not ok or type(cur) ~= "number" then return end
    if vanilla.nitroFov == nil then
        vanilla.nitroFov, vanilla.nitroOffset = cur, pawn.nitro_offset_fov
    end
    local want = Config.NitroFov + (extra or 0)
    if math.abs(cur - want) > 0.01 then
        pawn.nitro_camera_fov = want
        -- nitro_offset_fov (vanilla 30) is the same boost expressed relative to default_camera_fov.
        pcall(function() pawn.nitro_offset_fov = want - pawn.default_camera_fov end)
    end
end

function applyVerticalShake()
    for _, arm in ipairs(state.arms) do
        if valid(arm) then
            local ok, cur = pcall(function() return arm.shake_coef end)
            if ok and type(cur) == "number" and math.abs(cur - Config.VerticalShakeScale) > 0.001 then
                arm:SetShakeCoef(Config.VerticalShakeScale)
            end
        end
    end
end

-- Boost -------------------------------------------------------------------
-- No boost flag was found on the car, but nitro_charge drains while boosting (and only then),
-- so a falling charge means boosting. level eases 0..1 with it; kick jumps to 1 when a boost
-- starts and decays.
local boost = { lastCharge = nil, rate = 0, active = false, level = 0, kick = 0 }

function updateBoost(dt, pawn)
    local ok, charge = pcall(function() return pawn.nitro_charge end)
    if ok and type(charge) == "number" then
        if boost.lastCharge ~= nil then
            -- Smoothed drain rate (charge units per second; positive = draining).
            local r = (boost.lastCharge - charge) / dt
            boost.rate = boost.rate + (r - boost.rate) * (1 - math.exp(-10 * dt))
        end
        boost.lastCharge = charge
    end
    local active = boost.rate > 50
    if active and not boost.active then boost.kick = 1 end
    boost.active = active
    boost.level = boost.level + ((active and 1 or 0) - boost.level) * (1 - math.exp(-4 * dt))
    boost.kick = boost.kick * math.exp(-Config.BoostKickDecay * dt)
    return boost
end

-- Speed shake ---------------------------------------------------------------

-- Smooth 1D value noise in -1..1 (hashed lattice values, smoothstep between them).
local function hash(i, seed)
    local x = math.sin(i * 127.1 + seed * 311.7) * 43758.5453
    return (x - math.floor(x)) * 2 - 1
end
local function noise(t, seed)
    local i = math.floor(t)
    local f = t - i
    local u = f * f * (3 - 2 * f)
    return hash(i, seed) * (1 - u) + hash(i + 1, seed) * u
end
local function fbm(t, seed)
    return noise(t, seed) * 0.7 + noise(t * 2.13, seed + 17) * 0.3
end

-- Noise phases, advanced by frequency * dt each frame so the frequency can change smoothly
-- with speed (using time * frequency would jump whenever the frequency changes).
local shakePhase, swayPhase = 0, 0

-- The chase cameras (OutCamera on CameraArm, FarCamera on CameraArmForFar); their relative
-- rotation is ours to use. The first value seen is kept as the rest pose.
local function chaseCameras(pawn)
    local cams = {}
    for _, n in ipairs({ "OutCamera", "FarCamera" }) do
        local ok, c = pcall(function() return pawn[n] end)
        if ok and valid(c) then
            local addr = c:GetAddress()
            if vanilla.camRot[addr] == nil then
                local r = c.RelativeRotation
                vanilla.camRot[addr] = { Pitch = r.Pitch or 0, Yaw = r.Yaw or 0, Roll = r.Roll or 0 }
            end
            table.insert(cams, c)
        end
    end
    return cams
end

local function setCamRotation(cam, p, y, r)
    local base = vanilla.camRot[cam:GetAddress()]
    cam:K2_SetRelativeRotation({ Pitch = base.Pitch + p, Yaw = base.Yaw + y, Roll = base.Roll + r }, false, {}, false)
end

function applySpeedShake(dt, kmh, pawn, b)
    local span = math.max(Config.ShakeMaxKmh - Config.ShakeMinKmh, 1)
    local lin = clamp((kmh - Config.ShakeMinKmh) / span, 0, 1)
    local sf = lin ^ Config.ShakeCurve
    local intensity = Config.ShakeStrength * (sf * (1 + Config.BoostHoldShake * b.level)
        + Config.BoostKickShake * b.kick * math.max(sf, 0.3))
    state.shakeIntensity = intensity

    -- Faster with speed (boost pushes it a bit further).
    local speedHz = clamp(lin + 0.3 * b.level, 0, 1.3)
    local shakeHz = Config.ShakeHzMin + (Config.ShakeHzMax - Config.ShakeHzMin) * speedHz
    local swayHz = Config.SwayHzMin + (Config.SwayHzMax - Config.SwayHzMin) * speedHz
    state.shakeHz = shakeHz
    shakePhase = (shakePhase + shakeHz * dt) % 100000
    swayPhase = (swayPhase + swayHz * dt) % 100000

    local tf, ts = shakePhase, swayPhase
    local p = intensity * Config.ShakePitch * fbm(tf, 1)
    local y = intensity * (Config.ShakeYaw * fbm(tf, 2) + Config.SwayYaw * noise(ts, 3))
    local r = intensity * (Config.ShakeRoll * fbm(tf, 4) + Config.SwayRoll * noise(ts, 5))
    for _, cam in ipairs(chaseCameras(pawn)) do
        setCamRotation(cam, p, y, r)
    end
end

-- Acceleration feel ---------------------------------------------------------
-- The arm already moves the camera along its length with acceleration (acc_scale_for_x_move),
-- clamped to [min_move_target_length, max_move_target_length] = [0, 10] in vanilla.

function applyAccelFeel()
    for _, arm in ipairs(state.arms) do
        if valid(arm) then
            local addr = arm:GetAddress()
            pcall(function()
                if vanilla.maxMove[addr] == nil then
                    vanilla.maxMove[addr], vanilla.minMove[addr] = arm.max_move_target_length, arm.min_move_target_length
                end
                if arm.max_move_target_length ~= Config.AccelPullback then arm.max_move_target_length = Config.AccelPullback end
                if arm.min_move_target_length ~= -Config.AccelPushIn then arm.min_move_target_length = -Config.AccelPushIn end
            end)
        end
    end
end

-- Post-process: speed motion blur, boost fringe and vignette ------------------
-- Written into the chase cameras' PostProcessSettings (blend weight 1). If the struct can't be
-- written from Lua, this logs once and switches itself off.

local postFxBroken = false

-- Motion blur goes through the r.MotionBlur.Amount cvar (writes into the camera's
-- PostProcessSettings had no visible effect in test 1). -1 = use the game's post-process value.
local ksl = nil
lastBlur = nil
local function setBlurCvar(amount, pawn)
    if lastBlur ~= nil and math.abs(amount - lastBlur) < 0.02 then return end
    ksl = ksl or StaticFindObject("/Script/Engine.Default__KismetSystemLibrary")
    ksl:ExecuteConsoleCommand(pawn, string.format("r.MotionBlur.Amount %.2f", amount), state.pc)
    lastBlur = amount
end

local function setPostFx(cam, fringe, vignette)
    local pp = cam.PostProcessSettings
    pp.bOverride_SceneFringeIntensity = fringe ~= nil
    if fringe ~= nil then pp.SceneFringeIntensity = fringe end
    pp.bOverride_VignetteIntensity = vignette ~= nil
    if vignette ~= nil then pp.VignetteIntensity = vignette end
end

function applyPostFx(kmh, pawn, b)
    local on = Config.PostFx
    local span = math.max(Config.ShakeMaxKmh - Config.ShakeMinKmh, 1)
    local sf = clamp((kmh - Config.ShakeMinKmh) / span, 0, 1)
    local okB, errB = pcall(setBlurCvar, (on and Config.MotionBlurMax > 0) and (Config.MotionBlurMax * sf) or -1, pawn)
    if not okB and lastBlur == nil then
        log("motion blur cvar failed: %s", tostring(errB))
        lastBlur = -2
    end

    if postFxBroken then return end
    local fringe = (on and Config.BoostFringe > 0) and (Config.BoostFringe * b.level) or nil
    -- 0.4 is UE's default vignette intensity.
    local vignette = (on and Config.BoostVignette > 0) and (0.4 + Config.BoostVignette * b.level) or nil
    for _, cam in ipairs(chaseCameras(pawn)) do
        local ok, err = pcall(setPostFx, cam, fringe, vignette)
        if not ok then
            log("post-process override unavailable (%s); motion blur/fringe/vignette off", tostring(err))
            postFxBroken = true
            return
        end
    end
end

-- Puts the game's own camera behaviour back (mod toggled off).
function restoreVanillaCameraFx()
    local pawn = state.pawn
    if valid(pawn) and vanilla.nitroFov ~= nil then
        pawn.nitro_camera_fov = vanilla.nitroFov
        pcall(function() pawn.nitro_offset_fov = vanilla.nitroOffset end)
    end
    for _, arm in ipairs(state.arms) do
        if valid(arm) then
            local addr = arm:GetAddress()
            pcall(function() arm:SetShakeCoef(1) end)
            pcall(function()
                if vanilla.maxMove[addr] ~= nil then
                    arm.max_move_target_length = vanilla.maxMove[addr]
                    arm.min_move_target_length = vanilla.minMove[addr]
                end
            end)
        end
    end
    if valid(pawn) then
        for _, cam in ipairs(chaseCameras(pawn)) do
            pcall(setCamRotation, cam, 0, 0, 0)
            if not postFxBroken then pcall(setPostFx, cam, nil, nil) end
        end
        lastBlur = nil
        pcall(setBlurCvar, -1, pawn)
    end
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

-- TXRGetRightStick is registered by the TXRChaseCamInput C++ mod; without it (or with no
-- XInput controller) this reports "not connected" and the orbit uses the game's signals.
local loggedStickSource = nil
function readRealStick()
    local x, y, connected = 0, 0, false
    if TXRGetRightStick ~= nil then
        local ok, rx, ry, rc = pcall(TXRGetRightStick)
        if ok then x, y, connected = rx, ry, rc end
    end
    local source = connected and "XInput (TXRChaseCamInput)" or "game look signals"
    if source ~= loggedStickSource then
        log("orbit stick source: %s", source)
        loggedStickSource = source
    end
    return x, y, connected
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
        local target
        local sx, sy, connected = readRealStick()
        if connected then
            -- Real stick: look where it points (up = 0, right = +90, down = 180).
            if Config.OrbitInvert then sx = -sx end
            local mag = math.sqrt(sx * sx + sy * sy)
            if mag > Config.OrbitStickDeadZone then
                local angle = math.deg(math.atan(sx, sy))
                -- Near straight down the sign of x is noise; keep the side we were on so a
                -- partial push doesn't flip between left and right.
                if math.abs(angle) > 170 and orbit.lastSide ~= 0 then
                    angle = orbit.lastSide * math.abs(angle)
                elseif sx ~= 0 then
                    orbit.lastSide = sx > 0 and 1 or -1
                end
                if Config.OrbitScaleWithDeflection then
                    local span = math.max(Config.OrbitStickFullAt - Config.OrbitStickDeadZone, 0.01)
                    angle = angle * clamp((mag - Config.OrbitStickDeadZone) / span, 0, 1)
                end
                target = angle
                held = true
            end
        else
            local x = (rightOn and clamp(rightMag, 0, 1) or 0) - (leftOn and clamp(leftMag, 0, 1) or 0)
            if Config.OrbitInvert then x = -x end
            target = stickLookAngle(x, backOn and clamp(backMag, 0, 1) or 0)
        end
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

-- Smooth view cuts --------------------------------------------------------
-- Leaving the garage, the game pans over the car and then hard-cuts to the driving camera: the
-- view target switches to the car with no blend. When the view target becomes the car, we
-- spawn a plain CameraActor at the exact pose shown last frame, cut to it, and blend from it
-- to the car with SetViewTargetWithBlend. The camera is removed once the blend is done.

local cut = { driver = nil, driverSeenAt = 0, prevTarget = nil, prevAddr = nil, pov = nil,
              temp = nil, tempAddr = nil, removeAt = nil }

local function cameraPov(cm)
    -- The camera cache is a reflected property, unlike GetCameraRotation(), whose return value
    -- loses its Pitch in UE4SS.
    local pov = cm.CameraCachePrivate.POV
    local l, r = pov.Location, pov.Rotation
    return { loc = { X = l.X, Y = l.Y, Z = l.Z }, rot = { Pitch = r.Pitch, Yaw = r.Yaw, Roll = r.Roll }, fov = pov.FOV }
end

local function isCar(actor)
    local ok, armComp = pcall(function() return actor.CameraArm end)
    return ok and valid(armComp)
end

function viewCutTick(arm, dt)
    -- Every car's arm ticks; run once per frame, on one "driver" arm (re-picked if it goes away).
    local now = os.clock()
    if valid(cut.driver) and now - cut.driverSeenAt < 0.5 then
        if arm:GetAddress() ~= cut.driver:GetAddress() then return end
    else
        cut.driver = arm
    end
    cut.driverSeenAt = now

    if cut.temp ~= nil and now >= cut.removeAt then
        pcall(function() if valid(cut.temp) then cut.temp:K2_DestroyActor() end end)
        cut.temp, cut.tempAddr = nil, nil
    end

    if not valid(state.pc) then
        state.pc = FindFirstOf("PlayerController")
        if not valid(state.pc) then return end
    end
    local cm = state.pc.PlayerCameraManager
    if not valid(cm) then return end
    local target = cm.ViewTarget.Target
    local addr = valid(target) and target:GetAddress() or nil

    -- The camera cache holds the pose drawn last frame; cut.pov is the one drawn the frame before.
    local okP, drawn = pcall(cameraPov, cm)
    if not okP then drawn = nil end

    if addr ~= cut.prevAddr then
        log("view target: %s -> %s", valid(cut.prevTarget) and cut.prevTarget:GetFName():ToString() or "none",
            valid(target) and target:GetFName():ToString() or "none")
        local fromOther = cut.prevAddr ~= nil and cut.prevAddr ~= cut.tempAddr
        if Config.SmoothViewCuts and fromOther and drawn ~= nil and valid(target) and isCar(target)
            and target:GetAddress() == (valid(state.pc.Pawn) and state.pc.Pawn:GetAddress() or -1) then
            -- If the switch happened after our tick last frame, the cut was already drawn: the
            -- newest pose jumped away from the one before it, so blend from that older pose.
            local from, late = drawn, false
            if cut.pov ~= nil then
                local dx, dy, dz = drawn.loc.X - cut.pov.loc.X, drawn.loc.Y - cut.pov.loc.Y, drawn.loc.Z - cut.pov.loc.Z
                if dx * dx + dy * dy + dz * dz > 200 * 200 or math.abs(wrap(drawn.rot.Yaw - cut.pov.rot.Yaw)) > 25 then
                    from, late = cut.pov, true
                end
            end
            blendFromPov(target, from, late)
        end
    end
    cut.prevTarget, cut.prevAddr = target, addr
    if drawn ~= nil then cut.pov = drawn end
end

function blendFromPov(car, pov, late)
    local cls = StaticFindObject("/Script/Engine.CameraActor")
    local world = car:GetWorld()
    local temp = world:SpawnActor(cls, pov.loc, pov.rot)
    if not valid(temp) then
        log("view cut: couldn't spawn the blend camera")
        return
    end
    local cam = temp.CameraComponent
    cam.FieldOfView = pov.fov
    -- CameraActor letterboxes to 16:9 by default; the game doesn't (Steam Deck is 16:10).
    cam.bConstrainAspectRatio = false
    cut.temp, cut.tempAddr = temp, temp:GetAddress()
    cut.removeAt = os.clock() + Config.ViewCutBlendTime + 0.5

    -- Cut to the parked camera, then blend to the car. EViewTargetBlendFunction 4 = EaseInOut.
    state.pc:SetViewTargetWithBlend(temp, 0, 0, 0, false)
    state.pc:SetViewTargetWithBlend(car, Config.ViewCutBlendTime, 4, Config.ViewCutBlendExp, false)
    log("view cut smoothed: blending to %s over %.1f s%s", car:GetFName():ToString(), Config.ViewCutBlendTime,
        late and " (cut was already drawn for a frame)" or "")
end

-- Hooking the arm's tick --------------------------------------------------
-- The arm Blueprint's ReceiveTick runs once per frame per arm. We run our update once per
-- frame (on the first player arm that ticks) so the offset is in place for the arm's own math.

local hooked = false

local function onArmTick(ctx, deltaSeconds)
    if not Config.Enabled then return end
    local arm = ctx:get()
    -- Runs before the player-car checks: the cut it smooths happens as the game possesses the
    -- car, before that car is "ours".
    local okC, errC = pcall(viewCutTick, arm, deltaSeconds:get())
    if not okC then log("view cut smoothing failed: %s", tostring(errC)) end
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

-- Called from update() on the game thread, 4x/s while Ctrl+F5 is on. (A LoopAsync version read
-- these tables from UE4SS's async thread while the camera hook wrote them, and crashed the game.)
-- "cam-car" is measured from the camera manager, so it shows whether the offset turns the
-- camera the intended way (it should be close to offset, plus the game's own slip swing).
-- "cam rot" and "pp" read back what we wrote, to see whether shake/post-process stick.
local debugTimer = 0
function debugTick(dt)
    if not state.debug then return end
    debugTimer = debugTimer + dt
    if debugTimer < 0.25 then return end
    debugTimer = 0
    local ok, err = pcall(function()
        local gap = wrap(state.pc.PlayerCameraManager:GetCameraRotation().Yaw - state.pawn:K2_GetActorRotation().Yaw)
        local arm = state.mainArm
        local camRot, pp = "?", "?"
        pcall(function()
            local r = state.pawn.OutCamera.RelativeRotation
            camRot = string.format("%.2f/%.2f/%.2f", r.Pitch or 0, r.Yaw or 0, r.Roll or 0)
        end)
        pcall(function()
            local s = state.pawn.OutCamera.PostProcessSettings
            pp = string.format("fringe %s:%.2f vig %s:%.2f", tostring(s.bOverride_SceneFringeIntensity), s.SceneFringeIntensity,
                tostring(s.bOverride_VignetteIntensity), s.VignetteIntensity)
        end)
        log("%6.1f km/h  yaw rate %6.1f  offset %5.1f  orbit %6.1f  slip %5.1f  cam-car %5.1f  shake %.2f @%.1fHz  cam rot %s  boost %.2f/%.2f (rate %.0f)  arm acc %.1f len %.1f  fov %.1f  blur %.2f  %s",
            state.kmh, state.yawRate, state.offset, orbit.yaw, arm.slip_angle or 0, gap,
            state.shakeIntensity or 0, state.shakeHz or 0, camRot, boost.level, boost.kick, boost.rate,
            arm.acc or 0, arm.target_length or 0, state.pc.PlayerCameraManager:GetFOVAngle(), lastBlur or -1, pp)
    end)
    if not ok then log("debug failed: %s", tostring(err)) end
end

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
        if not Config.Enabled then pcall(restoreVanillaCameraFx) end
    end)
    log("chase cam %s", Config.Enabled and "ON" or "OFF (vanilla)")
end)

-- Everything below is for tuning (DevKeys = true in config.lua).
if Config.DevKeys then

RegisterKeyBind(Key.F5, { ModifierKey.CONTROL }, function()
    state.debug = not state.debug
    log("debug log %s", state.debug and "ON" or "OFF")
end)

local function tuned()
    log("LagSpeed %.1f  MaxOffset %d  CloseDistanceOffset %d  CloseHeightOffset %d  NitroFov %d  VerticalShakeScale %.1f  ShakeStrength %.1f  PostFx %s",
        Config.LagSpeed, Config.MaxOffset, Config.CloseDistanceOffset, Config.CloseHeightOffset,
        Config.NitroFov, Config.VerticalShakeScale, Config.ShakeStrength, tostring(Config.PostFx))
end

RegisterKeyBind(Key.B, { ModifierKey.CONTROL }, function()
    Config.PostFx = not Config.PostFx
    tuned()
end)

RegisterKeyBind(Key.INS, { ModifierKey.CONTROL }, function()
    Config.NitroFov = math.min(130, Config.NitroFov + 5)
    tuned()
end)
RegisterKeyBind(Key.DEL, { ModifierKey.CONTROL }, function()
    Config.NitroFov = math.max(60, Config.NitroFov - 5)
    tuned()
end)
RegisterKeyBind(Key.OEM_SIX, { ModifierKey.CONTROL }, function() -- ]
    Config.VerticalShakeScale = math.min(3, Config.VerticalShakeScale + 0.1)
    tuned()
end)
RegisterKeyBind(Key.OEM_FOUR, { ModifierKey.CONTROL }, function() -- [
    Config.VerticalShakeScale = math.max(0, Config.VerticalShakeScale - 0.1)
    tuned()
end)
RegisterKeyBind(Key.OEM_PLUS, { ModifierKey.CONTROL }, function() -- =
    Config.ShakeStrength = math.min(5, Config.ShakeStrength + 0.1)
    tuned()
end)
RegisterKeyBind(Key.OEM_MINUS, { ModifierKey.CONTROL }, function() -- -
    Config.ShakeStrength = math.max(0, Config.ShakeStrength - 0.1)
    tuned()
end)

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

end -- DevKeys

log("loaded. Ctrl+F6 toggles the mod%s", Config.DevKeys and "; dev keys on (Ctrl+arrows etc. tune, Ctrl+F5 debug)" or "")
