--[[
    VehicleSpeedMod for Out of Ore (anti-stack rewrite)

    Fixes "multiple presets stacking" when cycling:
      - Only ONE background LoopAsync (shared flag)
      - Keybind debounce (ignore rapid repeat)
      - Preset change = restore stock originals FIRST, then apply new mult
      - Gear snaps captured once; never re-snapshot modified gears
      - Interval apply only reasserts current preset (idempotent)
]]

local UEHelpers = require("UEHelpers")
require("config")

local Config = VehicleSpeedConfig or {}
local GlobalAr = nil

-- Per-vehicle cache: originals (stock numbers) + gear snaps (stock gear fields)
local OriginalCache = {}

-- Track what we last applied so we don't thrash / double-feel
local LastApplied = {
    preset = nil,
    generation = 0,
}

local PresetGeneration = 0
local LastCycleMs = 0
local CYCLE_DEBOUNCE_MS = 400
local Applying = false -- re-entrancy guard

local PropMap = {
    max_speed_limit = "MaxSpeedLimit",
    dynamic_max_torque = "DynamicMaxTorque",
    target_acceleration = "TargetAcceleration",
    vehicle_max_angular_velocity = "VehicleMaxAngularVelocity",
    idle_max_rpm = "IdleMaxRPM",
    target_speed = "TargetSpeed",
    top_speed_forward = "TopSpeedF",
    top_speed_reverse = "TopSpeedR",
    high_gear_speed = "HighGearSpeed",
    low_gear_speed = "LowGearSpeed",
    gear_ratio_forward = "GearRatioF",
    gear_ratio_reverse = "GearRatioR",
    drivetrain_gear_modifier = "DrivetrainGearModifier",
    max_acceleration = "MaxAccs",
    engine_power = "EnginePower",
    drive_torque_multiplier = "DriveTorqMultiplier",
    brake_force = "BrakeForce",
}

local DefaultFloors = {
    MaxSpeedLimit = 80,
    DynamicMaxTorque = 3500,
    TargetAcceleration = 8,
    TargetSpeed = 80,
    VehicleMaxAngularVelocity = 12,
    IdleMaxRPM = 2600,
    TopSpeedF = 45,
    TopSpeedR = 22,
    HighGearSpeed = 45,
    LowGearSpeed = 22,
    EnginePower = 120,
    DriveTorqMultiplier = 1,
    MaxAccs = 6,
}

local GEAR_FIELDS = {
    "EndSpeed", "StartSpeed", "UpShift", "DownShift",
    "MaxTorque", "MinTorque", "HighRPM", "LowRPM",
}

local function Log(msg)
    local line = "[VehicleSpeedMod] " .. tostring(msg)
    print(line .. "\n")
    if GlobalAr and type(GlobalAr) == "userdata" then
        pcall(function() GlobalAr:Log(line) end)
    end
end

local function NowMs()
    -- os.clock is seconds of CPU time; fine for debounce
    return math.floor(os.clock() * 1000)
end

local function WithAr(Ar, fn)
    GlobalAr = Ar
    local ok, err = pcall(fn)
    GlobalAr = nil
    if not ok then Log("Error: " .. tostring(err)) end
    return true
end

local function SharedGet(key)
    local ok, v = pcall(function()
        if ModRef and ModRef.GetSharedVariable then
            return ModRef:GetSharedVariable(key)
        end
        return nil
    end)
    if ok then return v end
    return nil
end

local function SharedSet(key, value)
    pcall(function()
        if ModRef and ModRef.SetSharedVariable then
            ModRef:SetSharedVariable(key, value)
        end
    end)
end

local function ReloadConfig()
    package.loaded["config"] = nil
    local ok, err = pcall(function()
        require("config")
        Config = VehicleSpeedConfig or {}
    end)
    if not ok then
        Log("Config reload failed: " .. tostring(err))
        return false
    end
    PresetGeneration = PresetGeneration + 1
    LastApplied.preset = nil
    Log("Config reloaded enabled=" .. tostring(Config.enabled) ..
        " preset=" .. tostring(Config.active_preset) ..
        " scale_gears=" .. tostring(Config.scale_gears))
    return true
end

