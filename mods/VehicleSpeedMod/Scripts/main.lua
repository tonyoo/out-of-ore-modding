--[[
    VehicleSpeedMod for Out of Ore

    AVS_SuperVehicleBase machines use gear tables (EndSpeed/MaxTorque).
    We:
      1) Find vehicles reliably (FindAllOf + ForEachUObject fallback)
      2) Set AVS props from ORIGINAL * multiplier (no stacking)
      3) Optionally scale gear structs once per vehicle/preset
]]

local UEHelpers = require("UEHelpers")
require("config")

local Config = VehicleSpeedConfig or {}
local GlobalAr = nil
local OriginalCache = {} -- [addr] = { originals={}, gears={}, classShort= }
local GearKey = {}       -- [addr..preset] = true after gear scale
local ApplyLoopStarted = false
local PresetGeneration = 0

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

local function Log(msg)
    local line = "[VehicleSpeedMod] " .. tostring(msg)
    print(line .. "\n")
    if GlobalAr and type(GlobalAr) == "userdata" then
        pcall(function() GlobalAr:Log(line) end)
    end
end

local function WithAr(Ar, fn)
    GlobalAr = Ar
    local ok, err = pcall(fn)
    GlobalAr = nil
    if not ok then Log("Error: " .. tostring(err)) end
    return true
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
    GearKey = {}
    Log("Config reloaded enabled=" .. tostring(Config.enabled) ..
        " preset=" .. tostring(Config.active_preset) ..
        " scale_gears=" .. tostring(Config.scale_gears))
    return true
end

local function GetPresetOrder()
    if type(Config.presets) ~= "table" then return {} end
    local preferred = { "vanilla", "sport", "insane" }
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
    return { name = name, speed = speed, power = power, accel = accel, raw = p }
end

local function GetMults(classShort)
    local feel = GetFeel()
    local p = feel.raw
    local mult = {}
    for key, _ in pairs(PropMap) do
        mult[key] = tonumber(p[key]) or 1.0
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
            if PropMap[k] then mult[k] = tonumber(v) or mult[k] end
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
        }
    end
    return OriginalCache[addr], addr
end

local function CacheProp(obj, prop)
    local cache = EnsureCache(obj)
    if not cache then return end
    if cache.originals[prop] == nil then
        local v = ReadNum(obj, prop)
        if v ~= nil then cache.originals[prop] = v end
    end
end

local function ApplyProps(obj, mult)
    local n = 0
    local cache = EnsureCache(obj)
    if not cache then return 0 end
    for key, prop in pairs(PropMap) do
        CacheProp(obj, prop)
        local original = cache.originals[prop]
        if original ~= nil then
            local base = Floor(prop, original)
            local m = tonumber(mult[key]) or 1.0
            local target = base * m
            if WriteNum(obj, prop, target) then
                n = n + 1
                if Config.log_applies then
                    Log(string.format("  %s: %.3f -> %.3f (x%.2f)", prop, original, target, m))
                end
            end
        end
    end
    return n
end

local function ScaleGearArray(obj, arrayName, feel, addr)
    local cache = OriginalCache[addr]
    if not cache then return 0 end
    local total = 0

    local ok = pcall(function()
        local arr = obj[arrayName]
        if arr == nil then return end

        local num = 0
        pcall(function()
            if arr.GetArrayNum then num = arr:GetArrayNum() end
        end)
        if num <= 0 then return end

        if not cache.gears[arrayName] then
            cache.gears[arrayName] = {}
            for i = 1, num do
                local g = arr[i]
                if g then
                    local snap = {}
                    for _, f in ipairs({
                        "EndSpeed", "StartSpeed", "UpShift", "DownShift",
                        "MaxTorque", "MinTorque", "HighRPM", "LowRPM"
                    }) do
                        local v = nil
                        pcall(function() v = g[f] end)
                        if type(v) == "number" then snap[f] = v end
                    end
                    cache.gears[arrayName][i] = snap
                end
            end
            if Config.log_applies then
                Log(string.format("  cached %s gears=%d", arrayName, num))
            end
        end

        for i = 1, num do
            local g = arr[i]
            local snap = cache.gears[arrayName][i]
            if g and snap then
                local function set(field, m)
                    if snap[field] ~= nil and m then
                        local nv = snap[field] * m
                        pcall(function() g[field] = nv end)
                        total = total + 1
                    end
                end
                set("EndSpeed", feel.speed)
                set("StartSpeed", feel.speed)
                set("UpShift", feel.speed)
                set("DownShift", feel.speed)
                set("MaxTorque", feel.power)
                set("MinTorque", feel.power)
            end
        end
    end)

    if not ok then return 0 end
    return total
end

