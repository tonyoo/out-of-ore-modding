# Out of Ore — Master AI Modding Guide

**Read this entire file before editing mods.**  
Supporting files: `PATHS.md`, `PITFALLS.md`, `EXISTING_MODS.md`, `MOD_RECIPES.md`, `ARCHITECTURE.md`, `TOOLS.md`.

---

## 1. Project goal

Mod **Out of Ore** (Steam) using **UE4SS Lua**. Prior work includes:

- Verifying UE4SS  
- Dumping blueprints / objects for research  
- Vehicle speed/gears mod  
- Dirt capacity + terrain + weight compensation  
- Desktop Mod Manager + one-click installer kit for sharing  
- Removing RoleStoreMod  
- GitHub monorepo + releases  

---

## 1b. ALWAYS push changes to GitHub (standing order)

**User requirement:** every time you make a change, update GitHub. Do not leave edits only on disk.

| Item | Value |
|------|--------|
| Public monorepo (loader only) | `D:\OpenCode\out-of-ore-modding` → https://github.com/tonyoo/out-of-ore-modding |
| Private monorepo (gameplay mods) | `D:\OpenCode\out-of-ore-gameplay-mods` → https://github.com/tonyoo/out-of-ore-gameplay-mods |
| Branch | `main` (both) |

**Public kit never packages DirtCapacity / VehicleSpeed / BlueprintDump.**  
Gameplay mod sources live only in the **private** repo (+ live game `UE4SS\Mods` for testing).

### After each change (required)

**Gameplay mods** (Dirt / Speed / Dump):

```powershell
$gameMods = "E:\SteamLibrary\steamapps\common\OutofOre\OutOfOre\Binaries\Win64\UE4SS\Mods"
$priv = "D:\OpenCode\out-of-ore-gameplay-mods"
foreach ($m in @("DirtCapacityMod","VehicleSpeedMod","BlueprintDumpMod","GpsAssistMod","VehicleScaleMod")) {
  if (Test-Path "$gameMods\$m") {
    Remove-Item "$priv\$m" -Recurse -Force -ErrorAction SilentlyContinue
    Copy-Item "$gameMods\$m" "$priv\$m" -Recurse -Force
  }
}
cd $priv
git add -A
git commit -m "Describe gameplay mod change"
git push origin main
```

**Loader / manager / installer / public docs:**

```powershell
# Sync tools from live OutOfOreModManager if edited there
# Sync docs from D:\OpenCode\Grok Out Of ore into public repo docs\
cd D:\OpenCode\out-of-ore-modding
git add -A
git commit -m "Describe loader/docs change"
git push origin main
```

### When to also make a GitHub Release (public loader only)

- Rebuild with: `OutOfOreModManager\Rebuild All.bat`  
- Publish **loader-only** kit (no gameplay mods):

```powershell
gh release create v1.1.0 "E:\SteamLibrary\steamapps\common\OutofOre\OutOfOreModManager\dist\OutOfOre-Modding-Kit-v1.1.0.zip" --repo tonyoo/out-of-ore-modding --title "v1.1.0" --notes "Loader only"
```

### Do not

- Commit game `.pak`, dumps, crash logs, or `UE4SS.log` (see `.gitignore`)  
- Finish a task with only game-folder edits and no push  

---

## 2. Environment (facts)

| Fact | Value |
|------|--------|
| Game root | `E:\SteamLibrary\steamapps\common\OutofOre` |
| Engine (shipping) | Unreal **4.27** |
| Mod runtime | **UE4SS** v3.0.1 Beta (confirmed working) |
| Inject proxy | `Binaries\Win64\dwmapi.dll` (file description: UE4SS Injection Proxy) |
| UE4SS home | `OutOfOre\Binaries\Win64\UE4SS\` |
| AI docs | `D:\OpenCode\Grok Out Of ore\` |

### How to know UE4SS is healthy

Check `UE4SS\UE4SS.log` after launch:

1. Early AOB scans may fail for a few seconds (normal)  
2. Then: `Found GUObjectArray` / `PS scan successful`  
3. `Starting Lua mod '...'` for each enabled mod  

If `dwmapi.dll` is missing or AV quarantines it, mods will not load.

---

## 3. Where the dumps are

**Do not guess.** Prefer these research files:

### Catalog / actors (Win64)

```
E:\SteamLibrary\steamapps\common\OutofOre\OutOfOre\Binaries\Win64\
  BP_Catalog.txt
  BP_Catalog.csv
  BP_Actors.txt
  BP_Detail_*.txt
  UUU_ObjectsDump.txt