local function GetPresetOrder()
    if type(Config.presets) ~= "table" then return {} end
    local preferred = { "vanilla", "sport", "insane", "insane+" }
    local order, seen = {}, {}
    for _, n in ipairs(preferred) do
        if Config.presets[n] then table.insert(order, n); seen[n] = true end
    end
    local rest = {}
    for n, _ in pairs(Config.presets) do
        if not seen[n] then table.insert(rest, n) end
    end
    table.sort(rest)
    for _, n in ipairs(rest) do table.insert(order, n) end
    return order
end

local function GetFeel()
    local name = Config.active_preset or "sport"
    local p = (Config.presets and Config.presets[name]) or {}
    local speed = tonumber(p.top_speed_forward) or tonumber(p.max_speed_limit) or 1.0
    local power = tonumber(p.drive_torque_multiplier) or tonumber(p.engine_power) or speed
    local accel = tonumber(p.max_acceleration) or power
    if speed < 0.1 then speed = 0.1 end
    if power < 0.1 then power = 0.1 end
    if accel < 0.1 then accel = 0.1 end
    -- Allow extreme presets like insane+ (100x); still clamp absurd typos
    local maxMult = 200
    if speed > maxMult then speed = maxMult end
    if power > maxMult then power = maxMult end
    if accel > maxMult then accel = maxMult end
    return { name = name, speed = speed, power = power, accel = accel, raw = p }
end

local function GetMults(classShort)
    local feel = GetFeel()
    local p = feel.raw
    local mult = {}
    local maxMult = 200
    for key, _ in pairs(PropMap) do
        mult[key] = tonumber(p[key]) or 1.0
        if mult[key] > maxMult then mult[key] = maxMult end
        if mult[key] < 0.1 then mult[key] = 0.1 end
    end
    if not p.max_speed_limit then mult.max_speed_limit = feel.speed end
    if not p.target_speed then mult.target_speed = feel.speed end
    if not p.dynamic_max_torque then mult.dynamic_max_torque = feel.power end
    if not p.target_acceleration then mult.target_acceleration = feel.accel end
    if not p.top_speed_forward then mult.top_speed_forward = feel.speed end
    if not p.high_gear_speed then mult.high_gear_speed = feel.speed end
    if not p.engine_power then mult.engine_power = feel.power end
    if not p.drive_torque_multiplier then mult.drive_torque_multiplier = feel.power end
    if not p.max_acceleration then mult.max_acceleration = feel.accel end

    local ov = Config.class_overrides
    if type(ov) == "table" and classShort and ov[classShort] then
        for k, v in pairs(ov[classShort]) do
            if PropMap[k] then
                mult[k] = tonumber(v) or mult[k]
            end
        end
    end
    return mult, feel
end

local function GetClassShort(obj)
    local ok, s = pcall(function()
        local c = obj:GetClass()
        if not c or not c:IsValid() then return nil end
        local full = c:GetFullName() or ""
        return full:match("%.([^%.%s]+)$") or full
    end)
    return ok and s or nil
end

local function GetAddr(obj)
    local ok, a = pcall(function() return obj:GetAddress() end)
    return (ok and a) and tostring(a) or nil
end

local function ReadNum(obj, name)
    local ok, v = pcall(function() return obj[name] end)
    if ok and type(v) == "number" then return v end
    return nil
end

local function WriteNum(obj, name, value)
    return pcall(function() obj[name] = value end)
end

local function Floor(prop, original)
    local floors = Config.absolute_floors or DefaultFloors
    local f = floors[prop]
    if original == nil then return nil end
    if f and (original == 0 or math.abs(original) < 1e-4) then
        return f
    end
    return original
end

local function EnsureCache(obj)
    local addr = GetAddr(obj)
    if not addr then return nil, nil end
    if not OriginalCache[addr] then
        OriginalCache[addr] = {
            originals = {},
            gears = {},
            classShort = GetClassShort(obj),
            lastPreset = nil,
        }
    end
    return OriginalCache[addr], addr
end

--- Capture stock prop once. Never overwrite an existing original.
local function CachePropOnce(obj, prop)
    local cache = EnsureCache(obj)
    if not cache then return end
    if cache.originals[prop] ~= nil then return end
    local v = ReadNum(obj, prop)
    if v ~= nil then
        cache.originals[prop] = v
    end
end

