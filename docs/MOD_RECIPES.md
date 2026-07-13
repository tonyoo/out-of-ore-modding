# Recipe: create a UE4SS Lua mod for Out of Ore

## Prerequisites

- UE4SS working (`UE4SS.log` shows PS scan success)  
- Research dumps or Live View for target class/properties  
- Game restarted after enabling new mod  

## Step-by-step

### 1. Research

1. Search `BP_Catalog.csv` / `UE4SS_ObjectDump.txt` for class names  
2. If needed enable BlueprintDumpMod and run:

```text
bpdump_detail SomeClass_C
```

3. Note **full function paths** for hooks, e.g.  
   `/Game/Blueprints/PC_Standard.PC_Standard_C:PurchaseItem`  

### 2. Scaffold files

```text
E:\SteamLibrary\steamapps\common\OutofOre\OutOfOre\Binaries\Win64\UE4SS\Mods\
  MyCoolMod\
    Scripts\
      main.lua
      config.lua          # optional
      config.example.lua  # optional backup
```

### 3. Enable

**mods.txt** (add line; keep Keybinds near bottom):

```text
MyCoolMod : 1
```

**mods.json** — add:

```json
{
  "mod_name": "MyCoolMod",
  "mod_enabled": true
}
```

### 4. Minimal main.lua pattern

```lua
local UEHelpers = require("UEHelpers")
-- require("config")  -- if using config.lua that sets MyCoolConfig = {...}

local function Log(msg)
    print("[MyCoolMod] " .. tostring(msg) .. "\n")
end

-- Cache originals by object address string
local Originals = {}

local function Addr(obj)
    local ok, a = pcall(function() return obj:GetAddress() end)
    if ok and a then return tostring(a) end
    return nil
end

local function ReadNum(obj, name)
    local ok, v = pcall(function() return obj[name] end)
    if ok and type(v) == "number" then return v end
    return nil
end

local function Apply(obj, prop, mult)
    local id = Addr(obj)
    if not id then return end
    if not Originals[id] then Originals[id] = {} end
    if Originals[id][prop] == nil then
        local v = ReadNum(obj, prop)
        if v == nil then return end
        Originals[id][prop] = v
    end
    local base = Originals[id][prop]
    pcall(function() obj[prop] = base * mult end)
end

RegisterConsoleCommandHandler("mycool_status", function()
    Log("alive")
    return true
end)

Log("Loaded")
```

### 5. Finding objects

```lua
-- Preferred for machines:
local found = FindAllOf("AVS_SuperVehicleBase_C")

-- Components:
local comps = FindAllOf("TerraformComponent_C")

-- Fallback scan (slower):
ForEachUObject(function(obj)
    -- filter by GetFullName() / class
end)

-- Player (may be character, not vehicle):
local pawn = UEHelpers.GetPlayer()
local pc = UEHelpers.GetPlayerController()
```

### 6. Hooks (optional)

```lua
RegisterHook("/Game/Blueprints/PC_Standard.PC_Standard_C:SomeFunction", function(Context, ...)
    -- return false to block (when supported)
end)
```

If RegisterHook fails at load time, retry after map load / when class is loaded, or use property loops instead.

### 7. Spawn / map apply

```lua
RegisterLoadMapPostHook(function()
    ExecuteInGameThread(function()
        ExecuteWithDelay(2000, function()
            -- apply
        end)
    end)
end)

NotifyOnNewObject("/Game/Vehicles/AVS_SuperVehicleBase.AVS_SuperVehicleBase_C", function(obj)
    ExecuteWithDelay(1000, function()
        if obj and obj:IsValid() then
            -- apply
        end
    end)
end)
```

### 8. Verify

1. Restart game  
2. `UE4SS.log` contains: `Starting Lua mod 'MyCoolMod'`  
3. Console: your `*_status` command  
4. Behavior works in-world  
5. Storage containers still open; no new crash dumps  

### 9. Ship

- Pack with **OutOfOreModManager** → `.ooomod`  
- Or add to `assemble_kit.ps1` starter custom list  
- Document in `EXISTING_MODS.md` and this pack  

---

## Anti-patterns

| Don’t | Do instead |
|-------|------------|
| `value = value * mult` every 3s | `value = original * mult` |
| Assume `GetPlayer()` is the truck | `FindAllOf("AVS_SuperVehicleBase_C")` |
| Only patch `BP_VehicleBase` | Patch SuperVehicle / Terraform / AVS |
| Multiply weight with dirt capacity | Scale weight **down** when capacity up |
| Enable LoadAllAssets dumps by default | One-shot only; risk OOM/crash |
| Edit the main `.pak` for small tweaks | Lua or LogicMods |

---

## Config.lua convention used here

```lua
MyCoolConfig = {
    enabled = true,
    active_preset = "default",
    presets = {
        default = { some_mult = 1.5 },
    },
}
```

Reload pattern:

```lua
package.loaded["config"] = nil
require("config")
Config = MyCoolConfig or {}
```
