--[[
    DirtCapacityMod — dirt hold + terrain manipulation (Out of Ore)

    Capacity:  TotalFillVolumeM3, modifiers, DirtAcc, TransDirtAccSize
    Terrain:   cut/dump rates so dig/dump matches bigger bucket volume
    Weight:    WeightModifier scaled DOWN when capacity goes UP (lift full bucket)

    Safety: always ORIGINAL * multiplier (never stacks current value).
    Does NOT multiply ActualFillVolumeM3 (current load).
]]

local UEHelpers = require("UEHelpers")
require("config")

local Config = DirtCapacityConfig or {}
local GlobalAr = nil
local OriginalCache = {} -- [addr] = { originals = { prop = number }, classShort = string }
local ApplyLoopStarted = false

-- Bucket / hold volume (scale UP with dirt_capacity)
local CapacityProps = {
    "TotalFillVolumeM3",
    "TotalFillVolumeM3Modifier",
    "DirtAcc",
    "DozerBuffertAmount Dm 3",
}

-- Terrain cut / dump / voxel conversion (scale with terrain_manipulation)
local TerrainProps = {
    "DirtToWorldModifier",
    "CutBoxModifier",
    "CutBulk",
    "LinearModifier",
    "VoxelToBulkMultiplier",
    "VoxelToOreMultiplier",
    "DumpAmountStart",
    "DumpAmountEnd",
    "fUnloadSpeed",
    "Sphere Cut Radius",
    "VelocityExtraCutExtent",
    "RotationalExtraCutExtent",
    "BladeSize",
    "Bulk",
    "SpeedFill",
    "TempTotalDumpAmount",
}

-- Weight density (scale DOWN so full bucket is still liftable)
local WeightProps = {
    "WeightModifier",
}

-- Vehicle-level optional capacity
local VehicleProps = {
    "TransDirtAccSize",
}

local function Log(msg)
    local line = "[DirtCapacityMod] " .. tostring(msg)
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
        Config = DirtCapacityConfig or {}
    end)
    if not ok then
        Log("Config reload failed: " .. tostring(err))
        return false
    end
    Log("Config reloaded enabled=" .. tostring(Config.enabled) ..
        " preset=" .. tostring(Config.active_preset))
    return true
end

local function GetPresetOrder()
    if type(Config.presets) ~= "table" then return {} end
    local preferred = { "vanilla", "double", "huge" }
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

local function GetCapacityMult()
    local name = Config.active_preset or "vanilla"
    local p = (Config.presets and Config.presets[name]) or {}
    local m = tonumber(p.dirt_capacity) or 1.0
    if m < 0.1 then m = 0.1 end
    if m > 20 then m = 20 end -- hard safety cap
    return m, name
end

--- Terrain cut/dump multiplier — matches dirt_capacity unless overridden
local function GetTerrainMult()
    local name = Config.active_preset or "vanilla"
    local p = (Config.presets and Config.presets[name]) or {}
    if p.terrain_manipulation ~= nil then
        local t = tonumber(p.terrain_manipulation) or 1.0
        if t < 0.1 then t = 0.1 end
        if t > 20 then t = 20 end
        return t
    end
    if Config.match_terrain_to_capacity == false then
        return 1.0
    end
    return GetCapacityMult()
end

--- Weight density multiplier (NOT total weight of a full bucket if compensated)
local function GetWeightMult()
    local name = Config.active_preset or "vanilla"
    local p = (Config.presets and Config.presets[name]) or {}
    if p.weight_scale ~= nil then
        local w = tonumber(p.weight_scale) or 1.0
        if w < 0.05 then w = 0.05 end
        if w > 5 then w = 5 end
        return w
    end
    -- Default: keep full-bucket mass roughly stock when capacity increases
    if Config.compensate_weight ~= false then
        local cap = GetCapacityMult()
        if cap <= 0 then return 1.0 end
        local w = 1.0 / cap
        if w < 0.05 then w = 0.05 end
        return w
    end
    return 1.0
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

