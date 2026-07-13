# Pitfalls and incident history

Read this before implementing vehicle, dirt, or aggressive hooks.

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

## Recovery checklist

1. Disable suspect mod (`: 0` or `enable 0`)  
2. Restart game  
3. If world broken: older save  
4. Last resort: remove `dwmapi.dll`, Steam verify, reinstall UE4SS from kit  
