# Existing mods (status)

Live install: `E:\SteamLibrary\steamapps\common\OutofOre\OutOfOre\Binaries\Win64\UE4SS\Mods\`

Always re-read live `mods.txt` — it changes.

---

## Public (this repo)

### MiniMapMod ✅

| | |
|--|--|
| Path | `mods/MiniMapMod` (this repo) / live `UE4SS\Mods\MiniMapMod` / private clone |
| Config | `Scripts/config.lua` → `MiniMapConfig` |
| Goal | HUD mini-map using the game’s own capture (`W_Element_MapImage` + `Map_Component` + `BP_MapCaptureActor`) |
| Kit | **v1.2.0** optional payload (`payload/Optional/MiniMapMod.ooomod`) |

**Do not** drop Palworld `DekBasicMinimap_P.pak` into `Content\Paks\LogicMods` (UE5 Palworld pack; will not load on 4.27).

**Install (players):** kit installer checkbox **Install MiniMapMod**, or Mod Manager → Unpack `packs\MiniMapMod.ooomod`. Release: https://github.com/tonyoo/out-of-ore-modding/releases/tag/v1.2.0

**Commands:** `minimap`, `minimap_enable 0|1`, `minimap_size`, `minimap_pos`, `minimap_corner`, `minimap_zoom`, `minimap_zoom_step`, `minimap_zoom_in`, `minimap_zoom_out`, `minimap_dump`, `minimap_reload`, `minimap_help`

**Zoom keys:** Ctrl+Shift+Up / Ctrl+Shift+Down (same 3-arg `RegisterKeyBind` style as VehicleScaleMod)

**Config:** `size_px`, `corner`, `padding_px`, `offset_x` / `offset_y` (+x right, +y down), `zoom`, `zoom_step`

**What the overlay draws (live dump):**

- **Visible map:** `Canvas_MapViewport` → `Canvas_MapContent` → `Image_Map` (+ `PlayerIconCanvas`, `Canvas_MapMarkers`)
- **Hidden chrome:** `MapZoomSlider`, `Image_256`, `W_Element_Button_Center`, SOS `Marker_Rescue` / `Image_Rescue`
- **WidgetTree-only (not BindWidgets):** `CanvasPanelRoot`, `Border`, `SizeBox_98` — look up via `GetParent()` / `GetChildAt`, not `widget.Border`

Parent the overlay to `W_HUD.ConstantHud` with the **slot returned by `AddChild`**. Wait for `PC_Standard` + `W_HUD` (not main menu). Tick UObject work on the **game thread**. See `PITFALLS.md` §13–18.

---

## Private (not in this loader)

**Repo:** https://github.com/tonyoo/out-of-ore-gameplay-mods  
**Local:** `D:\OpenCode\out-of-ore-gameplay-mods`

| Mod | Role |
|-----|------|
| VehicleSpeedMod | Speed / gears (do not floor auto MaxSpeedLimit to 80) |
| VehicleScaleMod | Scale |
| DevMenuMod | Unhide tablet Dev / Building XML / Terraform tab |
| BlueprintDumpMod | Runtime BP dumps |

**Abandoned (do not restore as active):** GpsAssistMod — sources stay on GitHub, do not delete.  
**Do not recreate** DirtCapacityMod, VehicleTuneMod, RoleStoreMod, or StoreUnlockAll.

Dev Menu: tablet **I**; commands `devmenu`, `devmenu_building`, `devmenu_terraform`. Terraform tab is vehicle XML DigComp (CanCut, cutbox, …), not world paint. Saving XML from Dev can persist broken machines.

---

## Stock UE4SS (keep)

`ConsoleCommandsMod`, `ConsoleEnablerMod`, `BPML_GenericFunctions`, `BPModLoaderMod`, `Keybinds` (keep near bottom of `mods.txt`), `shared`.