local function EnsureCache(obj)
    local addr = GetAddr(obj)
    if not addr then return nil, nil end
    if not OriginalCache[addr] then
        OriginalCache[addr] = {
            originals = {},
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
        if v ~= nil then
            cache.originals[prop] = v
        end
    end
end

local function FloorBase(prop, original)
    local floors = Config.absolute_floors or {}
    local f = floors[prop]
    if original == nil then return nil end
    -- Only floor pure zeros for modifier-style fields
    if f and original == 0 then
        return f
    end
    return original
end

local function ApplyPropList(obj, props, mult)
    local n = 0
    local cache = EnsureCache(obj)
    if not cache then return 0 end

    -- unique prop names
    local seen = {}
    for _, prop in ipairs(props) do
        if not seen[prop] then
            seen[prop] = true
            CacheProp(obj, prop)
            local original = cache.originals[prop]
            if original ~= nil then
                local base = FloorBase(prop, original)
                local target = base * mult
                if WriteNum(obj, prop, target) then
                    n = n + 1
                    if Config.log_applies then
                        Log(string.format("  %s %s: %.4f -> %.4f (x%.2f)",
                            tostring(cache.classShort), prop, original, target, mult))
                    end
                end
            end
        end
    end
    return n
end

local function TryCallSetMaxCapacity(comp, mult)
    -- Optional: if BP exposes SetMaxCapacity, call after write
    pcall(function()
        local fn = comp.SetMaxCapacity
        if fn and type(fn) == "function" then
            -- Unknown signature; skip call — property write is primary
        elseif fn and fn.IsValid and fn:IsValid() then
            -- UFunction object — try call with scaled total if we know it
            local cache = EnsureCache(comp)
            local orig = cache and cache.originals["TotalFillVolumeM3"]
            if orig then
                local base = FloorBase("TotalFillVolumeM3", orig)
                pcall(function() comp:SetMaxCapacity(base * mult) end)
            end
        end
    end)
end

local function IsTerraformComponent(obj)
    if not obj or not obj:IsValid() then return false end
    local short = GetClassShort(obj) or ""
    if short:find("TerraformComponent", 1, true) then return true end
    -- property probe
    if ReadNum(obj, "TotalFillVolumeM3") ~= nil then return true end
    if ReadNum(obj, "TotalFillVolumeM3Modifier") ~= nil then return true end
    return false
end

local function CollectTerraformComponents()
    local list, seen = {}, {}

    local function add(obj)
        if not obj or type(obj) ~= "userdata" then return end
        local valid = false
        pcall(function() valid = obj:IsValid() end)
        if not valid then return end
        if not IsTerraformComponent(obj) then return end
        local addr = GetAddr(obj)
        if not addr or seen[addr] then return end
        seen[addr] = true
        table.insert(list, obj)
    end

    for _, name in ipairs({
        "TerraformComponent_C",
        "TerraformComponent",
    }) do
        pcall(function()
            local found = FindAllOf(name)
            if found then for _, o in ipairs(found) do add(o) end end
        end)
        pcall(function() add(FindFirstOf(name)) end)
    end

    -- From vehicles
    for _, vname in ipairs({
        "AVS_SuperVehicleBase_C",
        "AVS_Base_C",
        "BP_VehicleBase_C",
    }) do
        pcall(function()
            local found = FindAllOf(vname)
            if not found then return end
            for _, veh in ipairs(found) do
                if veh and veh:IsValid() then
                    pcall(function() add(veh.TerraformComponent) end)
                    pcall(function() add(veh["Terraform Component"]) end)
                    -- common component property names
                    pcall(function()
                        local comps = veh.BlueprintCreatedComponents
                        -- may not exist
                    end)
                end
            end
        end)
    end

    -- Fallback scan
    if #list == 0 then
        pcall(function()
            ForEachUObject(function(obj)
                local short = GetClassShort(obj)
                if short and short:find("TerraformComponent", 1, true) then
                    add(obj)
                end
            end)
        end)
    end

    return list
end

local function CollectVehiclesForSecondary()
    local list, seen = {}, {}
    local function add(obj)
        if not obj or not obj:IsValid() then return end
        local short = GetClassShort(obj) or ""
        if not (short:find("AVS_SuperVehicle", 1, true)
            or short:find("AVS_Base", 1, true)
            or short == "BP_VehicleBase_C"
            or (short:match("^V_") and short:find("Base"))) then
            return
        end
        local addr = GetAddr(obj)
        if not addr or seen[addr] then return end
        seen[addr] = true
        table.insert(list, obj)
    end

    for _, name in ipairs({
        "AVS_SuperVehicleBase_C", "AVS_Base_C", "BP_VehicleBase_C",
        "V_TruckBase_C", "V_SemiTruckBase_C", "V_PaverBase_C",
    }) do
        pcall(function()
            local found = FindAllOf(name)
            if found then for _, o in ipairs(found) do add(o) end end
        end)
    end
    return list
end

local function ApplyToTerraform(comp, capMult, terrainMult, weightMult)
    local n = 0
    n = n + ApplyPropList(comp, CapacityProps, capMult)
    n = n + ApplyPropList(comp, TerrainProps, terrainMult)
    n = n + ApplyPropList(comp, WeightProps, weightMult)
    TryCallSetMaxCapacity(comp, capMult)

    -- If a hydraulic power cut flag exists and is stuck true when full, clear it
    pcall(function()
        if comp.IsHydraulicPowerCut == true then
            comp.IsHydraulicPowerCut = false
        end
    end)

    return n
end

local function ApplyToVehicle(veh, capMult)
    return ApplyPropList(veh, VehicleProps, capMult)
end

local function ApplyAll()
    if Config.enabled == false then
        return 0, 0, 0
    end
    local capMult = GetCapacityMult()
    local terrainMult = GetTerrainMult()
    local weightMult = GetWeightMult()
    local comps = CollectTerraformComponents()
    local vehicles = CollectVehiclesForSecondary()
    local writes = 0
    for _, c in ipairs(comps) do
        writes = writes + ApplyToTerraform(c, capMult, terrainMult, weightMult)
    end
    for _, v in ipairs(vehicles) do
        writes = writes + ApplyToVehicle(v, capMult)
    end
    return #comps, #vehicles, writes
end

local function ResetAll()
    local n = 0
    local function restore(obj)
        local addr = GetAddr(obj)
        local cache = addr and OriginalCache[addr]
        if not cache or not cache.originals then return end
        for prop, orig in pairs(cache.originals) do
            if WriteNum(obj, prop, orig) then n = n + 1 end
        end
    end
    for _, c in ipairs(CollectTerraformComponents()) do restore(c) end
    for _, v in ipairs(CollectVehiclesForSecondary()) do restore(v) end
    return n
end

local function PrintStatus()
    local mult, name = GetCapacityMult()
    local tmult = GetTerrainMult()
    local wmult = GetWeightMult()
    Log("=== DirtCapacityMod ===")
    Log(string.format("enabled=%s preset=%s dirt_x=%.2f terrain_x=%.2f weight_x=%.2f",
        tostring(Config.enabled), name, mult, tmult, wmult))
    Log(string.format("compensate_weight=%s match_terrain=%s",
        tostring(Config.compensate_weight ~= false),
        tostring(Config.match_terrain_to_capacity ~= false)))
    Log("presets: " .. table.concat(GetPresetOrder(), ", "))
    Log("terrain_x scales dig cut size / dump rates to match bigger bucket")

    local comps = CollectTerraformComponents()
    Log("TerraformComponents found: " .. tostring(#comps))
    if #comps == 0 then
        Log("None found. Enter a digger/loader in the world, then dirtcap_apply")
    end

    for i, c in ipairs(comps) do
        if i > 8 then
            Log("... +" .. tostring(#comps - 8) .. " more")
            break
        end
        local short = GetClassShort(c) or "?"
        local outerName = "?"
        pcall(function()
            local o = c:GetOuter()
            if o and o:IsValid() then outerName = GetClassShort(o) or o:GetFullName() end
        end)
        Log(string.format("[%d] %s (outer=%s)", i, short, tostring(outerName)))
        for _, prop in ipairs({
            "TotalFillVolumeM3", "TotalFillVolumeM3Modifier", "DirtAcc",
            "ActualFillVolumeM3", "WeightModifier",
            "DirtToWorldModifier", "CutBoxModifier", "CutBulk",
            "VoxelToBulkMultiplier", "DumpAmountStart", "DumpAmountEnd",
            "Sphere Cut Radius", "LinearModifier",
        }) do
            local val = ReadNum(c, prop)
            if val ~= nil then
                local addr = GetAddr(c)
                local orig = addr and OriginalCache[addr] and OriginalCache[addr].originals[prop]
                if orig then
                    Log(string.format("    %s=%.4f (orig %.4f)", prop, val, orig))
                else
                    Log(string.format("    %s=%.4f", prop, val))
                end
            end
        end
    end

    local vehicles = CollectVehiclesForSecondary()
    local withTrans = 0
    for _, v in ipairs(vehicles) do
        if ReadNum(v, "TransDirtAccSize") then withTrans = withTrans + 1 end
    end
    Log(string.format("Vehicles scanned: %d (with TransDirtAccSize: %d)", #vehicles, withTrans))
end

local function SetPreset(name)
    if not Config.presets or not Config.presets[name] then
        Log("Unknown preset. Available: " .. table.concat(GetPresetOrder(), ", "))
        return
    end
    Config.active_preset = name
    if DirtCapacityConfig then DirtCapacityConfig.active_preset = name end
    local nc, nv, nw = ApplyAll()
    Log(string.format("preset=%s terraform=%d vehicles=%d writes=%d", name, nc, nv, nw))
    if nc == 0 then
        Log("TIP: load world + use a machine with a bucket, then dirtcap_apply")
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

RegisterConsoleCommandHandler("dirtcap_reload", function(_, _, Ar)
    return WithAr(Ar, function()
        if ReloadConfig() then
            local nc, nv, nw = ApplyAll()
            Log(string.format("Applied terraform=%d vehicles=%d writes=%d", nc, nv, nw))
        end
    end)
end)

RegisterConsoleCommandHandler("dirtcap_status", function(_, _, Ar)
    return WithAr(Ar, function() PrintStatus() end)
end)

RegisterConsoleCommandHandler("dirtcap_preset", function(_, Parameters, Ar)
    return WithAr(Ar, function() SetPreset(Parameters and Parameters[1]) end)
end)

RegisterConsoleCommandHandler("dirtcap_apply", function(_, _, Ar)
    return WithAr(Ar, function()
        local nc, nv, nw = ApplyAll()
        Log(string.format("Applied terraform=%d vehicles=%d writes=%d", nc, nv, nw))
    end)
end)

RegisterConsoleCommandHandler("dirtcap_reset", function(_, _, Ar)
    return WithAr(Ar, function()
        Log("Restored " .. tostring(ResetAll()) .. " fields")
    end)
end)

RegisterConsoleCommandHandler("dirtcap_enable", function(_, Parameters, Ar)
    return WithAr(Ar, function()
        local a = Parameters and Parameters[1]
        if a == "0" or a == "off" or a == "false" then
            Config.enabled = false
            if DirtCapacityConfig then DirtCapacityConfig.enabled = false end
            Log("Disabled")
        elseif a == "1" or a == "on" or a == "true" then
            Config.enabled = true
            if DirtCapacityConfig then DirtCapacityConfig.enabled = true end
            local nc, nv, nw = ApplyAll()
            Log(string.format("Enabled terraform=%d vehicles=%d writes=%d", nc, nv, nw))
        else
            Log("dirtcap_enable 0|1 (now " .. tostring(Config.enabled) .. ")")
        end
    end)
end)

RegisterConsoleCommandHandler("dirtcap_help", function(_, _, Ar)
    return WithAr(Ar, function()
        Log("dirtcap_status | apply | preset vanilla|double|huge | reload | enable 0|1 | reset")
        Log("Keys: Ctrl+Shift+D status, Ctrl+Shift+[ / ] cycle presets")
        Log("Edit: Mods/DirtCapacityMod/Scripts/config.lua")
    end)
end)

local kb = Config.keybinds or {}
if kb.status ~= false and not IsKeyBindRegistered(Key.D, { ModifierKey.CONTROL, ModifierKey.SHIFT }) then
    RegisterKeyBind(Key.D, { ModifierKey.CONTROL, ModifierKey.SHIFT }, function()
        ExecuteInGameThread(function() PrintStatus() end)
    end)
end
-- OEM_4 = [, OEM_6 = ] on many layouts — use LEFT/RIGHT BRACKET if available
if kb.next_preset ~= false then
    local keyNext = Key.OEM_SIX or Key.RIGHT_BRACKET or Key.PERIOD
    if keyNext and not IsKeyBindRegistered(keyNext, { ModifierKey.CONTROL, ModifierKey.SHIFT }) then
        RegisterKeyBind(keyNext, { ModifierKey.CONTROL, ModifierKey.SHIFT }, function()
            ExecuteInGameThread(function() CyclePreset(1) end)
        end)
    end
end
if kb.prev_preset ~= false then
    local keyPrev = Key.OEM_FOUR or Key.LEFT_BRACKET or Key.COMMA
    if keyPrev and not IsKeyBindRegistered(keyPrev, { ModifierKey.CONTROL, ModifierKey.SHIFT }) then
        RegisterKeyBind(keyPrev, { ModifierKey.CONTROL, ModifierKey.SHIFT }, function()
            ExecuteInGameThread(function() CyclePreset(-1) end)
        end)
    end
end

local function StartLoop()
    if ApplyLoopStarted then return end
    ApplyLoopStarted = true
    local ms = math.floor((tonumber(Config.apply_interval_seconds) or 4) * 1000)
    if ms < 2000 then ms = 2000 end
    LoopAsync(ms, function()
        pcall(function()
            if Config.enabled ~= false then ApplyAll() end
        end)
        return false
    end)
end

RegisterLoadMapPostHook(function()
    ExecuteInGameThread(function()
        ExecuteWithDelay(3000, function()
            if Config.enabled == false then return end
            local nc, nv, nw = ApplyAll()
            Log(string.format("Map load: terraform=%d vehicles=%d writes=%d", nc, nv, nw))
        end)
    end)
end)

pcall(function()
    NotifyOnNewObject("/Game/VehicleComponents/TerraformComponent.TerraformComponent_C", function(obj)
        ExecuteWithDelay(800, function()
            if Config.enabled == false then return end
            if obj and obj:IsValid() then
                local capMult = GetCapacityMult()
                local terrainMult = GetTerrainMult()
                local weightMult = GetWeightMult()
                local n = ApplyToTerraform(obj, capMult, terrainMult, weightMult)
                if Config.log_applies then
                    Log("New TerraformComponent writes=" .. tostring(n))
                end
            end
        end)
    end)
end)

pcall(function()
    NotifyOnNewObject("/Game/Vehicles/AVS_SuperVehicleBase.AVS_SuperVehicleBase_C", function(obj)
        ExecuteWithDelay(1500, function()
            if Config.enabled == false then return end
            if obj and obj:IsValid() then
                ApplyAll()
            end
        end)
    end)
end)

local mult, pname = GetCapacityMult()
local tmult = GetTerrainMult()
local wmult = GetWeightMult()
Log(string.format("Loaded. enabled=%s preset=%s dirt_x=%.2f terrain_x=%.2f weight_x=%.2f",
    tostring(Config.enabled), pname, mult, tmult, wmult))
Log("Terrain cut/dump scales with capacity. Weight scaled down so full buckets lift.")
Log("In-world: dirtcap_status | dirtcap_preset double | dirtcap_reload")
StartLoop()

ExecuteInGameThread(function()
    ExecuteWithDelay(5000, function()
        if Config.enabled == false then return end
        local nc, nv, nw = ApplyAll()
        Log(string.format("Initial: terraform=%d vehicles=%d writes=%d", nc, nv, nw))
    end)
end)