--- Capture stock gear tables once (numeric copies only).
local function CacheGearsOnce(obj, addr)
    local cache = OriginalCache[addr]
    if not cache then return end

    for _, arrayName in ipairs({ "Gears", "Gears_Reverse" }) do
        if cache.gears[arrayName] then
            goto continue
        end
        pcall(function()
            local arr = obj[arrayName]
            if arr == nil or not arr.GetArrayNum then return end
            local num = arr:GetArrayNum()
            if num <= 0 then return end

            cache.gears[arrayName] = {}
            for i = 1, num do
                local g = arr[i]
                if g then
                    local snap = {}
                    for _, f in ipairs(GEAR_FIELDS) do
                        local v = nil
                        pcall(function() v = g[f] end)
                        if type(v) == "number" then
                            snap[f] = v
                        end
                    end
                    cache.gears[arrayName][i] = snap
                end
            end
            if Config.log_applies then
                Log(string.format("  stock-cached %s gears=%d", arrayName, num))
            end
        end)
        ::continue::
    end
end

--- Restore stock props + gears (no multipliers).
local function RestoreVehicle(obj)
    local cache, addr = EnsureCache(obj)
    if not cache or not addr then return 0 end
    local n = 0

    for prop, orig in pairs(cache.originals) do
        if WriteNum(obj, prop, orig) then n = n + 1 end
    end

    for arrayName, gears in pairs(cache.gears) do
        pcall(function()
            local arr = obj[arrayName]
            if not arr then return end
            for i, snap in pairs(gears) do
                local g = arr[i]
                if g and snap then
                    for f, val in pairs(snap) do
                        pcall(function() g[f] = val end)
                        n = n + 1
                    end
                end
            end
        end)
    end

    cache.lastPreset = "vanilla_base"
    return n
end

local function ApplyPropsFromOriginals(obj, mult)
    local n = 0
    local cache = EnsureCache(obj)
    if not cache then return 0 end

    for key, prop in pairs(PropMap) do
        CachePropOnce(obj, prop)
        local original = cache.originals[prop]
        if original ~= nil then
            local base = Floor(prop, original)
            local m = tonumber(mult[key]) or 1.0
            local target = base * m
            if WriteNum(obj, prop, target) then
                n = n + 1
                if Config.log_applies then
                    Log(string.format("  %s: stock=%.3f -> %.3f (x%.2f)", prop, original, target, m))
                end
            end
        end
    end
    return n
end

local function ApplyGearsFromOriginals(obj, feel, addr)
    if Config.scale_gears ~= true then return 0 end
    local cache = OriginalCache[addr]
    if not cache then return 0 end

    CacheGearsOnce(obj, addr)
    local total = 0

    for _, arrayName in ipairs({ "Gears", "Gears_Reverse" }) do
        local snaps = cache.gears[arrayName]
        if snaps then
            pcall(function()
                local arr = obj[arrayName]
                if not arr then return end
                for i, snap in pairs(snaps) do
                    local g = arr[i]
                    if g and snap then
                        local function set(field, m)
                            if snap[field] ~= nil and m then
                                pcall(function() g[field] = snap[field] * m end)
                                total = total + 1
                            end
                        end
                        set("EndSpeed", feel.speed)
                        set("StartSpeed", feel.speed)
                        set("UpShift", feel.speed)
                        set("DownShift", feel.speed)
                        set("MaxTorque", feel.power)
                        set("MinTorque", feel.power)
                        -- do NOT scale HighRPM/LowRPM (was making shift feel stack weirdly)
                    end
                end
            end)
        end
    end
    return total
end

local function IsVehicleClassName(short)
    if not short then return false end
    if short:find("AVS_SuperVehicle", 1, true) then return true end
    if short == "AVS_Base_C" or short:find("AVS_Base_C", 1, true) then return true end
    if short == "AVS_Vehicle_C" then return true end
    if short == "BP_VehicleBase_C" then return true end
    if short:match("^V_") and short:find("Base") then return true end
    return false
end

local function LooksLikeVehicle(obj)
    if not obj or not obj:IsValid() then return false end
    local short = GetClassShort(obj)
    if IsVehicleClassName(short) then return true end
    if short and short:find("Vehicle", 1, true)
        and not short:find("Widget")
        and not short:find("^W_")
        and not short:find("BFL_") then
        if ReadNum(obj, "MaxSpeedLimit") or ReadNum(obj, "TopSpeedF") or ReadNum(obj, "DynamicMaxTorque") then
            return true
        end
    end
    return false
end

