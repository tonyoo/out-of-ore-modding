# MiniMapMod

HUD mini-map for Out of Ore. Uses the game’s own map capture (`W_Element_MapImage` + `Map_Component`). Requires **UE4SS** (this repo’s loader kit).

## Install

1. Install the [Out of Ore Modding Kit](https://github.com/tonyoo/out-of-ore-modding/releases/latest).
2. Unpack this pack with **Out of Ore Mod Manager**, or copy the `MiniMapMod` folder to:

   `OutOfOre\Binaries\Win64\UE4SS\Mods\MiniMapMod`

3. Enable `MiniMapMod : 1` in `UE4SS\Mods\mods.txt`.
4. Restart the game, load a world.

## Config

Edit `Scripts\config.lua` then `minimap_reload` or restart.

| Key | Meaning |
|-----|---------|
| `size_px` | Square size |
| `corner` | `bottom_right` / `bottom_left` / `top_right` / `top_left` |
| `padding_px` | Gap from those edges |
| `offset_x` / `offset_y` | Extra pixels (`+x` right, `+y` down) |
| `zoom` | 0.05 far … 1 close |
| `zoom_step` | Amount per zoom hotkey |

## Controls

| Input | Action |
|-------|--------|
| **Ctrl+Shift+Up / Down** | Zoom in / out |
| `minimap_pos <x> <y>` | Move (offsets) |
| `minimap_zoom_step <n>` | Hotkey zoom amount |
| `minimap_enable 0\|1` | Hide / show |
| `minimap_help` | Command list |

## Notes

- Do **not** install Palworld `DekBasicMinimap` into `LogicMods`.
- Restart after first install so Lua loads.
