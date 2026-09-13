# Pitfalls and incident history

Read this before implementing vehicle, dirt, HUD overlays, or aggressive hooks.

---

## 1. Multiplier stacking (CRITICAL)

**Symptom:** Game unstable; storage containers won’t open; physics broken; crash dumps under `UE4SS\`.

**Cause:** Applying `prop = prop * mult` every interval/tick so values grow exponentially (especially torque).

**Fix rule:**

```text
On first see object → store original[prop]
Always set → prop = original[prop] * mult
Never use current prop as the base for the next multiply
```

**Also avoid:** EngineSimluation hooks that do `Torque = Torque * mult` every frame.

---

## 2. Wrong vehicle type

**Symptom:** `vehicles found: 0` or props write “ok” but no speed feel; only 0 useful targets.

**Cause:** Searching only `BP_VehicleBase_C`. Live machines are usually:

```text
AVS_SuperVehicleBase_C
```

**Fix:** Target SuperVehicle / AVS_Vehicle / gear arrays; use actor dumps to confirm.

---

## 3. Player is not the machine

**Symptom:** Status says “not in a BP_VehicleBase pawn” while driving.

**Cause:** Possession model leaves character as pawn; vehicle is separate.

**Fix:** Don’t rely only on `UEHelpers.GetPlayer()`. Use FindAllOf / `NewVehiclePawn` / world actors.

---

## 4. Property writes succeed but gameplay ignores them

**Symptom:** Log shows `24 ok, 0 failed writes` but speed unchanged.

**Cause:** MaxSpeedLimit etc. may be 0 or not the sim authority; gears/XML drive motion.

**Fix:** Scale `Gears` / `Gears_Reverse` (`EndSpeed`, `MaxTorque`); use absolute floors when original is 0; re-apply after `InitializeGears`.

---

## 5. Dirt capacity vs lift

**Symptom:** Bigger bucket fills more but arm won’t raise when full.

**Cause:** More volume → more weight; or `WeightModifier` was scaled **up** with capacity.

**Fix:** When increasing capacity, scale `WeightModifier` **down** (e.g. `1/capacity`) so full-bucket mass stays similar.

---

## 6. Dirt capacity vs terrain

**Symptom:** Bucket holds more but dig/dump still “stock” amounts.

**Cause:** Only volume fields changed; cut/dump modifiers unchanged.

**Fix:** Scale terrain fields with capacity (`DirtToWorldModifier`, `CutBoxModifier`, `CutBulk`, dump amounts, voxel multipliers, etc.).

---

## 7. enabled=false / mods.txt : 0

**Symptom:** “Mod not working” but log says Loaded with `enabled=false` or `Mod 'X' disabled in mods.txt`.

**Fix:** Check both `config.lua` `enabled` **and** `mods.txt` / `mods.json`.

---

## 8. Main menu research

**Symptom:** Empty catalogs / 0 components.

**Cause:** Assets not loaded.

**Fix:** Load a save/world before dump or status.

---

## 9. UE4SS GUI crashes

**Symptom:** Crash dumps; instability with GuiConsole on.

**Fix:** Distribution settings: `GuiConsoleEnabled = 0`, `GuiConsoleVisible = 0`. Use in-game console instead.

---

## 10. RegisterHook failures at startup

**Symptom:** Log: unable to register hook / UFunction not found.

**Cause:** Class not loaded yet or path wrong.

**Fix:** Retry after map load; use property apply loops; verify path in detail dump.

---

## 11. Antivirus / proxy

**Symptom:** Mods never load; no UE4SS.log updates.

**Cause:** `dwmapi.dll` removed/quarantined.

**Fix:** Restore proxy; whitelist game Win64 folder.

---

## 12. Shipping kits with live data

**Symptom:** Huge zips; privacy noise; bad defaults.

**Fix:** `assemble_kit.ps1` builds **clean** UE4SS (no logs, dumps, crash dumps).

---

## 13. Palworld LogicMods on Out of Ore (CRITICAL)

**Symptom:** Pak does not load, or Fatal on start.

**Cause:** Packs like `DekBasicMinimap_P.pak` are **Palworld / UE5**. Out of Ore is **UE 4.27**.

**Fix:** Never copy foreign-game LogicMods into `Content\Paks\LogicMods`. For a mini-map, Lua + stock `W_Element_MapImage` / `Map_Component`.

---

## 14. Lua `obj:Method` without `()` (mod never loads)

**Symptom:** Console `command not recognized`; `UE4SS.log`: `function arguments expected near 'if'`.

**Cause:** `pc:GetComponentByClass` is a **call**. Without `()` Lua treats the next `if` as an argument.

**Fix:** Do not store methods with `:`. Use `obj.Method` or `obj:Method(args)`. A syntax error in `main.lua` aborts **before** `RegisterConsoleCommandHandler`.

---

## 15. `RegisterKeyBind` 2-arg form Fatals (CRITICAL)

**Symptom:** Overlay works; pressing Numpad+/− or PageUp → **Fatal error**.

**Cause:** `RegisterKeyBind(Key.ADD, function)` (two arguments). Working mods use **three**:

```lua
RegisterKeyBind(Key.UP_ARROW, { ModifierKey.CONTROL, ModifierKey.SHIFT }, fn)
```

**Fix:** Never use the 2-arg form. Do not bind `Key.ADD` / `OEM_PLUS` unless proven. MiniMap zoom is **Ctrl+Shift+Up/Down**.

---

## 16. Lua tables are not `TArray` (CRITICAL)

**Symptom:** Fatal a few seconds after the mini-map appears. Dump may mention `SetMapCaptureHiddenActors`.

**Cause:** `cap:SetMapCaptureHiddenActors({ pawn })` or `sc.HiddenActors = { pawn }`. UE4SS does not marshal a Lua table into `TArray<AActor*>`.

**Fix:** Do not pass Lua `{ }` as Blueprint array args. Let `HandleMapOpened` own capture hiding.

---

## 17. `LoopAsync` is not the game thread (CRITICAL)

**Symptom:** Fatal during play; or `[UE4SS.EngineTick] Ref was not function` and the overlay never rebuilds.

**Cause:**

- `CaptureNow` / `AddToViewport` / `CreateWidget` from `LoopAsync` (async thread)
- `ExecuteInGameThread(function() ... end)` **every pulse** — the anonymous fn is GC’d and EngineTick dies

**Fix:** One **stable** local `GameTick`, queue it:

```lua
local pending = false
local function GameTick()
    pending = false
    pcall(Tick)  -- all UObject work here
