# Absolute paths inventory

All paths are on the user’s Windows machine unless noted.

## Game

| Item | Path |
|------|------|
| Game root | `E:\SteamLibrary\steamapps\common\OutofOre` |
| Content project folder | `E:\SteamLibrary\steamapps\common\OutofOre\OutOfOre` |
| Shipping EXE | `E:\SteamLibrary\steamapps\common\OutofOre\OutOfOre\Binaries\Win64\OutOfOre-Win64-Shipping.exe` |
| Win64 binaries | `E:\SteamLibrary\steamapps\common\OutofOre\OutOfOre\Binaries\Win64` |
| Main pak | `E:\SteamLibrary\steamapps\common\OutofOre\OutOfOre\Content\Paks\OutOfOre-WindowsNoEditor.pak` |
| Pak sig | `E:\SteamLibrary\steamapps\common\OutofOre\OutOfOre\Content\Paks\OutOfOre-WindowsNoEditor.sig` |
| LogicMods (BPModLoader) | `E:\SteamLibrary\steamapps\common\OutofOre\OutOfOre\Content\Paks\LogicMods` |

## UE4SS

| Item | Path |
|------|------|
| UE4SS folder | `E:\SteamLibrary\steamapps\common\OutofOre\OutOfOre\Binaries\Win64\UE4SS` |
| Proxy DLL (inject) | `E:\SteamLibrary\steamapps\common\OutofOre\OutOfOre\Binaries\Win64\dwmapi.dll` |
| Core DLL | `...\UE4SS\UE4SS.dll` |
| Settings | `...\UE4SS\UE4SS-settings.ini` |
| Log | `...\UE4SS\UE4SS.log` |
| Mods root | `...\UE4SS\Mods` |
| Mod list | `...\UE4SS\Mods\mods.txt` |
| Mod list JSON | `...\UE4SS\Mods\mods.json` |
| Shared Lua helpers | `...\UE4SS\Mods\shared\UEHelpers\UEHelpers.lua` |

### Settings that matter

- Engine override: **MajorVersion = 4**, **MinorVersion = 27**
- `bUseUObjectArrayCache = false` (stability)
- Prefer `GuiConsoleEnabled = 0` for others (GUI can crash)
- In-game console via ConsoleEnablerMod: **`~`** or **`F10`**

## Research dumps (do not delete casually)

### Under Win64

| File | Path |
|------|------|
| BP catalog (text) | `...\Binaries\Win64\BP_Catalog.txt` |
| BP catalog (CSV) | `...\Binaries\Win64\BP_Catalog.csv` |
| Live actors dump | `...\Binaries\Win64\BP_Actors.txt` |
| UUU object dump | `...\Binaries\Win64\UUU_ObjectsDump.txt` (~28 MB) |
| Detail dumps | `...\Binaries\Win64\BP_Detail_*.txt` |

### Detail dumps present

```
BP_Detail_AVS_Vehicle_C.txt
BP_Detail_BFL_Vehicle_C.txt
BP_Detail_BP_SellPlace_C.txt
BP_Detail_BP_SellPointComponent_C.txt
BP_Detail_BP_SellPointManager_C.txt
BP_Detail_BP_StoreItemObject_C.txt
BP_Detail_BP_VehicleBase_C.txt
BP_Detail_GI_Schakt_C.txt
BP_Detail_GM_Schakt_C.txt
BP_Detail_PC_Standard_C.txt
BP_Detail_SchaktStateBase_C.txt
BP_Detail_W_Menu_Store_C.txt
BP_Detail_W_SellPanel_C.txt
```

### Under UE4SS

| File | Path |
|------|------|
| Full object dump | `...\UE4SS\UE4SS_ObjectDump.txt` (~70 MB) |
| Log | `...\UE4SS\UE4SS.log` |
| Local notes | `...\UE4SS\MODDING_NOTES.md`, `MODS_STATUS.txt` |

## Custom mods (Lua)

Base: `...\UE4SS\Mods\`

| Mod folder | Typical role |
|------------|----------------|
| `VehicleSpeedMod` | Speed / gears |
| `DirtCapacityMod` | Bucket capacity + terrain + weight |
| `BlueprintDumpMod` | Runtime BP dumps |
| `RoleStoreMod` | **Removed** (do not recreate unless asked) |

Stock UE4SS (keep):  
`ConsoleEnablerMod`, `ConsoleCommandsMod`, `Keybinds`, `BPModLoaderMod`, `BPML_GenericFunctions`, `CheatManagerEnablerMod`, `shared`, etc.

## Tools / distribution

| Item | Path |
|------|------|
| Mod Manager root | `E:\SteamLibrary\steamapps\common\OutofOre\OutOfOreModManager` |
| Manager EXE | `...\OutOfOreModManager\OutOfOreModManager.exe` |
| Manager source | `...\OutOfOreModManager\ooo_mod_manager.py` |
| Installer source | `...\OutOfOreModManager\ooo_mod_installer.py` |
| Share kit zip | `...\OutOfOreModManager\dist\OutOfOre-Modding-Kit-v1.0.zip` |
| Kit folder | `...\OutOfOreModManager\dist\OutOfOre-Modding-Kit-v1.0\` |
| Rebuild kit | `...\OutOfOreModManager\Rebuild Kit.bat` |
| Assemble script | `...\OutOfOreModManager\assemble_kit.ps1` |

## This documentation pack

| Item | Path |
|------|------|
| AI handoff root | `D:\OpenCode\Grok Out Of ore` |

## Desktop shortcuts (user machine)

- Out of Ore Mod Manager  
- Install Out of Ore Mods  
- Rebuild Out of Ore Modding Kit  