```

### Full object dump (UE4SS)

```
...\UE4SS\UE4SS_ObjectDump.txt
...\UE4SS\UE4SS.log
```

### How dumps were produced

| Method | How |
|--------|-----|
| UE4SS built-in | In-game **Ctrl+J** object dump, **Ctrl+H** SDK, **Ctrl+Num7** actors, **Ctrl+Num6** usmap |
| BlueprintDumpMod | Console: `bpdump`, `bpdump_game`, `bpdump_detail <Class>`, `bpdump_actors` |
| UUU | Universal Unreal Unlocker (older file still present) |

**Always dump in a loaded world**, not only main menu (few BPs loaded at menu).

### What dumps give you

- Class full names / parents  
- UFunctions and UProperties (reflection)  

### What dumps do **not** give you

- Full Blueprint graphs (nodes/wires) → use **FModel** on the `.pak` if needed  

---

## 4. High-value classes (start here)

| Class | Path / name | Use for |
|-------|-------------|---------|
| Player controller | `/Game/Blueprints/PC_Standard.PC_Standard_C` | Money, purchase, sell, inventory, company role |
| Game state | `/Game/Blueprints/SchaktStateBase.SchaktStateBase_C` | Prices, fuel mult, skills, economy |
| Game mode | `/Game/Blueprints/GM_Schakt.GM_Schakt_C` | Session / dirt removed / buildings |
| Game instance | `/Game/Blueprints/GI_Schakt.GI_Schakt_C` | Saves, vehicle XML map |
| **Real machines** | `/Game/Vehicles/AVS_SuperVehicleBase.AVS_SuperVehicleBase_C` | What is actually in the world |
| AVS base | `/Game/Vehicles/AVS_Base.AVS_Base_C` | Parent of SuperVehicle |
| Vehicle plugin | `/VehicleSystemPlugin/AVS_Vehicle.AVS_Vehicle_C` | MaxSpeedLimit, gears, torque, throttle |
| Older vehicle BP | `/Game/Blueprints/BP_VehicleBase.BP_VehicleBase_C` | TopSpeedF etc. — **not always** the driven class |
| Dirt / bucket | `/Game/VehicleComponents/TerraformComponent.TerraformComponent_C` | Fill volume, cut/dump, weight |
| Store UI | `W_Menu_Store_C` | UI filters (heavier than PC hooks) |

Native packages of interest: `/Script/OutOfOre.*` (e.g. `SchaktPlayerController`, `SchaktInventoryComponent`).

---

## 5. How modding works on this game

### Primary: UE4SS Lua mods

```
...\UE4SS\Mods\<ModName>\
  Scripts\
    main.lua          required
    config.lua        optional
