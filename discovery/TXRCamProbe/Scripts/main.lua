-- TXRCamProbe: dev-only UE4SS mod for the TXR chase camera project.
-- Not shipped. Finds out how the game builds its car camera and what changes while drifting.
--   Ctrl+F7 = dump pawn, controller, camera manager, every scene component on the car
--             (attach parent, world transform, which one the view is coming from) and the
--             car Blueprint's camera-related functions
--   Ctrl+F8 = toggle the live log (4x/s): speed, car yaw, camera yaw, gap, slip, drift_started.
--             While it runs, drifts are captured automatically: a grip baseline is kept every
--             second, and 0.5 s after drift_started turns on, the probe diffs against it.
--   Ctrl+F9 = manual snapshot/diff, as before
-- Output goes to the UE4SS console and ue4ss\UE4SS.log.

local function log(fmt, ...)
    print(string.format("[TXRCamProbe] " .. fmt .. "\n", ...))
end

local function valid(obj)
    return obj ~= nil and obj:IsValid()
end

local function name(obj)
    if valid(obj) then return obj:GetFullName() end
    return "<none>"
end

local function short(obj)
    if valid(obj) then return obj:GetFName():ToString() end
    return "<none>"
end

local function classChain(obj)
    local parts = {}
    local cls = obj:GetClass()
    while valid(cls) do
        table.insert(parts, cls:GetFName():ToString())
        cls = cls:GetSuperStruct()
    end
    return table.concat(parts, " -> ")
end

-- Struct return values from function calls sometimes come back with missing fields,
-- so format each one separately instead of letting string.format throw.
local function f1(x)
    if type(x) == "number" then return string.format("%.1f", x) end
    return tostring(x)
end

local function rotStr(r)
    if r == nil then return "?" end
    return "P " .. f1(r.Pitch) .. " Y " .. f1(r.Yaw) .. " R " .. f1(r.Roll)
end

local function vecStr(v)
    if v == nil then return "?" end
    return "(" .. f1(v.X) .. ", " .. f1(v.Y) .. ", " .. f1(v.Z) .. ")"
end

local function wrap(a) return (a + 180) % 360 - 180 end

local function getPC()
    local pc = FindFirstOf("PlayerController")
    if valid(pc) then return pc end
end

-- Formats one property value. Returns nil for types we don't snapshot.
local SIMPLE = { FloatProperty = true, DoubleProperty = true, IntProperty = true, BoolProperty = true,
                 ByteProperty = true, EnumProperty = true, NameProperty = true }
local function propValue(obj, prop)
    local pname = prop:GetFName():ToString()
    local ptype = prop:GetClass():GetFName():ToString()
    local ok, v = pcall(function() return obj[pname] end)
    if not ok then return nil end
    if SIMPLE[ptype] then
        if type(v) == "number" then return string.format("%.4g", v) end
        if type(v) == "userdata" and v.ToString then return v:ToString() end
        return tostring(v)
    end
    if ptype == "StructProperty" then
        local s = prop:GetStruct():GetFName():ToString()
        if s == "Vector" then return vecStr(v) end
        if s == "Rotator" then return rotStr(v) end
    end
    if ptype == "ObjectProperty" and type(v) == "userdata" and v.IsValid then
        return valid(v) and v:GetFName():ToString() or "None"
    end
    return nil
end

-- Calls fn(prop) for every property on obj's class and its supers.
local function forEachProp(obj, fn)
    local cls = obj:GetClass()
    while valid(cls) do
        cls:ForEachProperty(fn)
        cls = cls:GetSuperStruct()
    end
end

local function dumpProps(obj)
    forEachProp(obj, function(prop)
        local v = propValue(obj, prop)
        if v ~= nil then log("     %-40s %s", prop:GetFName():ToString(), v) end
    end)
end

local function sameObj(a, b)
    return valid(a) and valid(b) and a:GetAddress() == b:GetAddress()
end

