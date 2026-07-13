--[[
    BlueprintDumpMod — dump loaded BlueprintGeneratedClass data for Out of Ore mod research.

    Console commands (open in-game console via ConsoleEnablerMod):
      bpdump              — all BlueprintGeneratedClass currently loaded
      bpdump_game         — game-focused filter (recommended)
      bpdump_detail <name>— functions + properties for one class
      bpdump_actors       — live actors whose class ends with _C
      bpdump_help         — list commands

    Hotkey: Ctrl+Shift+B → bpdump_game

    Output files are written next to UE4SS (working directory):
      BP_Catalog.txt / BP_Catalog.csv
      BP_Detail_<Name>.txt
      BP_Actors.txt
]]

local UEHelpers = require("UEHelpers")

local OutputDir = "." -- UE4SS working directory (...\Binaries\Win64\ue4ss)
local GlobalAr = nil

local GameNamePrefixes = {
    "BP_", "BFL_", "PC_", "AC_", "ABP_", "AVS_", "WBP_", "UI_",
    "GM_", "GS_", "HUD_", "AN_", "BPC_", "BPI_", "DT_", "DA_",
}

local EngineNoisePatterns = {
    "/Script/Engine.",
    "/Script/CoreUObject.",
    "/Script/UMG.",
    "/Script/Slate.",
    "/Script/SlateCore.",
    "/Script/MovieScene",
    "/Script/Niagara",
    "/Script/AnimGraphRuntime",
    "/Script/GameplayAbilities",
    "/Script/OnlineSubsystem",
    "/Script/EnhancedInput",
    "/Engine/",
    "/Script/AIModule",
    "/Script/NavigationSystem",
}

local function Log(msg)
    local line = "[BlueprintDumpMod] " .. tostring(msg)
    print(line .. "\n")
    if GlobalAr and type(GlobalAr) == "userdata" then
        pcall(function() GlobalAr:Log(line) end)
    end
end

local function SafeStr(fn, fallback)
    local ok, result = pcall(fn)
    if ok and result ~= nil then
        return tostring(result)
    end
    return fallback or "?"
end

