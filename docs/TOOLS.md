# Tools — Mod Manager, installer, packaging

## Mod Manager (day-to-day)

| Item | Path |
|------|------|
| Folder | `E:\SteamLibrary\steamapps\common\OutofOre\OutOfOreModManager\` |
| EXE (no Python) | `OutOfOreModManager.exe` |
| Python source | `ooo_mod_manager.py` |
| Dev launch | `Launch Mod Manager.bat` |
| Desktop shortcut | **Out of Ore Mod Manager** |

### Features

- List mods under `UE4SS\Mods`  
- Enable / disable → writes `mods.txt` + `mods.json`  
- Double-click toggle  
- **Pack** selected mods → `.ooomod`  
- **Unpack** `.ooomod` / `.zip` into Mods  
- Delete mod folders  
- Launch game  

### Pack format `.ooomod`

Zip containing:

```text
manifest.json
README.txt          # optional
mods/
  ModName/
    Scripts/...
```

`manifest.json`:

```json
{
  "format": "outofore-modpack",
  "format_version": 1,
  "name": "Display Name",
  "author": "",
  "description": "",
  "mods": [
    { "name": "DirtCapacityMod", "enabled": true }
  ]
}
```

---

## Installer kit (for other people)

| Item | Path |
|------|------|
| Share zip | `...\OutOfOreModManager\dist\OutOfOre-Modding-Kit-v1.0.zip` |
| Kit folder | `...\dist\OutOfOre-Modding-Kit-v1.0\` |
| Installer EXE | `Install Out of Ore Mods.exe` (must sit next to `payload\`) |
| Desktop shortcut | **Install Out of Ore Mods** |

### Kit payload

```text
payload\
  dwmapi.dll
  UE4SS\                 # clean stock + settings
  ModManager\
    OutOfOreModManager.exe
    packs\
  Optional\
    StarterCustomMods.ooomod
```

### Friend install steps

1. Own Out of Ore on Steam  
2. Run **Install Out of Ore Mods.exe**  
3. Select `...\steamapps\common\OutofOre`  
4. Install UE4SS + Manager (+ optional starter pack)  
5. Launch game; verify `UE4SS.log`  

**Friends do not need Python.**

What the installer does **not** replace: they still need the game itself.

---

## Rebuild kit (maintainer only)

Requires Python + PyInstaller on this machine.

| Item | Path |
|------|------|
| Build manager EXE | `build_exe.bat` |
| Build installer EXE | `build_installer_exe.bat` |
| Assemble zip | `assemble_kit.ps1` |
| One-click | `Rebuild Kit.bat` + desktop **Rebuild Out of Ore Modding Kit** |

```text
cd E:\SteamLibrary\steamapps\common\OutofOre\OutOfOreModManager
Rebuild Kit.bat
```

Output: `dist\OutOfOre-Modding-Kit-v1.0.zip`

---

## UE4SS built-in tools (in-game)

| Hotkey | Action |
|--------|--------|
| Ctrl+J | Dump all objects |
| Ctrl+H | C++ SDK headers |
| Ctrl+Num9 | UHT headers |
| Ctrl+Num7 | Dump actors |
| Ctrl+Num6 | Dump usmap |

Console (ConsoleEnablerMod): `dump_object <path>`

---

## Offline asset tools (optional)

| Tool | Use |
|------|-----|
| FModel | Browse/extract `OutOfOre-WindowsNoEditor.pak` |
| UAssetGUI | Inspect single assets |
| Unreal 4.27 | Cook LogicMods BP packs (advanced) |

---

## AI notes when using tools

- Prefer editing files under `UE4SS\Mods\` over reinstalling the whole kit  
- After Manager enable/disable: tell user to **restart the game**  
- When packaging for others: run assemble kit so dumps/logs are not shipped  
- Manager `app_dir()` uses `sys.executable` parent when frozen as EXE  