-- Every SceneComponent owned by actor. FindAllOf walks every object in the world, so the
-- result is cached per actor; the auto drift capture calls this once a second.
local compCache = { addr = nil, list = {} }
local function componentsOf(actor)
    if compCache.addr == actor:GetAddress() then
        local fresh = {}
        for _, c in ipairs(compCache.list) do
            if valid(c) then table.insert(fresh, c) end
        end
        compCache.list = fresh
        return fresh
    end
    local out = {}
    for _, c in ipairs(FindAllOf("SceneComponent") or {}) do
        if valid(c) and sameObj(c:GetOwner(), actor) then table.insert(out, c) end
    end
    compCache = { addr = actor:GetAddress(), list = out }
    return out
end

local function isA(obj, className)
    local cls = obj:GetClass()
    while valid(cls) do
        if cls:GetFName():ToString() == className then return true end
        cls = cls:GetSuperStruct()
    end
    return false
end

local function step(label, fn)
    local ok, err = pcall(fn)
    if not ok then log("  (%s failed: %s)", label, tostring(err)) end
end

local CAM_WORDS = { "cam", "view", "drift", "look", "fov", "shake", "spring", "follow" }
local function camRelated(s)
    s = s:lower()
    for _, w in ipairs(CAM_WORDS) do
        if s:find(w, 1, true) then return true end
    end
    return false
end

-- Prints each function declared on cls with its parameters, e.g. "Foo(float InSpeed) -> out float Speed".
local function signature(fn)
    local ins, outs = {}, {}
    fn:ForEachProperty(function(p)
        local s = p:GetClass():GetFName():ToString():gsub("Property$", "") .. " " .. p:GetFName():ToString()
        local isOut = false
        pcall(function() isOut = p:HasAnyPropertyFlags(0x100 | 0x400) end) -- CPF_OutParm | CPF_ReturnParm
        table.insert(isOut and outs or ins, s)
    end)
    local sig = fn:GetFName():ToString() .. "(" .. table.concat(ins, ", ") .. ")"
    if #outs > 0 then sig = sig .. " -> " .. table.concat(outs, ", ") end
    return sig
end

function dumpFunctions(cls)
    log("     functions of %s:", cls:GetFName():ToString())
    cls:ForEachFunction(function(fn)
        log("       %s", signature(fn))
    end)
end