```

Enable:

```text
# mods.txt
MyMod : 1
```

Also add to `mods.json` for consistency.

### Patterns that work

1. **Property patching** with **original × multiplier** (cache originals by object address — **never stack**)  
2. **RegisterHook** on Blueprint/native UFunctions  
3. **RegisterConsoleCommandHandler** for reload/status  
4. **RegisterKeyBind**  
5. **NotifyOnNewObject** + delayed apply on spawn  
6. **LoopAsync** re-apply (only from originals)  

Helpers: `require("UEHelpers")` from `Mods\shared\UEHelpers\UEHelpers.lua`.

### Secondary: LogicMods / BP packs

- Folder: `Content\Paks\LogicMods\`  
- Loaded by `BPModLoaderMod`  
- Needs cooked `.pak` + usually UE 4.27 editor workflow  
- Prefer Lua for value tweaks and hooks  

### Offline research

- **FModel** on `OutOfOre-WindowsNoEditor.pak`  
- Optional `.usmap` from UE4SS (**Ctrl+Num6**)  

---

## 6. Existing custom mods (summary)

| Mod | Status | Config / commands |
|-----|--------|-------------------|
| **DirtCapacityMod** | Private gameplay | `dirtcap_*` — capacity + terrain + weight |
| **VehicleSpeedMod** | Private gameplay | `vehiclespeed_*` — props + gear scale |
| **BlueprintDumpMod** | Research | `bpdump_*` |
| **GpsAssistMod** | Private gameplay | `gpsassist_*` — GPS height/angle → blade keys |
| **StoreUnlockAll** | **Deleted** | Abandoned; do not restore |
| **RoleStoreMod** | **Deleted** | Do not restore |

Stock console enabler is on → in-game console works.

See `EXISTING_MODS.md` for details.

---

## 7. Creating a new mod (short recipe)

1. Research target class in dumps / Live View / `bpdump_detail`  
2. Scaffold:

```text
UE4SS\Mods\MyMod\Scripts\main.lua
UE4SS\Mods\MyMod\Scripts\config.lua   # optional
```

3. Enable in `mods.txt` + `mods.json`  
4. Implement with original-value cache  
5. Restart game (or ensure hot reload is on — default hot reload often off)  
6. Confirm log: `Starting Lua mod 'MyMod'`  
7. Test in-world  
8. Optional: pack with Mod Manager as `.ooomod`  

Full checklist: `MOD_RECIPES.md`.

---

## 8. Critical pitfalls (read before coding)

1. **Stacking multipliers** every tick/interval using *current* value → physics explode → storage/interact break. Always `cache[addr].original * mult`.  
2. **Wrong vehicle class:** world machines are **`AVS_SuperVehicleBase_C`**, not only `BP_VehicleBase_C`.  
3. **Player pawn ≠ vehicle:** character stays possessed; find vehicles via `FindAllOf` / controller fields / SuperVehicle.  
4. **Dirt capacity without weight fix:** full bucket won’t lift → scale `WeightModifier` **down** when capacity goes **up**.  
5. **Dirt capacity without terrain scale:** dig/dump still stock → scale cut/dump modifiers with capacity.  
6. **Throttle hooks** may fail to register early; gear array + property floors more reliable for AVS.  
7. **UE4SS GUI** can crash some sessions — keep external GUI off for distribution.  
8. **Restart game** after enable/disable/unpack.  

Full list: `PITFALLS.md`.

---

## 9. Tools for humans and AI

| Tool | Purpose |
|------|---------|
| **OutOfOreModManager.exe** | Enable/disable, pack/unpack mods (no Python for end users) |
| **Install Out of Ore Mods.exe** | Installs UE4SS + Manager into a game folder (kit) |
| **OutOfOre-Modding-Kit-v1.0.zip** | Shareable zip for friends |
| Desktop shortcuts | Manager, Installer, Rebuild Kit |

Friends need: **Game + UE4SS** (via installer kit). Manager EXE does not inject; UE4SS does.

See `TOOLS.md`.

---

## 10. Safety / do not

- Do not overwrite `OutOfOre-WindowsNoEditor.pak` for experiments  
- Prefer additive files under `UE4SS\` and `LogicMods\`  
- Do not ship live dumps/crash logs in distribution kits  
- Steam “Verify integrity” restores stock files if proxy/UE4SS breaks boot  

---

## 11. Useful console commands (custom)

### DirtCapacityMod

- `dirtcap_status` / `dirtcap_apply` / `dirtcap_preset double|huge|vanilla`  
- `dirtcap_reload` / `dirtcap_enable 0|1` / `dirtcap_reset`  

### VehicleSpeedMod

- `vehiclespeed_status` / `vehiclespeed_apply` / `vehiclespeed_preset sport|insane|vanilla`  
- `vehiclespeed_reload` / `vehiclespeed_enable 0|1` / `vehiclespeed_reset`  

### BlueprintDumpMod (if enabled)

- `bpdump_game` / `bpdump_detail ClassName` / `bpdump_actors` / `bpdump_help`  

### GpsAssistMod

- `gpsassist_status` / `gpsassist_probe` / `gpsassist_enable 0|1`  
- `gpsassist_axes height|angle|both` / `gpsassist_logonly 0|1`  
- `gpsassist_deadzone_height` / `gpsassist_deadzone_angle` / `gpsassist_reload`  

### Stock

- `dump_object <path>` (ConsoleCommandsMod)  

---

## 12. Suggested next mod targets (if user asks)

From dumps already taken:

- Sell prices: `SchaktStateBase` `CalculateSellPrice*`  
- Fuel: `FuelConsumptionMultiplier`, vehicle fuel props  
- Money: `PC_Standard` `EditMoney` / `PurchaseItem`  
- Store filters: `W_Menu_Store` or purchase hooks (RoleStore was removed)  

Always re-check live dumps; game updates may shift names.

---

## 13. Verification checklist for any change

- [ ] `UE4SS.log` shows mod started  
- [ ] No new crash dumps under `UE4SS\` after 5–10 min play  
- [ ] Storage containers still open  
- [ ] Target behavior confirmed in-world  
- [ ] Config reload command works if provided  
- [ ] Docs updated if new permanent paths/mods added  

---

*Last major session context: UE4SS verified, dumps produced, VehicleSpeed + DirtCapacity + Mod Manager/installer kit, RoleStore deleted, AI guide pack created at `D:\OpenCode\Grok Out Of ore`.*
