# Existing mods (status as of handoff)

Base path: `E:\SteamLibrary\steamapps\common\OutofOre\OutOfOre\Binaries\Win64\UE4SS\Mods\`

## mods.txt (last known)

```text
CheatManagerEnablerMod : 0
ConsoleCommandsMod : 1
ConsoleEnablerMod : 1
SplitScreenMod : 0
LineTraceMod : 0
BPML_GenericFunctions : 1
BPModLoaderMod : 1
Keybinds : 1
BlueprintDumpMod : 0
VehicleSpeedMod : 1
DirtCapacityMod : 1
```

Always re-read live `mods.txt` — user may change it.

---

## Custom mods

### DirtCapacityMod ✅

| | |
|--|--|
| Path | `Mods\DirtCapacityMod\Scripts\` |
| Config | `config.lua` → `DirtCapacityConfig` |
| Target | `TerraformComponent` (+ optional vehicle `TransDirtAccSize`) |
| Goal | Bigger dirt hold; terrain dig/dump matches; full bucket still liftable |

**Config keys:**

- `dirt_capacity` — volume multiplier  
- `terrain_manipulation` — defaults to same as capacity if `match_terrain_to_capacity`  
- `weight_scale` — defaults to `1/dirt_capacity` if `compensate_weight`  
- Presets: `vanilla`, `double`, `huge`  

**Commands:** `dirtcap_status`, `dirtcap_apply`, `dirtcap_preset`, `dirtcap_reload`, `dirtcap_enable`, `dirtcap_reset`, `dirtcap_help`  

**Keybinds:** Ctrl+Shift+D status; bracket keys cycle if available  

**Safety:** original×mult only; does not stack-multiply `ActualFillVolumeM3` as capacity.

---

### VehicleSpeedMod ✅

| | |
|--|--|
| Path | `Mods\VehicleSpeedMod\Scripts\` |
| Config | `config.lua` → `VehicleSpeedConfig` |
| Target | `AVS_SuperVehicleBase` / AVS props + gear arrays |
| Goal | Faster machines via speed/torque props + gear EndSpeed/MaxTorque |

**Config keys:**

- Presets: `vanilla`, `sport`, `insane`, **`insane+` (100× — extreme)**  
- `scale_gears` — scale gear table fields  
- `absolute_floors` — when values are 0  

**Commands:** `vehiclespeed_status`, `vehiclespeed_apply`, `vehiclespeed_preset`, `vehiclespeed_reload`, `vehiclespeed_enable`, `vehiclespeed_reset`, `vehiclespeed_help`  

**Keybinds:** Ctrl+Shift+Left/Right cycle (debounced); Ctrl+Shift+V status  

**History:** Earlier builds re-multiplied torque every tick → broke interact/storage. Later, cycling presets felt stacked (multiple loops / no restore). Current build: restore stock first, then apply one mult; single LoopAsync; debounced keys. Gear scaling + props are the main path.

---

### BlueprintDumpMod (optional)

| | |
|--|--|
| Path | `Mods\BlueprintDumpMod\Scripts\main.lua` |
| Status | Often **disabled** in mods.txt (`: 0`) |
| Commands | `bpdump`, `bpdump_game`, `bpdump_detail <Name>`, `bpdump_actors`, `bpdump_help` |
| Outputs | Often written under Win64 or UE4SS working dir: `BP_Catalog.*`, `BP_Detail_*.txt`, `BP_Actors.txt` |

Enable when researching new systems.

---

### RoleStoreMod ❌ removed

- Was role-based store purchase filter on `PC_Standard_C:PurchaseItem`  
- **Folder deleted**; removed from mods.txt/json  
- Do **not** recreate unless user explicitly asks  

---

## Stock UE4SS mods (keep)

| Mod | Role |
|-----|------|
| ConsoleEnablerMod | In-game console keys |
| ConsoleCommandsMod | `dump_object`, `set`, `summon` |
| Keybinds | Ctrl+J dump, Ctrl+H SDK, etc. |
| BPModLoaderMod | LogicMods pak loading |
| BPML_GenericFunctions | Helpers for BP mods |
| CheatManagerEnablerMod | Optional cheats (often off) |
| shared/UEHelpers | Shared Lua helpers |

---

## When adding a new mod

1. New folder under `Mods\`  
2. Entry in `mods.txt` **and** `mods.json`  
3. Document it in this file and `AI_MODDING_GUIDE.md`  
4. Optional: include in starter `.ooomod` via `assemble_kit.ps1`  