local function EndsWith(str, suffix)
    if not str or not suffix then return false end
    return str:sub(-#suffix) == suffix
end

local function StartsWith(str, prefix)
    if not str or not prefix then return false end
    return str:sub(1, #prefix) == prefix
end

local function Contains(str, needle)
    return str and needle and str:find(needle, 1, true) ~= nil
end

local function SanitizeFileName(name)
    return (name or "unknown"):gsub("[^%w%._%-]", "_")
end

local function WriteTextFile(path, content)
    local f, err = io.open(path, "w+")
    if not f then
        Log("Failed to write " .. path .. ": " .. tostring(err))
        return false
    end
    f:write(content)
    f:close()
    return true
end

local function GetShortName(fullName)
    -- e.g. "BlueprintGeneratedClass /Game/Blueprints/PC_Standard.PC_Standard_C"
    if not fullName then return "?" end
    local short = fullName:match("%.([^%.%s]+)$")
    if short then return short end
    short = fullName:match("([^%s/]+)$")
    return short or fullName
end

local function GetParentName(classObj)
    local ok, parent = pcall(function()
        local super = classObj:GetSuperStruct()
        if super and super:IsValid() then
            return super:GetFullName()
        end
        return nil
    end)
    if ok and parent then return parent end
    return ""
end

local function IsBlueprintGeneratedClass(obj)
    if not obj or not obj:IsValid() then return false end
    local ok, result = pcall(function()
        if not obj:IsAnyClass() and not obj:IsClass() then
            return false
        end
        local full = obj:GetFullName() or ""
        if Contains(full, "BlueprintGeneratedClass") then
            return true
        end
        -- Fallback: UClass whose short name ends with _C
        local short = GetShortName(full)
        if EndsWith(short, "_C") and obj:IsClass() then
            return true
        end
        return false
    end)
    return ok and result
end

local function IsEngineNoise(fullName)
    if not fullName then return true end
    for _, pat in ipairs(EngineNoisePatterns) do
        if Contains(fullName, pat) then
            return true
        end
    end
    return false
end

local function LooksLikeGameBlueprint(fullName, shortName)
    if not fullName then return false end
    if Contains(fullName, "/Game/") then return true end
    if Contains(fullName, "OutOfOre") then return true end
    if IsEngineNoise(fullName) then return false end
    for _, prefix in ipairs(GameNamePrefixes) do
        if StartsWith(shortName or "", prefix) then
            return true
        end
    end
    -- Non-engine package classes ending in _C are often game/plugin content
    if EndsWith(shortName or "", "_C") and not IsEngineNoise(fullName) then
        return true
    end
    return false
end

local function CollectBlueprintClasses(gameOnly)
    local results = {}
    local seen = {}

    ForEachUObject(function(obj, _chunk, _index)
        local ok, err = pcall(function()
            if not IsBlueprintGeneratedClass(obj) then return end
            local full = SafeStr(function() return obj:GetFullName() end)
            if full == "?" or seen[full] then return end
            local short = GetShortName(full)
            if gameOnly and not LooksLikeGameBlueprint(full, short) then return end
            seen[full] = true
            table.insert(results, {
                full = full,
                short = short,
                parent = GetParentName(obj),
                obj = obj,
            })
        end)
        if not ok then
            -- skip bad objects quietly
        end
    end)

    table.sort(results, function(a, b)
        return (a.short or "") < (b.short or "")
    end)
    return results
end

local function FormatCatalogText(entries, title)
    local lines = {}
    table.insert(lines, title)
    table.insert(lines, string.format("Generated: %s", os.date("%Y-%m-%d %H:%M:%S")))
    table.insert(lines, string.format("Count: %d", #entries))
    table.insert(lines, string.rep("=", 80))
    table.insert(lines, "")
    for _, e in ipairs(entries) do
        table.insert(lines, string.format("%s", e.short))
        table.insert(lines, string.format("  Full:   %s", e.full))
        if e.parent and e.parent ~= "" then
            table.insert(lines, string.format("  Parent: %s", e.parent))
        end
        table.insert(lines, "")
    end
    return table.concat(lines, "\n")
end

local function FormatCatalogCsv(entries)
    local lines = { "short_name,full_name,parent" }
    for _, e in ipairs(entries) do
        local function csvEscape(s)
            s = tostring(s or ""):gsub('"', '""')
            if s:find('[,"\n]') then
                return '"' .. s .. '"'
            end
            return s
        end
        table.insert(lines, string.format("%s,%s,%s",
            csvEscape(e.short), csvEscape(e.full), csvEscape(e.parent)))
    end
    return table.concat(lines, "\n")
end

local function DumpCatalog(gameOnly)
    local label = gameOnly and "game-focused" or "all BlueprintGeneratedClass"
    Log("Scanning UObject array (" .. label .. ")...")
    local entries = CollectBlueprintClasses(gameOnly)
    Log(string.format("Found %d blueprint classes", #entries))

    local title = gameOnly
        and "Out of Ore — Game Blueprint Catalog (bpdump_game)"
        or "Out of Ore — Full Blueprint Catalog (bpdump)"

    local txtPath = OutputDir .. "/BP_Catalog.txt"
    local csvPath = OutputDir .. "/BP_Catalog.csv"
    if WriteTextFile(txtPath, FormatCatalogText(entries, title)) then
        Log("Wrote " .. txtPath)
    end
    if WriteTextFile(csvPath, FormatCatalogCsv(entries)) then
        Log("Wrote " .. csvPath)
    end
    Log("Done. Open BP_Catalog.csv in Excel or search BP_Catalog.txt.")
    return true
end

local function DumpClassDetail(className)
    if not className or className == "" then
        Log("Usage: bpdump_detail <ClassName>")
        Log("Example: bpdump_detail PC_Standard_C")
        return true
    end

    -- Try several resolution strategies
    local classObj = nil
    local attempts = {
        function() return FindObject(nil, className, nil, nil) end,
        function() return FindFirstOf(className) end,
        function() return StaticFindObject(className) end,
    }

    -- Also search GUObjectArray by short name
    local searchShort = className:match("([^%.]+)$") or className
    if not EndsWith(searchShort, "_C") then
        -- allow user to pass PC_Standard or PC_Standard_C
    end

    for _, attempt in ipairs(attempts) do
        local ok, obj = pcall(attempt)
        if ok and obj and obj:IsValid() then
            -- If we found an instance, use its class
            if obj:IsClass() or obj:IsAnyClass() then
                classObj = obj
            else
                local ok2, cls = pcall(function() return obj:GetClass() end)
                if ok2 and cls and cls:IsValid() then
                    classObj = cls
                end
            end
            if classObj then break end
        end
    end

    if not classObj then
        ForEachUObject(function(obj)
            if classObj then return end
            pcall(function()
                if not IsBlueprintGeneratedClass(obj) then return end
                local full = obj:GetFullName() or ""
                local short = GetShortName(full)
                if short == searchShort or short == className
                    or EndsWith(full, className)
                    or Contains(full, className) then
                    classObj = obj
                end
            end)
        end)
    end

    if not classObj or not classObj:IsValid() then
        Log("Class not found (is it loaded?). Try loading a save/world first: " .. className)
        return true
    end

    local fullName = SafeStr(function() return classObj:GetFullName() end)
    local shortName = GetShortName(fullName)
    local lines = {}
    table.insert(lines, "Blueprint detail dump")
    table.insert(lines, string.format("Generated: %s", os.date("%Y-%m-%d %H:%M:%S")))
    table.insert(lines, string.format("Class: %s", fullName))
    table.insert(lines, string.format("Parent: %s", GetParentName(classObj)))
    table.insert(lines, string.rep("=", 80))

    -- Functions (walk inheritance)
    table.insert(lines, "")
    table.insert(lines, "=== FUNCTIONS ===")
    local funcCount = 0
    local walk = classObj
    while walk and walk:IsValid() do
        local walkName = SafeStr(function() return walk:GetFullName() end)
        table.insert(lines, string.format("-- from %s", walkName))
        pcall(function()
            walk:ForEachFunction(function(fn)
                local fname = SafeStr(function() return fn:GetFName():ToString() end)
                local ffull = SafeStr(function() return fn:GetFullName() end)
                table.insert(lines, string.format("  %s", fname))
                table.insert(lines, string.format("    %s", ffull))
                funcCount = funcCount + 1
            end)
        end)
        local ok, super = pcall(function() return walk:GetSuperStruct() end)
        if ok and super and super:IsValid() then
            walk = super
        else
            break
        end
    end
    table.insert(lines, string.format("Function count (incl. parents): %d", funcCount))

    -- Properties (walk inheritance)
    table.insert(lines, "")
    table.insert(lines, "=== PROPERTIES ===")
    local propCount = 0
    walk = classObj
    while walk and walk:IsValid() do
        local walkName = SafeStr(function() return walk:GetFullName() end)
        table.insert(lines, string.format("-- from %s", walkName))
        pcall(function()
            walk:ForEachProperty(function(prop)
                local pname = SafeStr(function() return prop:GetFName():ToString() end)
                local ptype = SafeStr(function() return prop:GetClass():GetFName():ToString() end)
                local offset = SafeStr(function() return string.format("0x%04X", prop:GetOffset_Internal()) end, "????")
                table.insert(lines, string.format("  %s  %s  %s", offset, ptype, pname))
                propCount = propCount + 1
            end)
        end)
        local ok, super = pcall(function() return walk:GetSuperStruct() end)
        if ok and super and super:IsValid() then
            walk = super
        else
            break
        end
    end
    table.insert(lines, string.format("Property count (incl. parents): %d", propCount))

    local outPath = string.format("%s/BP_Detail_%s.txt", OutputDir, SanitizeFileName(shortName))
    if WriteTextFile(outPath, table.concat(lines, "\n")) then
        Log("Wrote " .. outPath)
    end
    Log(string.format("Detail done: %d functions, %d properties", funcCount, propCount))
    return true
end

local function DumpActors()
    Log("Dumping live blueprint actors...")
    local lines = {}
    table.insert(lines, "Live actors with Blueprint (_C) classes")
    table.insert(lines, string.format("Generated: %s", os.date("%Y-%m-%d %H:%M:%S")))
    table.insert(lines, string.rep("=", 80))

    local count = 0
    local actors = FindAllOf("Actor")
    if actors then
        for _, actor in ipairs(actors) do
            pcall(function()
                if not actor or not actor:IsValid() then return end
                local cls = actor:GetClass()
                if not cls or not cls:IsValid() then return end
                local classFull = cls:GetFullName() or ""
                local classShort = GetShortName(classFull)
                if not EndsWith(classShort, "_C") then return end
                local actorFull = SafeStr(function() return actor:GetFullName() end)
                table.insert(lines, string.format("%s", classShort))
                table.insert(lines, string.format("  Actor: %s", actorFull))
                table.insert(lines, string.format("  Class: %s", classFull))
                table.insert(lines, "")
                count = count + 1
            end)
        end
    end

    table.insert(lines, 4, string.format("Count: %d", count))
    local outPath = OutputDir .. "/BP_Actors.txt"
    if WriteTextFile(outPath, table.concat(lines, "\n")) then
        Log("Wrote " .. outPath)
    end
    Log(string.format("Actor dump done: %d actors", count))
    return true
end

local function PrintHelp()
    Log("Commands:")
    Log("  bpdump              — dump all loaded BlueprintGeneratedClass → BP_Catalog.txt/csv")
    Log("  bpdump_game         — game-focused catalog (recommended) → BP_Catalog.txt/csv")
    Log("  bpdump_detail NAME  — functions+properties for one class → BP_Detail_NAME.txt")
    Log("  bpdump_actors       — live actors with _C classes → BP_Actors.txt")
    Log("  bpdump_help         — this help")
    Log("Hotkey: Ctrl+Shift+B runs bpdump_game")
    Log("Tip: load a save/world first so more blueprints are in memory.")
    Log("Built-in UE4SS dumps: Ctrl+J objects, Ctrl+H SDK, Ctrl+Num7 actors")
    return true
end

local function WithAr(Ar, fn)
    GlobalAr = Ar
    local ok, err = pcall(fn)
    GlobalAr = nil
    if not ok then
        Log("Error: " .. tostring(err))
    end
    return true
end

RegisterConsoleCommandHandler("bpdump", function(FullCommand, Parameters, Ar)
    return WithAr(Ar, function() DumpCatalog(false) end)
end)

RegisterConsoleCommandHandler("bpdump_game", function(FullCommand, Parameters, Ar)
    return WithAr(Ar, function() DumpCatalog(true) end)
end)

RegisterConsoleCommandHandler("bpdump_detail", function(FullCommand, Parameters, Ar)
    return WithAr(Ar, function()
        local name = Parameters and Parameters[1] or nil
        -- If user typed "bpdump_detail PC_Standard_C", Parameters[1] is the class name
        DumpClassDetail(name)
    end)
end)

RegisterConsoleCommandHandler("bpdump_actors", function(FullCommand, Parameters, Ar)
    return WithAr(Ar, function() DumpActors() end)
end)

RegisterConsoleCommandHandler("bpdump_help", function(FullCommand, Parameters, Ar)
    return WithAr(Ar, function() PrintHelp() end)
end)

-- Hotkey: Ctrl+Shift+B → game catalog dump
if not IsKeyBindRegistered(Key.B, { ModifierKey.CONTROL, ModifierKey.SHIFT }) then
    RegisterKeyBind(Key.B, { ModifierKey.CONTROL, ModifierKey.SHIFT }, function()
        ExecuteInGameThread(function()
            Log("Hotkey Ctrl+Shift+B → bpdump_game")
            DumpCatalog(true)
        end)
    end)
end

Log("Loaded. Type bpdump_help in console, or press Ctrl+Shift+B in-game.")
PrintHelp()