local function ScaleGears(obj, feel, addr, force)
    if Config.scale_gears ~= true then return 0 end
    local gkey = tostring(addr) .. ":" .. tostring(feel.name) .. ":" .. tostring(PresetGeneration)
    if GearKey[gkey] and not force then return 0 end

    local n = 0
    n = n + ScaleGearArray(obj, "Gears", feel, addr)
    n = n + ScaleGearArray(obj, "Gears_Reverse", feel, addr)
    if n > 0 then GearKey[gkey] = true end
    return n
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
    -- Property probe only for vehicle-ish names
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
        "AVS_SuperVehicleBase",
        "AVS_Base_C",
        "AVS_Base",
        "AVS_Vehicle_C",
        "AVS_Vehicle",
        "BP_VehicleBase_C",
        "V_TruckBase_C",
        "V_SemiTruckBase_C",
        "V_PaverBase_C",
        "VehicleSystemBase",
    }

    for _, name in ipairs(names) do
        pcall(function()
            local found = FindAllOf(name)
            if found then
                for _, o in ipairs(found) do add(o) end
            end
        end)
        pcall(function()
            add(FindFirstOf(name))
        end)
    end

    -- Controller refs
    pcall(function()
        local pc = UEHelpers.GetPlayerController()
        if pc and pc:IsValid() then
            pcall(function() add(pc.NewVehiclePawn) end)
            pcall(function() add(pc.Pawn) end)
            pcall(function() add(pc.AcknowledgedPawn) end)
        end
    end)
    pcall(function() add(UEHelpers.GetPlayer()) end)

    -- Fallback: scan all UObjects for SuperVehicle classes (slower, reliable)
    if #list == 0 then
        pcall(function()
            ForEachUObject(function(obj)
                local short = GetClassShort(obj)
                if IsVehicleClassName(short) then
                    add(obj)
                end
            end)
        end)
    end

    return list
end

local function ApplyToVehicle(obj, forceGears)
    local short = GetClassShort(obj) or "?"
    local mult, feel = GetMults(short)
    local cache, addr = EnsureCache(obj)
    if not addr then return 0, 0 end

    if Config.log_applies then
        Log("Apply -> " .. short)
    end

    local props = ApplyProps(obj, mult)
    local gears = ScaleGears(obj, feel, addr, forceGears == true)
    return props, gears
end

local function ApplyAll(forceGears)
    if Config.enabled == false then
        Log("enabled=false (set enabled=true in config.lua)")
        return 0, 0, 0
    end
    local vehicles = CollectVehicles()
    local tp, tg = 0, 0
    for _, v in ipairs(vehicles) do
        local p, g = ApplyToVehicle(v, forceGears)
        tp = tp + p
        tg = tg + g
    end
    return #vehicles, tp, tg
end