-- Calls the car's camera getters (no inputs) and prints what they return.
local function callGetters()
    local pc = getPC()
    if not pc or not valid(pc.Pawn) then log("no pawn") return end
    local pawn = pc.Pawn
    log("==== car camera getters ====")
    local cls = pawn:GetClass()
    while valid(cls) and cls:GetFName():ToString():match("_C$") do
        cls:ForEachFunction(function(fn)
            local n = fn:GetFName():ToString()
            if n:match("^Get") and camRelated(n) then
                log("  %s", signature(fn))
                local out = {}
                local ok, ret = pcall(function() return pawn[n](pawn, out) end)
                if not ok then
                    log("    call failed: %s", tostring(ret))
                else
                    local parts = {}
                    if ret ~= nil then table.insert(parts, "return=" .. tostring(ret)) end
                    for k, v in pairs(out) do
                        if type(v) == "number" then v = string.format("%.4g", v) end
                        table.insert(parts, tostring(k) .. "=" .. tostring(v))
                    end
                    log("    %s", #parts > 0 and table.concat(parts, "  ") or "(nothing returned)")
                end
            end
        end)
        cls = cls:GetSuperStruct()
    end
    log("==== end getters ====")
end

local function dumpAll()
    local pc = getPC()
    if not pc then log("no PlayerController") return end
    local pawn = pc.Pawn
    local cm = pc.PlayerCameraManager
    log("==== camera dump ====")
    log("PlayerController: %s", name(pc))
    log("Pawn: %s", name(pawn))
    if valid(pawn) then log("  class: %s", classChain(pawn)) end

    local camLoc
    step("camera manager", function()
        log("CameraManager: %s", name(cm))
        log("  class: %s", classChain(cm))
        log("  ViewTarget: %s", name(cm.ViewTarget.Target))
        camLoc = cm:GetCameraLocation()
        log("  cam loc %s rot %s fov %s", vecStr(camLoc), rotStr(cm:GetCameraRotation()), f1(cm:GetFOVAngle()))
    end)
    if not valid(pawn) then return end

    step("pawn rotation", function()
        log("  car loc %s rot %s", vecStr(pawn:K2_GetActorLocation()), rotStr(pawn:K2_GetActorRotation()))
    end)

    log("---- scene components on the car (* = camera or spring arm, <== = view comes from here) ----")
    local cams = {}
    step("components", function()
        for _, c in ipairs(componentsOf(pawn)) do
            local loc, rot, near = nil, nil, ""
            pcall(function() loc = c:K2_GetComponentLocation() end)
            pcall(function() rot = c:K2_GetComponentRotation() end)
            if camLoc and loc and type(loc.X) == "number" and type(camLoc.X) == "number" then
                local dx, dy, dz = loc.X - camLoc.X, loc.Y - camLoc.Y, loc.Z - camLoc.Z
                if dx * dx + dy * dy + dz * dz < 25 then near = "  <==" end
            end
            local isCam = isA(c, "CameraComponent") or isA(c, "SpringArmComponent")
                or c:GetClass():GetFName():ToString() == "BP_CameraArm_C"
            if isCam then table.insert(cams, c) end
            local parent = "?"
            pcall(function() parent = short(c:GetAttachParent()) end)
            log("%s %-28s %-26s parent %-24s rot %s%s", isCam and "*" or " ", short(c),
                c:GetClass():GetFName():ToString(), parent, rotStr(rot), near)
        end
    end)

    for _, c in ipairs(cams) do
        log("---- %s (%s) ----", short(c), classChain(c))
        step("props of " .. short(c), function() dumpProps(c) end)
        if c:GetClass():GetFName():ToString() == "BP_CameraArm_C" then
            step("functions of " .. short(c), function() dumpFunctions(c:GetClass()) end)
        end
    end

    log("---- camera-related functions and variables on the car Blueprint ----")
    step("functions", function()
        local cls = pawn:GetClass()
        while valid(cls) do
            local cname = cls:GetFName():ToString()
            if not cname:match("_C$") then break end -- native classes from here on
            local funcs, vars = {}, {}
            pcall(function()
                cls:ForEachFunction(function(fn)
                    local n = fn:GetFName():ToString()
                    if camRelated(n) then table.insert(funcs, n) end
                end)
            end)
            cls:ForEachProperty(function(prop)
                local n = prop:GetFName():ToString()
                if camRelated(n) then
                    table.insert(vars, n .. "=" .. tostring(propValue(pawn, prop)))
                end
            end)
            log("  %s", cname)
            log("    functions: %s", table.concat(funcs, ", "))
            log("    variables: %s", table.concat(vars, ", "))
            cls = cls:GetSuperStruct()
        end
    end)
    log("==== end camera dump ====")
end

-- Snapshot diff -----------------------------------------------------------

local function snapshot()
    local pc = getPC()
    if not pc then return {} end
    local objs = {}
    if valid(pc.Pawn) then table.insert(objs, pc.Pawn) end
    if valid(pc.PlayerCameraManager) then table.insert(objs, pc.PlayerCameraManager) end
    if valid(pc.Pawn) then
        for _, c in ipairs(componentsOf(pc.Pawn)) do table.insert(objs, c) end
    end
    local snap = {}
    for _, obj in ipairs(objs) do
        local oname = obj:GetFName():ToString()
        forEachProp(obj, function(prop)
            local v = propValue(obj, prop)
            if v ~= nil then snap[oname .. "." .. prop:GetFName():ToString()] = v end
        end)
    end
    return snap
end

-- Values that change every frame while driving and only add noise to a diff.
local NOISY = { "location", "speed", "rpm", "temp", "time", "torque", "drag", "nitro", "hit_", "impulse",
                "omega", "drive_rate", "_acc", "reverb", "road_point", "lan_rate" }
local function noisy(k)
    local lk = k:lower()
    for _, w in ipairs(NOISY) do
        if lk:find(w, 1, true) then return true end
    end
    return false
end

local function printDiff(title, a, b)
    log("==== %s ====", title)
    local keys = {}
    for k in pairs(b) do table.insert(keys, k) end
    table.sort(keys)
    local skipped = 0
    for _, k in ipairs(keys) do
        if a[k] ~= nil and a[k] ~= b[k] then
            if noisy(k) then
                skipped = skipped + 1
            else
                log("  %-60s %s  ->  %s", k, a[k], b[k])
            end
        end
    end
    log("==== end diff (%d noisy values hidden) ====", skipped)
end

local lastSnap = nil

local function snapAndDiff()
    local snap = snapshot()
    if lastSnap == nil then
        log("snapshot 1 taken. Change state and press Ctrl+F9 again.")
    else
        printDiff("changed since last snapshot", lastSnap, snap)
    end
    lastSnap = snap
end

-- Live log + automatic drift capture --------------------------------------

local watching = false
local gripBaseline = nil
local lastBaselineAt = 0
local wasDrifting = false
local driftCaptureAt = nil
local ticks = 0

local function watchTick()
    local pc = getPC()
    if not pc then return end
    local pawn, cm = pc.Pawn, pc.PlayerCameraManager
    if not valid(pawn) or not valid(cm) then return end
    ticks = ticks + 1
    local v = pawn:GetVelocity()
    local kmh = math.sqrt(v.X * v.X + v.Y * v.Y + v.Z * v.Z) * 0.036
    local carYaw = pawn:K2_GetActorRotation().Yaw
    local camYaw = cm:GetCameraRotation().Yaw
    local velYaw = math.deg(math.atan(v.Y, v.X))
    local drifting = false
    pcall(function() drifting = pawn.drift_started == true end)
    log("%6.1f km/h  car %7.1f  cam %7.1f  cam-car %6.1f  slip %6.1f  %s",
        kmh, carYaw, camYaw, wrap(camYaw - carYaw), kmh > 5 and wrap(velYaw - carYaw) or 0,
        drifting and "DRIFT" or "")

    -- Keep a fresh grip baseline (once a second, at speed, not drifting).
    if not drifting and kmh > 40 and ticks - lastBaselineAt >= 4 then
        gripBaseline = snapshot()
        lastBaselineAt = ticks
    end
    if drifting and not wasDrifting then
        driftCaptureAt = ticks + 2 -- 0.5 s into the drift
        log("drift started, capturing in 0.5 s")
    end
    if driftCaptureAt and ticks >= driftCaptureAt then
        driftCaptureAt = nil
        if gripBaseline then
            printDiff("AUTO: grip baseline -> mid-drift", gripBaseline, snapshot())
        else
            log("drift capture skipped: no grip baseline yet (drive above 40 km/h first)")
        end
    end
    wasDrifting = drifting
end

local function startWatch()
    LoopAsync(250, function()
        if not watching then return true end
        ExecuteInGameThread(function()
            local ok, err = pcall(watchTick)
            if not ok then log("watch failed: %s", tostring(err)) end
        end)
        return false
    end)
end

RegisterKeyBind(Key.F7, { ModifierKey.CONTROL }, function()
    ExecuteInGameThread(function()
        local ok, err = pcall(dumpAll)
        if not ok then log("dump failed: %s", tostring(err)) end
    end)
end)

RegisterKeyBind(Key.F8, { ModifierKey.CONTROL }, function()
    watching = not watching
    log("live log %s", watching and "ON (drifts are captured automatically)" or "OFF")
    if watching then startWatch() end
end)

RegisterKeyBind(Key.F9, { ModifierKey.CONTROL }, function()
    ExecuteInGameThread(function()
        local ok, err = pcall(snapAndDiff)
        if not ok then log("snapshot failed: %s", tostring(err)) end
    end)
end)

RegisterKeyBind(Key.F10, { ModifierKey.CONTROL }, function()
    ExecuteInGameThread(function()
        local ok, err = pcall(callGetters)
        if not ok then log("getters failed: %s", tostring(err)) end
    end)
end)

log("loaded: Ctrl+F7 dump, Ctrl+F8 live log + auto drift capture, Ctrl+F9 snapshot/diff, Ctrl+F10 camera getters")