local function CollectVehicles()
    local list, seen = {}, {}

    local function add(obj)
        if not obj or type(obj) ~= "userdata" then return end
        local okValid = false
        pcall(function() okValid = obj:IsValid() end)
        if not okValid then return end
        if not LooksLikeVehicle(obj) then return end
        local addr = GetAddr(obj)
        if not addr or seen[addr] then return end
        seen[addr] = true
        table.insert(list, obj)
    end

    local names = {
        "AVS_SuperVehicleBase_C",
        "AVS_Base_C",
        "AVS_Vehicle_C",
        "BP_VehicleBase_C",
        "V_TruckBase_C",
        "V_SemiTruckBase_C",
        "V_PaverBase_C",
    }

    for _, name in ipairs(names) do
        pcall(function()
            local found = FindAllOf(name)
            if found then
                for _, o in ipairs(found) do add(o) end
            end
        end)
    end

    pcall(function()
        local pc = UEHelpers.GetPlayerController()
        if pc and pc:IsValid() then
            pcall(function() add(pc.NewVehiclePawn) end)
            pcall(function() add(pc.Pawn) end)
        end
    end)

    if #list == 0 then
        pcall(function()
            ForEachUObject(function(obj)
                local short = GetClassShort(obj)
                if IsVehicleClassName(short) then add(obj) end
            end)
        end)
    end

    return list
end

--- Core apply: ALWAYS stock → mult (restore then apply when preset changes)
local function ApplyToVehicle(obj, forceRestore)
    local short = GetClassShort(obj) or "?"
    local mult, feel = GetMults(short)
    local cache, addr = EnsureCache(obj)
    if not addr then return 0, 0 end

    -- Capture stock first time we see this vehicle (before writing)
    for _, prop in pairs(PropMap) do
        CachePropOnce(obj, prop)
    end
    CacheGearsOnce(obj, addr)

    local needRestore = forceRestore
        or cache.lastPreset == nil
        or cache.lastPreset ~= feel.name

    if needRestore then
        RestoreVehicle(obj)
    end

    if Config.log_applies then
        Log(string.format("Apply -> %s preset=%s restore=%s", short, feel.name, tostring(needRestore)))
    end

    local props = ApplyPropsFromOriginals(obj, mult)
    local gears = ApplyGearsFromOriginals(obj, feel, addr)
    cache.lastPreset = feel.name
    return props, gears
end

local function ApplyAll(forceRestore)
    if Config.enabled == false then
        return 0, 0, 0
    end
    if Applying then
        return 0, 0, 0
    end
    Applying = true

    local nv, tp, tg = 0, 0, 0
    local ok, err = pcall(function()
        local vehicles = CollectVehicles()
        nv = #vehicles
        local feel = GetFeel()
        for _, v in ipairs(vehicles) do
            local p, g = ApplyToVehicle(v, forceRestore == true)
            tp = tp + p
            tg = tg + g
        end
        LastApplied.preset = feel.name
        LastApplied.generation = PresetGeneration
    end)

    Applying = false
    if not ok then
        Log("ApplyAll error: " .. tostring(err))
    end
    return nv, tp, tg
end

local function ResetAll()
    local n = 0
    for _, v in ipairs(CollectVehicles()) do
        n = n + RestoreVehicle(v)
        local cache = EnsureCache(v)
        if cache then cache.lastPreset = nil end
    end
    LastApplied.preset = nil
    return n
end