local function ResetAll()
    local n = 0
    for _, v in ipairs(CollectVehicles()) do
        local addr = GetAddr(v)
        local cache = addr and OriginalCache[addr]
        if cache and cache.originals then
            for prop, orig in pairs(cache.originals) do
                if WriteNum(v, prop, orig) then n = n + 1 end
            end
        end
        if cache and cache.gears then
            for arrayName, gears in pairs(cache.gears) do
                pcall(function()
                    local arr = v[arrayName]
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
        end
    end
    GearKey = {}
    return n
end

local function PrintStatus()
    local feel = GetFeel()
    Log("=== VehicleSpeedMod ===")
    Log(string.format("enabled=%s preset=%s speed_x=%.2f power_x=%.2f scale_gears=%s",
        tostring(Config.enabled), feel.name, feel.speed, feel.power, tostring(Config.scale_gears)))

    local vehicles = CollectVehicles()
    Log("vehicles found: " .. tostring(#vehicles))

    if #vehicles == 0 then
        Log("No vehicles in memory. Enter/spawn a machine in the world, then run vehiclespeed_apply")
        return
    end

    for i, v in ipairs(vehicles) do
        if i > 8 then
            Log("... +" .. tostring(#vehicles - 8) .. " more")
            break
        end
        local short = GetClassShort(v) or "?"
        Log(string.format("[%d] %s", i, short))
        for _, prop in ipairs({
            "MaxSpeedLimit", "DynamicMaxTorque", "TargetAcceleration",
            "TopSpeedF", "HighGearSpeed", "EnginePower"
        }) do
            local val = ReadNum(v, prop)
            if val ~= nil then
                local addr = GetAddr(v)
                local orig = addr and OriginalCache[addr] and OriginalCache[addr].originals[prop]
                if orig then
                    Log(string.format("    %s=%.3f (orig %.3f)", prop, val, orig))
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
                Log(string.format("    Gears[1] EndSpeed=%s MaxTorque=%s (count=%d)",
                    tostring(es), tostring(mt), arr:GetArrayNum()))
            end
        end)
    end
end

local function SetPreset(name)
    if not Config.presets or not Config.presets[name] then
        Log("Unknown preset. Available: " .. table.concat(GetPresetOrder(), ", "))
        return
    end
    Config.active_preset = name
    if VehicleSpeedConfig then VehicleSpeedConfig.active_preset = name end
    PresetGeneration = PresetGeneration + 1
    GearKey = {}
    local nv, np, ng = ApplyAll(true)
    Log(string.format("preset=%s vehicles=%d props=%d gearFields=%d", name, nv, np, ng))
    if nv == 0 then
        Log("TIP: get in a vehicle / load a world first, then vehiclespeed_apply")
    end
end

local function CyclePreset(dir)
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
        GearKey = {}
        local nv, np, ng = ApplyAll(true)
        Log(string.format("Applied vehicles=%d props=%d gears=%d", nv, np, ng))
    end)
end)

RegisterConsoleCommandHandler("vehiclespeed_reset", function(_, _, Ar)
    return WithAr(Ar, function()
        Log("Restored " .. tostring(ResetAll()) .. " fields")
    end)
end)

RegisterConsoleCommandHandler("vehiclespeed_enable", function(_, Parameters, Ar)
    return WithAr(Ar, function()
        local a = Parameters and Parameters[1]
        if a == "0" or a == "off" or a == "false" then
            Config.enabled = false
            if VehicleSpeedConfig then VehicleSpeedConfig.enabled = false end
            Log("Disabled")
        elseif a == "1" or a == "on" or a == "true" then
            Config.enabled = true
            if VehicleSpeedConfig then VehicleSpeedConfig.enabled = true end
            GearKey = {}
            local nv, np, ng = ApplyAll(true)
            Log(string.format("Enabled vehicles=%d props=%d gears=%d", nv, np, ng))
        else
            Log("vehiclespeed_enable 0|1 (now " .. tostring(Config.enabled) .. ")")
        end
    end)
end)

RegisterConsoleCommandHandler("vehiclespeed_help", function(_, _, Ar)
    return WithAr(Ar, function()
        Log("vehiclespeed_status | apply | preset sport|insane|vanilla | reload | enable 0|1 | reset")
        Log("Keybinds: Ctrl+Shift+Left/Right cycle, Ctrl+Shift+V status")
        Log("Must be IN WORLD with vehicles spawned. Main menu = 0 vehicles.")
    end)
end)

local kb = Config.keybinds or {}
if kb.next_preset ~= false and not IsKeyBindRegistered(Key.RIGHT_ARROW, { ModifierKey.CONTROL, ModifierKey.SHIFT }) then
    RegisterKeyBind(Key.RIGHT_ARROW, { ModifierKey.CONTROL, ModifierKey.SHIFT }, function()
        ExecuteInGameThread(function() CyclePreset(1) end)
    end)
end
if kb.prev_preset ~= false and not IsKeyBindRegistered(Key.LEFT_ARROW, { ModifierKey.CONTROL, ModifierKey.SHIFT }) then
    RegisterKeyBind(Key.LEFT_ARROW, { ModifierKey.CONTROL, ModifierKey.SHIFT }, function()
        ExecuteInGameThread(function() CyclePreset(-1) end)
    end)
end
if kb.status ~= false and not IsKeyBindRegistered(Key.V, { ModifierKey.CONTROL, ModifierKey.SHIFT }) then
    RegisterKeyBind(Key.V, { ModifierKey.CONTROL, ModifierKey.SHIFT }, function()
        ExecuteInGameThread(function() PrintStatus() end)
    end)
end

local function StartLoop()
    if ApplyLoopStarted then return end
    ApplyLoopStarted = true
    local ms = math.floor((tonumber(Config.apply_interval_seconds) or 4) * 1000)
    if ms < 2000 then ms = 2000 end
    LoopAsync(ms, function()
        pcall(function()
            if Config.enabled ~= false then
                ApplyAll(false)
            end
        end)
        return false
    end)
end

RegisterLoadMapPostHook(function()
    ExecuteInGameThread(function()
        ExecuteWithDelay(3000, function()
            if Config.enabled == false then return end
            GearKey = {}
            local nv, np, ng = ApplyAll(true)
            Log(string.format("Map load: vehicles=%d props=%d gears=%d", nv, np, ng))
        end)
    end)
end)

pcall(function()
    NotifyOnNewObject("/Game/Vehicles/AVS_SuperVehicleBase.AVS_SuperVehicleBase_C", function(obj)
        ExecuteWithDelay(1200, function()
            if Config.enabled == false then return end
            if obj and obj:IsValid() then
                local p, g = ApplyToVehicle(obj, true)
                Log(string.format("New vehicle: props=%d gears=%d (%s)", p, g, tostring(GetClassShort(obj))))
            end
        end)
    end)
end)

Log(string.format("Loaded. enabled=%s preset=%s scale_gears=%s",
    tostring(Config.enabled), tostring(Config.active_preset), tostring(Config.scale_gears)))
Log("In-world: vehiclespeed_status then vehiclespeed_preset sport")
StartLoop()

ExecuteInGameThread(function()
    ExecuteWithDelay(5000, function()
        if Config.enabled == false then return end
        local nv, np, ng = ApplyAll(true)
        Log(string.format("Initial: vehicles=%d props=%d gears=%d", nv, np, ng))
    end)
end)
