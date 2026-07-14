# Out of Ore Modding (public — loader only)

UE4SS install helpers and a desktop **Mod Manager** for [Out of Ore](https://store.steampowered.com/app/1304930/Out_of_Ore/).

**This repository does not ship gameplay mods** (dirt capacity, vehicle speed, etc.).  
Those are in a **private** repo: [`out-of-ore-gameplay-mods`](https://github.com/tonyoo/out-of-ore-gameplay-mods).

## For players

1. Install **Out of Ore** from Steam (launch once).  
2. Download the latest **Release**:  
   **https://github.com/tonyoo/out-of-ore-modding/releases/latest**  
   (asset: `OutOfOre-Modding-Kit-v1.1.0.zip`)  
3. Run **`Install Out of Ore Mods.exe`**  
4. Select `...\steamapps\common\OutofOre`  
5. Install → open **Out of Ore Mod Manager** → launch game  

No Python required for end users.

### What the kit installs

| Component | Purpose |
|-----------|---------|
| UE4SS | Runtime that loads Lua mods |
| OutOfOreModManager.exe | Enable/disable mods, pack/unpack `.ooomod` |
| Stock UE4SS tools | Console enabler, keybinds, BPModLoader, etc. |

**Not included:** DirtCapacityMod, VehicleSpeedMod, BlueprintDumpMod.

## For developers

| Path | Contents |
|------|----------|
| `tools/mod-manager/` | Manager source + `build_exe.bat` + **`Rebuild All.bat`** |
| `tools/installer/` | Installer source + `assemble_kit.ps1` |
| `docs/` | AI/human handoff guides |
| `mods/` | Empty on purpose (loader-only) |

### Rebuild manager + installer + kit

From the live tools folder (game drive):

```text
E:\SteamLibrary\steamapps\common\OutofOre\OutOfOreModManager\Rebuild All.bat
```

Or copy that bat into this repo’s `tools/` and run after adjusting paths.

Steps inside the bat:

1. PyInstaller → `OutOfOreModManager.exe`  
2. PyInstaller → `Install Out of Ore Mods.exe`  
3. `assemble_kit.ps1` → loader-only zip (no gameplay packs)  

### Standing rule

After changes: commit + `git push origin main`.  
New player-facing kit: also publish a GitHub Release with the zip.

## Related

| Repo | Visibility | Contents |
|------|------------|----------|
| [tonyoo/out-of-ore-modding](https://github.com/tonyoo/out-of-ore-modding) | **Public** | Loader, manager, installer |
| [tonyoo/out-of-ore-gameplay-mods](https://github.com/tonyoo/out-of-ore-gameplay-mods) | **Private** | Dirt / speed / dump mods |

## License

- Tools in this repo: MIT — see `LICENSE`  
- UE4SS in release kits: MIT — [UE4SS-RE/RE-UE4SS](https://github.com/UE4SS-RE/RE-UE4SS)  

Game files are not included.