local function PrintStatus()
    local feel = GetFeel()
    Log("=== VehicleSpeedMod ===")
    Log(string.format("enabled=%s active_preset=%s speed_x=%.2f power_x=%.2f",
        tostring(Config.enabled), feel.name, feel.speed, feel.power))
    Log(string.format("last_applied_preset=%s scale_gears=%s",
        tostring(LastApplied.preset), tostring(Config.scale_gears)))

    local vehicles = CollectVehicles()
    Log("vehicles found: " .. tostring(#vehicles))
    if #vehicles == 0 then
        Log("Enter/spawn a machine, then vehiclespeed_apply")
        return
    end

    for i, v in ipairs(vehicles) do
        if i > 6 then
            Log("... +" .. tostring(#vehicles - 6) .. " more")
            break
        end
        local short = GetClassShort(v) or "?"
        local addr = GetAddr(v)
        local cache = addr and OriginalCache[addr]
        Log(string.format("[%d] %s last=%s", i, short, tostring(cache and cache.lastPreset)))
        for _, prop in ipairs({ "MaxSpeedLimit", "DynamicMaxTorque", "TopSpeedF" }) do
            local val = ReadNum(v, prop)
            if val ~= nil then
                local orig = cache and cache.originals[prop]
                if orig then
                    Log(string.format("    %s=%.3f (stock %.3f)", prop, val, orig))
                else
                    Log(string.format("    %s=%.3f", prop, val))
                end
            end
        end
        pcall(function()
            local arr = v.Gears
            if arr and arr.GetArrayNum and arr:GetArrayNum() > 0 then
                local g = arr[1]
                local es, mt
                pcall(function() es = g.EndSpeed end)
                pcall(function() mt = g.MaxTorque end)
                local stockEs = cache and cache.gears and cache.gears.Gears and cache.gears.Gears[1] and cache.gears.Gears[1].EndSpeed
                Log(string.format("    Gears[1] EndSpeed=%s (stock %s) MaxTorque=%s",
                    tostring(es), tostring(stockEs), tostring(mt)))
            end
        end)
    end
end

local function SetPreset(name)
    if not Config.presets or not Config.presets[name] then
        Log("Unknown preset. Available: " .. table.concat(GetPresetOrder(), ", "))
        return
    end

    -- Same preset already applied? Still force restore+apply for consistency
    Config.active_preset = name
    if VehicleSpeedConfig then VehicleSpeedConfig.active_preset = name end
    PresetGeneration = PresetGeneration + 1

    -- CRITICAL: always restore stock first when switching presets
    local nv, np, ng = ApplyAll(true)
    Log(string.format("preset=%s vehicles=%d props=%d gears=%d (restored stock then applied once)",
        name, nv, np, ng))
    if nv == 0 then
        Log("TIP: get in a vehicle / load a world first, then vehiclespeed_apply")
    end
end

local function CyclePreset(dir)
    local now = NowMs()
    if (now - LastCycleMs) < CYCLE_DEBOUNCE_MS then
        return -- ignore double keybind / multi-handler fire
    end
    LastCycleMs = now

    local order = GetPresetOrder()
    if #order == 0 then return end
    local idx = 1
    for i, n in ipairs(order) do
        if n == (Config.active_preset or "") then idx = i break end
    end
    idx = idx + (dir or 1)
    if idx < 1 then idx = #order end
    if idx > #order then idx = 1 end
    SetPreset(order[idx])
end

RegisterConsoleCommandHandler("vehiclespeed_reload", function(_, _, Ar)
    return WithAr(Ar, function()
        if ReloadConfig() then
            local nv, np, ng = ApplyAll(true)
            Log(string.format("Applied vehicles=%d props=%d gears=%d", nv, np, ng))
        end
    end)
end)

RegisterConsoleCommandHandler("vehiclespeed_status", function(_, _, Ar)
    return WithAr(Ar, function() PrintStatus() end)
end)

RegisterConsoleCommandHandler("vehiclespeed_preset", function(_, Parameters, Ar)
    return WithAr(Ar, function() SetPreset(Parameters and Parameters[1]) end)
end)

RegisterConsoleCommandHandler("vehiclespeed_apply", function(_, _, Ar)
    return WithAr(Ar, function()
        local nv, np, ng = ApplyAll(true)
        Log(string.format("Applied vehicles=%d props=%d gears=%d", nv, np, ng))
    end)
end)

RegisterConsoleCommandHandler("vehiclespeed_reset", function(_, _, Ar)
    return WithAr(Ar, function()
        Log("Restored " .. tostring(ResetAll()) .. " stock fields (vanilla baseline)")
        LastApplied.preset = nil
    end)
end)

RegisterConsoleCommandHandler("vehiclespeed_enable", function(_, Parameters, Ar)
    return WithAr(Ar, function()
        local a = Parameters and Parameters[1]
        if a == "0" or a == "off" or a == "false" then
            Config.enabled = false
            if VehicleSpeedConfig then VehicleSpeedConfig.enabled = false end
            ResetAll()
            Log("Disabled + restored stock values")
        elseif a == "1" or a == "on" or a == "true" then
            Config.enabled = true
            if VehicleSpeedConfig then VehicleSpeedConfig.enabled = true end
            local nv, np, ng = ApplyAll(true)
            Log(string.format("Enabled vehicles=%d props=%d gears=%d", nv, np, ng))
        else
            Log("vehiclespeed_enable 0|1 (now " .. tostring(Config.enabled) .. ")")
        end
    end)
end)

RegisterConsoleCommandHandler("vehiclespeed_help", function(_, _, Ar)
    return WithAr(Ar, function()
        Log("vehiclespeed_status | apply | preset vanilla|sport|insane|insane+ | reload | enable 0|1 | reset")
        Log("Preset changes RESTORE stock first, then apply once (no stacking).")
        Log("insane+ = 100x — extreme; may break physics. Keys: Ctrl+Shift+Left/Right, Ctrl+Shift+V")
    end)
end)

-- Keybinds: only register once per process via shared flag
local function RegisterBindsOnce()
    if SharedGet("VehicleSpeedMod_Binds") == true then
        Log("Keybinds already registered (skipping duplicate)")
        return
    end
    local kb = Config.keybinds or {}
    if kb.next_preset ~= false then
        RegisterKeyBind(Key.RIGHT_ARROW, { ModifierKey.CONTROL, ModifierKey.SHIFT }, function()
            ExecuteInGameThread(function() CyclePreset(1) end)
        end)
    end
    if kb.prev_preset ~= false then
        RegisterKeyBind(Key.LEFT_ARROW, { ModifierKey.CONTROL, ModifierKey.SHIFT }, function()
            ExecuteInGameThread(function() CyclePreset(-1) end)
        end)
    end
    if kb.status ~= false then
        RegisterKeyBind(Key.V, { ModifierKey.CONTROL, ModifierKey.SHIFT }, function()
            ExecuteInGameThread(function() PrintStatus() end)
        end)
    end
    SharedSet("VehicleSpeedMod_Binds", true)
end

local function StartLoopOnce()
    if SharedGet("VehicleSpeedMod_Loop") == true then
        Log("Apply loop already running (skipping duplicate LoopAsync)")
        return
    end
    SharedSet("VehicleSpeedMod_Loop", true)

    local ms = math.floor((tonumber(Config.apply_interval_seconds) or 5) * 1000)
    if ms < 3000 then ms = 3000 end

    LoopAsync(ms, function()
        pcall(function()
            if Config.enabled == false then return end
            -- Soft reassert current preset only (no extra restore unless needed)
            ApplyAll(false)
        end)
        return false
    end)
    Log("Started single apply loop every " .. tostring(ms) .. "ms")
end

-- Map load: only one hook registration flag
if SharedGet("VehicleSpeedMod_MapHook") ~= true then
    SharedSet("VehicleSpeedMod_MapHook", true)
    RegisterLoadMapPostHook(function()
        ExecuteInGameThread(function()
            ExecuteWithDelay(3000, function()
                if Config.enabled == false then return end
                local nv, np, ng = ApplyAll(true)
                Log(string.format("Map load: vehicles=%d props=%d gears=%d", nv, np, ng))
            end)
        end)
    end)
end

if SharedGet("VehicleSpeedMod_NewObj") ~= true then
    SharedSet("VehicleSpeedMod_NewObj", true)
    pcall(function()
        NotifyOnNewObject("/Game/Vehicles/AVS_SuperVehicleBase.AVS_SuperVehicleBase_C", function(obj)
            ExecuteWithDelay(1500, function()
                if Config.enabled == false then return end
                if obj and obj:IsValid() then
                    -- New vehicle: capture stock then apply current preset once
                    local p, g = ApplyToVehicle(obj, true)
                    if Config.log_applies then
                        Log(string.format("New vehicle: props=%d gears=%d (%s)",
                            p, g, tostring(GetClassShort(obj))))
                    end
                end
            end)
        end)
    end)
end

RegisterBindsOnce()
StartLoopOnce()

Log(string.format("Loaded (anti-stack). enabled=%s preset=%s scale_gears=%s",
    tostring(Config.enabled), tostring(Config.active_preset), tostring(Config.scale_gears)))
Log("Cycling presets restores stock first, then applies one mult. Debounced keys.")

ExecuteInGameThread(function()
    ExecuteWithDelay(5000, function()
        if Config.enabled == false then return end
        local nv, np, ng = ApplyAll(true)
        Log(string.format("Initial: vehicles=%d props=%d gears=%d", nv, np, ng))
    end)
end)
