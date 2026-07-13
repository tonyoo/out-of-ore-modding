# Out of Ore Mod Manager

Desktop GUI for managing **UE4SS Lua mods** for Out of Ore.

## Features

| Feature | Description |
|---------|-------------|
| **List mods** | Shows everything under `OutOfOre\Binaries\Win64\UE4SS\Mods` |
| **Enable / Disable** | Writes `mods.txt` and `mods.json` |
| **Double-click** | Toggle a mod on/off |
| **Pack** | Bundle selected mods into a `.ooomod` zip pack |
| **Unpack** | Install a `.ooomod` / `.zip` pack into the game |
| **Delete** | Remove mod folders (careful with stock UE4SS mods) |
| **Launch game** | Starts `OutOfOre-Win64-Shipping.exe` |

## Run

Double-click:

```text
Launch Mod Manager.bat
```

Or:

```text
python ooo_mod_manager.py
```

## Pack format (`.ooomod`)

A zip archive with:

```text
manifest.json
README.txt
mods/
  YourMod/
    Scripts/
      main.lua
      config.lua
  AnotherMod/
    ...
```

`manifest.json` example:

```json
{
  "format": "outofore-modpack",
  "format_version": 1,
  "name": "My Dirt Mods",
  "author": "you",
  "description": "Bigger buckets",
  "mods": [
    { "name": "DirtCapacityMod", "enabled": true }
  ]
}
```

Packs are saved under `OutOfOreModManager\packs\` by default.

## Notes

- **In-game ImGui mod menus** are limited under pure UE4SS Lua; this external app is the reliable GUI.
- After enable/disable/unpack, **restart Out of Ore** so UE4SS reloads mods.
- Stock mods (`ConsoleEnablerMod`, `Keybinds`, `BPModLoaderMod`, …) are labeled **stock**.
- Your custom mods: `DirtCapacityMod`, `VehicleSpeedMod`, `BlueprintDumpMod`, etc.

## Paths

Manager auto-detects:

```text
...\steamapps\common\OutofOre\
  OutOfOre\
    Binaries\Win64\UE4SS\Mods\
  OutOfOreModManager\          ← this tool
    ooo_mod_manager.py
    Launch Mod Manager.bat
    packs\
```