end
LoopAsync(ms, function()
    if pending then return false end
    pending = true
    ExecuteInGameThread(GameTick)
    return false
end)
```

Wait for `PC_Standard` + live `W_HUD` before `CreateWidget` (main menu / loading widgets die).

---

## 18. Mini-map widget tree (visibility / gray bar)

**Symptom:** Gray slider column; or hiding “chrome” deletes the whole map.

**Cause:** `W_Element_MapImage` is the **tablet map**, not a HUD square.

- **BindWidgets** (work with `widget.Image_Map`): `Image_Map`, `Canvas_MapViewport`, `MapZoomSlider`, `Image_256`, `PlayerIconCanvas`, `Canvas_MapMarkers`, …
- **WidgetTree-only** (`Named()` returns MISSING): `CanvasPanelRoot`, `Border`, `SizeBox_98` — find via `Canvas_MapViewport:GetParent()` / `GetChildAt`
- Collapsing **`Border`** or **`SizeBox_98` by guess** hid the map when they wrapped it. Live dump: map chain is `Image_Map` → `Canvas_MapContent` → `Canvas_MapViewport` → `CanvasPanelRoot`. SizeBox is a **sibling**, not an ancestor — then it is safe to collapse via children walk.
- SOS is `Marker_Rescue` / `Image_Rescue` on `PlayerIconCanvas`
- Overhead **scene capture** draws the 3D pawn from above (looks “fallen apart”). Tablet uses `W_MapMarker_Player` and hides the pawn from capture — do not fake that with a Lua `TArray`

**Fix:** `minimap_dump` logs vis + parent. Hide slider/`Image_256` only; keep `Image_Map` ancestors; walk root children for SizeBox.

Parent overlay to **`W_HUD.ConstantHud`** using the **slot `AddChild` returns**. `AddToViewport` from Lua often creates an object that never paints.

Do not `CreateWidget` extra `W_Element_Button` / `SetButtonContent` (Fatal).

---

## 19. ShowingCursor is not “tablet open”

**Symptom:** Mini-map created then immediately `Paused: tablet open`.

**Cause:** Console / cursor sets `ShowingCursor`. Auto-hide treated that as the tablet.

**Fix:** Don’t hide on cursor. If needed, use `W_InGameMenu.VisibleBackground`. MiniMapMod does not auto-hide.

---

## 20. Flooring auto MaxSpeedLimit (vehicles)

**Symptom:** Grader surge; excavator superspeed; roller oscillation.

**Cause:** Writing `MaxSpeedLimit = 80` (or similar) when XML/gears use **auto** (0 / negative).

**Fix:** Skip auto cap writes; scale gears only. Do not stack speed mods. **VehicleTuneMod is abandoned; do not restore.**

---

## Recovery checklist

1. Disable suspect mod (`: 0` or `enable 0`)  
2. Restart game  
3. If world broken: older save  
4. Last resort: remove `dwmapi.dll`, Steam verify, reinstall UE4SS from kit v1.2.0  

