-- TXRCamProbe: dev-only UE4SS mod for the TXR chase camera project.
-- Not shipped. Finds out how the game builds its car camera and what changes while drifting.
--   Ctrl+F7 = dump pawn, controller, camera manager, every scene component on the car
--             (attach parent, world transform, which one the view is coming from) and the
--             car Blueprint's camera-related functions
--   Ctrl+F8 = toggle the live log (4x/s): speed, car yaw, camera yaw, gap, slip, drift_started.
--             While it runs, drifts are captured automatically: a grip baseline is kept every
--             second, and 0.5 s after drift_started turns on, the probe diffs against it.
--             View changes (view button, right-stick look) are captured the same way: the log
--             shows the view state and right stick, and diffs against the last stable view.
--   Ctrl+F9 = manual snapshot/diff, as before
--   Ctrl+F10 = call the car's camera getters (per view type for GetCameraPos/Pitch/ViewAngle)
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

local function outStr(v)
    if type(v) == "number" then return string.format("%.4g", v) end
    if type(v) == "userdata" then
        local ok, s = pcall(function()
            if v.X ~= nil then return vecStr(v) end
            if v.Yaw ~= nil then return rotStr(v) end
        end)
        if ok and s then return s end
    end
    return tostring(v)
end

local function callAndPrint(label, call)
    local out = {}
    local ok, ret = pcall(call, out)
    if not ok then
        log("    %s call failed: %s", label, tostring(ret))
        return
    end
    local parts = {}
    if ret ~= nil then table.insert(parts, "return=" .. outStr(ret)) end
    for k, v in pairs(out) do table.insert(parts, tostring(k) .. "=" .. outStr(v)) end
    log("    %s %s", label, #parts > 0 and table.concat(parts, "  ") or "(nothing returned)")
end

-- First input parameter's name, or nil when the function takes no inputs.
local function firstInput(fn)
    local name
    fn:ForEachProperty(function(p)
        if name then return end
        local isOut = false
        pcall(function() isOut = p:HasAnyPropertyFlags(0x100 | 0x400) end)
        if not isOut then name = p:GetFName():ToString() end
    end)
    return name
end

-- Calls the car's camera getters and prints what they return. Getters that take a view type
-- (GetCameraPos/Pitch/ViewAngle(in_type)) are called once per type 0..5.
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
                local input = firstInput(fn)
                if input == nil or input:match("^Temp_") or input:match("^CallFunc_") or input:match("^K2Node_") then
                    callAndPrint("", function(out) return pawn[n](pawn, out) end)
                elseif input == "in_type" then
                    for t = 0, 5 do
                        callAndPrint("type " .. t .. ":", function(out) return pawn[n](pawn, t, out) end)
                    end
                else
                    log("    (skipped: takes %s)", input)
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
    step("view mappings", dumpViewMappings)
    step("gk input", dumpGkInput)
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
local lastView = nil
local stableTicks = 0
local viewBaseline = nil
local viewCaptureAt = nil
local pendingViewDiff = nil

-- Compact description of the current camera view: the car's view variables plus the
-- active camera component(s).
function viewSignature(pawn)
    local parts = {}
    for _, n in ipairs({ "camera_type", "sub_camera_type", "view_type", "is_view_change" }) do
        local ok, v = pcall(function() return pawn[n] end)
        if ok and v ~= nil then table.insert(parts, n .. "=" .. tostring(v)) end
    end
    local active = {}
    for _, c in ipairs(componentsOf(pawn)) do
        if isA(c, "CameraComponent") then
            local ok, on = pcall(function() return c:IsActive() end)
            if ok and on then table.insert(active, short(c)) end
        end
    end
    table.insert(parts, "active=" .. table.concat(active, "+"))
    return table.concat(parts, " ")
end

-- Right stick through the player controller's input state; nil if it can't be read.
-- (Run 5: always 0 in TXR, which uses Enhanced Input. See readInputActions below.)
function readRightStick(pc)
    local function axis(key)
        local ok, v = pcall(function() return pc:GetInputAnalogKeyState({ KeyName = FName(key) }) end)
        if ok and type(v) == "number" then return v end
        return nil
    end
    return axis("Gamepad_RightX"), axis("Gamepad_RightY")
end

-- Enhanced Input ------------------------------------------------------------
-- Reads every loaded InputAction through UEnhancedInputLibrary::GetBoundActionValue on the
-- pawn and controller, and returns "IA_Name=(x, y)" for the ones that aren't zero.

local inputLib = nil
local inputErrLogged = false

local function inputActions()
    local out = {}
    for _, a in ipairs(FindAllOf("InputAction") or {}) do
        if valid(a) and not a:GetFullName():find("Default__", 1, true) then table.insert(out, a) end
    end
    return out
end

local function actionValue(actor, action)
    if inputLib == nil then
        inputLib = StaticFindObject("/Script/EnhancedInput.Default__EnhancedInputLibrary")
    end
    local value = inputLib:GetBoundActionValue(actor, action)
    local v2 = inputLib:Conv_InputActionValueToAxis2D(value)
    return v2.X, v2.Y
end

local cachedActions = nil
-- Run 6: GetBoundActionValue read all zeros (nothing is bound with BindActionValue), so this
-- asks the controller's EnhancedPlayerInput for the live value of the view/look actions instead.
local function isViewAction(a)
    local n = short(a)
    return n:find("View", 1, true) or n:find("Look", 1, true)
end

function readInputActions(pc)
    local parts = {}
    inputLib = inputLib or StaticFindObject("/Script/EnhancedInput.Default__EnhancedInputLibrary")
    local pi = pc.PlayerInput
    if not valid(pi) then return "no PlayerInput" end
    cachedActions = cachedActions or inputActions()
    for _, a in ipairs(cachedActions) do
        if isViewAction(a) then
            local ok, x, y = pcall(function()
                local v2 = inputLib:Conv_InputActionValueToAxis2D(pi:GetActionValue(a))
                return v2.X, v2.Y
            end)
            if not ok then
                if not inputErrLogged then
                    log("PlayerInput:GetActionValue failed: %s", tostring(x))
                    inputErrLogged = true
                end
            elseif type(x) == "number" and (math.abs(x) > 0.01 or math.abs(y or 0) > 0.01) then
                table.insert(parts, string.format("%s=(%.2f, %.2f)", short(a), x, y or 0))
            end
        end
    end
    return table.concat(parts, " ")
end

-- Genki's own controller layer (UGkInputPlatform / UGkInputPlatformInternal, from the exe's
-- strings). Run 7 showed no gamepad mappings in any IMC, so the stick probably goes through here.
function dumpGkInput()
    log("---- Gk input platform ----")
    for _, cname in ipairs({ "GkInputPlatform", "GkInputPlatformInternal", "GkPlatform", "GkPlatformInternal" }) do
        local objs = FindAllOf(cname) or {}
        log("  %s: %d instance(s)", cname, #objs)
        for i, o in ipairs(objs) do
            if i > 2 then break end
            log("  -- %s (%s)", o:GetFullName(), classChain(o))
            dumpProps(o)
            local cls = o:GetClass()
            while valid(cls) do
                local cn = cls:GetFName():ToString()
                if cn == "Object" or cn == "Subsystem" or cn == "GameInstanceSubsystem" then break end
                dumpFunctions(cls)
                cls = cls:GetSuperStruct()
            end
        end
    end
end

-- Key-state checks for the live log: the engine's virtual right-stick keys and analog axes.
-- W / SpaceBar / Up are keyboard controls: if those register but the gamepad keys don't, Genki's
-- input layer swallows the gamepad before PlayerInput; if nothing registers, it's the Lua FKey.
local KEY_CHECKS = { "Gamepad_RightX", "Gamepad_RightY", "Gamepad_RightStick_Left", "Gamepad_RightStick_Right",
                     "Gamepad_RightStick_Up", "Gamepad_RightStick_Down", "Gamepad_FaceButton_Bottom",
                     "Gamepad_LeftX", "Gamepad_RightTriggerAxis", "W", "SpaceBar", "Up" }
function keyStatesLine(pc)
    local parts = {}
    for _, k in ipairs(KEY_CHECKS) do
        local key = { KeyName = FName(k) }
        local okA, a = pcall(function() return pc:GetInputAnalogKeyState(key) end)
        local okD, d = pcall(function() return pc:IsInputKeyDown(key) end)
        local short = k:gsub("Gamepad_", ""):gsub("RightStick_", "RS_")
        if (okA and type(a) == "number" and math.abs(a) > 0.01) or (okD and d == true) then
            table.insert(parts, string.format("%s=%s/%s", short, okA and f1(a) or "err", okD and tostring(d) or "err"))
        end
    end
    local okV, v = pcall(function() return pc:GetInputVectorKeyState({ KeyName = FName("Gamepad_Right2D") }) end)
    if okV and v and type(v.X) == "number" and (math.abs(v.X) > 0.01 or math.abs(v.Y) > 0.01) then
        table.insert(parts, string.format("Right2D=(%.2f, %.2f)", v.X, v.Y))
    end
    return table.concat(parts, " ")
end

-- Array elements can come back wrapped (RemoteUnrealParam); unwrap when they have :get().
function unwrap(x)
    if type(x) == "userdata" then
        local ok, inner = pcall(function() return x:get() end)
        if ok and inner ~= nil then return inner end
    end
    return x
end

local function objList(arr)
    local out = {}
    local okAll, errAll = pcall(function()
        local n = arr:GetArrayNum()
        for i = 1, n do
            local o = unwrap(arr[i])
            if valid(o) then
                local s = o:GetClass():GetFName():ToString()
                for _, p in ipairs({ "ActuationThreshold", "bX", "bY", "bZ", "Order", "LowerThreshold", "UpperThreshold", "Type" }) do
                    local okp, v = pcall(function() return o[p] end)
                    if okp and v ~= nil and type(v) ~= "userdata" then
                        if type(v) == "number" then v = string.format("%.3g", v) end
                        s = s .. " " .. p .. "=" .. tostring(v)
                    end
                end
                table.insert(out, s)
            end
        end
    end)
    if not okAll then table.insert(out, "<error: " .. tostring(errAll) .. ">") end
    return table.concat(out, "; ")
end

-- Prints every mapping of a view/look action in every loaded InputMappingContext:
-- which key drives it, with what modifiers (negate, swizzle, dead zone) and triggers (thresholds).
function dumpViewMappings()
    log("---- view/look mappings ----")
    for _, a in ipairs(inputActions()) do
        if isViewAction(a) then
            log("  %s triggers: %s  modifiers: %s", short(a), objList(a.Triggers), objList(a.Modifiers))
        end
    end
    for _, ctx in ipairs(FindAllOf("InputMappingContext") or {}) do
        if valid(ctx) and not ctx:GetFullName():find("Default__", 1, true) then
            local okN, n = pcall(function() return ctx.Mappings:GetArrayNum() end)
            log("  context %s: %s mappings", ctx:GetFullName(), okN and tostring(n) or ("<error: " .. tostring(n) .. ">"))
            if okN then
                for i = 1, n do
                    local ok, err = pcall(function()
                        local m = unwrap(ctx.Mappings[i])
                        local action = m.Action
                        local aname = valid(action) and short(action) or "None"
                        if aname == "None" or isViewAction(action) then
                            log("    [%d] %s <- %s  triggers: %s  modifiers: %s", i, aname,
                                m.Key.KeyName:ToString(), objList(m.Triggers), objList(m.Modifiers))
                        end
                    end)
                    if not ok then log("    [%d] <error: %s>", i, tostring(err)) end
                end
            end
        end
    end
end

-- Lists loaded InputActions and the Enhanced Input event functions on the controller and car
-- Blueprints (InpActEvt_*), which are what fires when an action triggers.
function dumpInput(pc)
    log("---- InputActions ----")
    for _, a in ipairs(inputActions()) do
        local vt = "?"
        pcall(function() vt = tostring(a.ValueType) end)
        log("  %s  ValueType=%s", a:GetFullName(), vt)
    end
    for _, actor in ipairs({ pc, pc.Pawn }) do
        if valid(actor) then
            local cls = actor:GetClass()
            while valid(cls) and cls:GetFName():ToString():match("_C$") do
                cls:ForEachFunction(function(fn)
                    local n = fn:GetFName():ToString()
                    local ln = n:lower()
                    if n:find("InpActEvt", 1, true) or n:find("InpAxis", 1, true)
                        or ln:find("look", 1, true) or ln:find("stick", 1, true) or ln:find("subcamera", 1, true)
                        or ln:find("sub_camera", 1, true) or ln:find("input", 1, true) then
                        log("  %s:%s", cls:GetFName():ToString(), signature(fn))
                    end
                end)
                cls = cls:GetSuperStruct()
            end
        end
    end
end

-- Hooks every InpActEvt_* function on the controller and car Blueprints and logs which ones fire
-- (at most twice a second each), with whatever their first parameter holds.
local inputHooks = {}
-- Latest value per view event, e.g. viewEvents["ViewLeft7"] = { value, at, count }.
viewEvents = {}

-- "ViewLeft7=0.12/5 (0.1s)": last value, how many times it fired since the last line, age.
function viewEventsLine()
    local parts, now = {}, os.clock()
    local keys = {}
    for k in pairs(viewEvents) do table.insert(keys, k) end
    table.sort(keys)
    for _, k in ipairs(keys) do
        local e = viewEvents[k]
        if now - e.at < 1.0 then
            table.insert(parts, string.format("%s=%.2f/%d (%.2fs)", k, e.value, e.count, now - e.at))
        end
        e.count = 0
    end
    return table.concat(parts, "  ")
end
function hookInputEvents(pc)
    local count = 0
    inputLib = inputLib or StaticFindObject("/Script/EnhancedInput.Default__EnhancedInputLibrary")
    for _, actor in ipairs({ pc, pc.Pawn }) do
        if valid(actor) then
            local cls = actor:GetClass()
            while valid(cls) and cls:GetFName():ToString():match("_C$") do
                local classPath = cls:GetFullName():match("%s(.+)$")
                cls:ForEachFunction(function(fn)
                    local n = fn:GetFName():ToString()
                    if n:find("InpActEvt", 1, true) and n:find("View", 1, true) and not inputHooks[classPath .. ":" .. n] then
                        local path = classPath .. ":" .. n
                        -- "IA_NIG_ViewLeft_K2Node_EnhancedInputActionEvent_7" -> "ViewLeft7"
                        local tag = (n:match("IA_NIG_(%a+)_") or n) .. (n:match("_(%d+)$") or "")
                        local ok = pcall(RegisterHook, path, function(ctx, p1)
                            local val = 0
                            pcall(function()
                                val = inputLib:Conv_InputActionValueToAxis2D(p1:get()).X
                            end)
                            local e = viewEvents[tag] or { count = 0 }
                            e.value, e.at, e.count = val, os.clock(), e.count + 1
                            viewEvents[tag] = e
                        end)
                        if ok then
                            inputHooks[path] = true
                            count = count + 1
                        end
                    end
                end)
                cls = cls:GetSuperStruct()
            end
        end
    end
    log("hooked %d input event(s)", count)
end

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
    local view = viewSignature(pawn)
    local rx, ry = readRightStick(pc)
    log("%6.1f km/h  car %7.1f  cam %7.1f  cam-car %6.1f  slip %6.1f  fov %5.1f  RS %s,%s  %s  %s",
        kmh, carYaw, camYaw, wrap(camYaw - carYaw), kmh > 5 and wrap(velYaw - carYaw) or 0,
        cm:GetFOVAngle(), f1(rx), f1(ry), view, drifting and "DRIFT" or "")
    local events = viewEventsLine()
    if events ~= "" then log("    view events: %s", events) end
    local keys = keyStatesLine(pc)
    if keys ~= "" then log("    keys: %s", keys) end

    -- View changes (view button, right-stick look): diff against the last stable baseline.
    if lastView ~= nil and view ~= lastView then
        log("view changed: [%s] -> [%s]", lastView, view)
        if viewBaseline then
            local before = viewBaseline
            viewCaptureAt = ticks + 1
            pendingViewDiff = { before = before, title = "AUTO: view [" .. lastView .. "] -> [" .. view .. "]" }
        end
        stableTicks = 0
    else
        stableTicks = stableTicks + 1
    end
    lastView = view
    if viewCaptureAt and ticks >= viewCaptureAt and pendingViewDiff then
        printDiff(pendingViewDiff.title, pendingViewDiff.before, snapshot())
        viewCaptureAt, pendingViewDiff = nil, nil
    end
    -- Baseline for view diffs: refreshed every 0.5 s while the view has been stable for 0.5 s.
    if stableTicks >= 2 and not drifting and ticks % 2 == 0 then
        viewBaseline = snapshot()
    end

    -- Keep a fresh grip baseline (once a second, at speed, not drifting).
    if not drifting and kmh > 40 and ticks - lastBaselineAt >= 4 then
        gripBaseline = viewBaseline or snapshot()
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
    if watching then
        ExecuteInGameThread(function()
            local pc = getPC()
            if pc then
                local ok, err = pcall(hookInputEvents, pc)
                if not ok then log("input hooks failed: %s", tostring(err)) end
            end
        end)
        startWatch()
    end
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
