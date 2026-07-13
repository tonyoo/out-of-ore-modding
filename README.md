# Out of Ore Modding

UE4SS Lua mods, desktop **Mod Manager**, and a one-click **installer kit** for [Out of Ore](https://store.steampowered.com/app/1304930/Out_of_Ore/).

## For players (friends)

1. Install **Out of Ore** from Steam (launch once).  
2. Download the latest **Release** zip:  
   **https://github.com/tonyoo/out-of-ore-modding/releases/latest**  
   (asset: `OutOfOre-Modding-Kit-v1.0.zip`)
3. Run **`Install Out of Ore Mods.exe`**  
4. Point it at `...\steamapps\common\OutofOre`  
5. Open **Out of Ore Mod Manager** → manage/pack/unpack mods  
6. Launch the game  

No Python required for end users.

## For developers / AI

| Path | Contents |
|------|----------|
| `mods/` | Custom Lua mods (source of truth) |
| `tools/mod-manager/` | Mod Manager Python app + EXE build |
| `tools/installer/` | Installer + kit assembly scripts |
| `docs/` | Full AI/human handoff guide |
| `scripts/deploy_to_game.ps1` | Copy `mods/` → live game `UE4SS\Mods` |

**AI session start:** read `docs/AI_MODDING_GUIDE.md` and `docs/PATHS.md`.

```powershell
# Deploy mods from this repo into your game install
.\scripts\deploy_to_game.ps1
```

## Repo layout

```text
out-of-ore-modding/
  mods/                 DirtCapacityMod, VehicleSpeedMod, BlueprintDumpMod
  tools/mod-manager/    ooo_mod_manager.py, build_exe.bat
  tools/installer/      ooo_mod_installer.py, assemble_kit.ps1
  docs/                 AI handoff documentation
  scripts/              deploy helpers
  vendor/               notes on UE4SS payload (binaries via Releases only)
```

## Build release kit (maintainer)

Requires Python 3 + PyInstaller on Windows.

```powershell
cd tools\mod-manager
.\build_exe.bat
cd ..\installer
.\build_installer_exe.bat
# Adapt assemble_kit.ps1 paths or run from original OutOfOreModManager until ported
```

Publish:

```powershell
gh release create v1.0.0 releases/OutOfOre-Modding-Kit-v1.0.zip --title "v1.0.0" --notes "UE4SS + Mod Manager + starter mods"
```

## License

- **This repository** (mods + tools): MIT — see `LICENSE`  
- **UE4SS** (bundled in release kits): MIT — [UE4SS-RE/RE-UE4SS](https://github.com/UE4SS-RE/RE-UE4SS)  

Out of Ore game files are **not** included and must not be redistributed.

## Disclaimer

Unofficial fan tools. Not affiliated with the game developers. Use at your own risk; keep Steam backups. Antivirus may flag injection proxy / PyInstaller EXEs.
