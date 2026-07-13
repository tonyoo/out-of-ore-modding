# Architecture notes (Out of Ore + UE4SS)

## Game packaging

- Shipping Unreal **4.27** build  
- Main cooked content: single large `OutOfOre-WindowsNoEditor.pak`  
- Project/internal name fragments: **Schakt** (e.g. `SchaktGameState`, `GM_Schakt`, `SchaktInventory`)  
- Voxel/terrain mining heavily used (VoxelPro plugin present under Plugins)

## Runtime mod injection

```
Game EXE (Win64)
  └─ loads dwmapi.dll (UE4SS proxy) from same folder
       └─ loads UE4SS\UE4SS.dll
            └─ scans AOBs, loads Mods from mods.txt
                 └─ runs each Mod\Scripts\main.lua
```

Working directory for dumps/logs is typically the `UE4SS` folder (case may appear as `ue4ss` in logs).

## Player / economy layer

```
PC_Standard_C  (Blueprint)
  parent: SchaktPlayerController (native /Script/OutOfOre)
  - Money, CompanyMoney, Company Role, Debt
  - PurchaseItem / ServerPurchaseItem
  - SellItem / SellItemDirect
  - Inventory, Store widgets, vehicles lists

SchaktStateBase_C  (GameState BP)
  parent: SchaktGameState
  - CalculateSellPrice / CalculatePurchasePrice*
  - FuelConsumptionMultiplier
  - Day/Night speed multipliers
  - Skills, debt, economy save/load

GI_Schakt_C  (GameInstance)
  - Saves, OptionsFuelConsumption, VehicleXmlMap
```

## Vehicles (critical distinction)

### What is actually driven in-world

Most live machines in actor dumps:

```
AVS_SuperVehicleBase_C
  parent: AVS_Base_C
    parent chain → AVS_Vehicle_C (VehicleSystemPlugin BP)
      parent: VehicleSystemBase (native plugin)
```

Relevant systems:

- **Gears:** `Gears`, `Gears_Reverse` arrays of `VehicleGear` (EndSpeed, MaxTorque, …)  
- **Limits:** `MaxSpeedLimit`, `DynamicMaxTorque`, `TargetAcceleration`  
- **Init from XML:** `InitializeGears`, `GetWheelVariablesFromXml`, `ModifiedXmlString`  
- **Fuel/inventory components** on SuperVehicle  

### BP_VehicleBase_C

- Separate hierarchy under `/Game/Blueprints/`  
- Has clear floats: `TopSpeedF/R`, `FuelConsumption`, `TransDirtAccSize`, dirt flags  
- **Do not assume** the player’s machine is this class  
- Still useful if instances exist or for shared naming  

### Player possession

Player often remains a character controller; vehicle is a separate actor.  
`UEHelpers.GetPlayer()` may **not** return the machine.  
Find vehicles with `FindAllOf("AVS_SuperVehicleBase_C")` or controller fields like `NewVehiclePawn`.

## Dirt / terraforming

```
TerraformComponent_C  (on machines)
  Capacity:
    TotalFillVolumeM3
    TotalFillVolumeM3Modifier
    DirtAcc
    DozerBuffertAmount Dm 3
  Terrain:
    DirtToWorldModifier
    CutBoxModifier, CutBulk, LinearModifier
    VoxelToBulkMultiplier, VoxelToOreMultiplier
    DumpAmountStart/End, Sphere Cut Radius, BladeSize, …
  Weight:
    WeightModifier
    ActualFillVolumeM3 / ActualWeightBeforeUnits (runtime — don’t stack-multiply as capacity)
  Function:
    SetMaxCapacity (optional)
```

Raising capacity without lowering weight density → **cannot lift full bucket**.  
Raising capacity without terrain scale → **dig/dump feels stock**.

## Inventory / containers

- `SchaktInventoryComponent`: `MaxSize`, fuel max, production sizes  
- Building: `BP_Container_C`, `BP_SchaktContainerCrate_C`  
- Broken storage open was observed after **vehicle torque stacking**, not after RoleStore  

## Store / UI

- Logic: often `PC_Standard` purchase/sell  
- UI: `W_Menu_Store_C` (`ShouldShowItemInCurrentStore`, `CheckRole`, cart)  
- Item wrapper: `BP_StoreItemObject_C`  

## Mod load order

Controlled by `UE4SS\Mods\mods.txt`.  
Keybinds entry must stay near bottom (UE4SS comment: do not move Keybinds up).

Example of a known-good style list:

```text
ConsoleCommandsMod : 1
ConsoleEnablerMod : 1
BPML_GenericFunctions : 1
BPModLoaderMod : 1
Keybinds : 1
VehicleSpeedMod : 1
DirtCapacityMod : 1
```

## Distribution architecture

```
Friend's PC
  Install Out of Ore Mods.exe
    → copies dwmapi + clean UE4SS into game Win64
    → copies OutOfOreModManager.exe
    → optional StarterCustomMods.ooomod
  OutOfOreModManager.exe
    → enable/disable, pack/unpack .ooomod
  Game launch
    → UE4SS injects and runs Lua
```
