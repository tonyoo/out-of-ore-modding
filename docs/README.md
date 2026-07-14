# Out of Ore — AI / Human Modding Handoff Pack

**Purpose:** Give a new AI (or human) everything needed to continue modding *Out of Ore* without rediscovering paths, dumps, tools, or past mistakes.

## Read order (for AI)

1. **`AI_MODDING_GUIDE.md`** ← read this first (master handoff)  
2. **`PATHS.md`** ← absolute paths inventory  
3. **`PITFALLS.md`** ← before changing vehicle/dirt/hooks  
4. **`EXISTING_MODS.md`**, **`MOD_RECIPES.md`**, **`ARCHITECTURE.md`**, **`TOOLS.md`** as needed  

## Session start prompt (paste into a new chat)

```text
Read D:\OpenCode\Grok Out Of ore\AI_MODDING_GUIDE.md and PATHS.md first.
You are helping mod Out of Ore with UE4SS Lua.
Game root: E:\SteamLibrary\steamapps\common\OutofOre
Git monorepo: D:\OpenCode\out-of-ore-modding (GitHub: tonyoo/out-of-ore-modding)
Follow PATHS, EXISTING_MODS, and PITFALLS before changing anything.
Do not re-multiply live property values every tick (stacking). Prefer original×multiplier caches.
Machines are mostly AVS_SuperVehicleBase, not BP_VehicleBase.
AFTER EVERY CHANGE: sync files into the monorepo, commit, and git push origin main.
```

## Standing rule: always update GitHub

**After every mod, tool, or docs change**, the AI (or human) must:

1. Sync live game mods → `D:\OpenCode\out-of-ore-modding\mods\` (if game copies were edited)
2. Sync docs → `D:\OpenCode\out-of-ore-modding\docs\` if handoff docs changed
3. `cd D:\OpenCode\out-of-ore-modding`
4. `git add -A` → `git commit -m "..."` → `git push origin main`

Optional: new **Release** only when shipping a rebuilt kit zip for friends (not every small tweak).

## Quick facts

| Item | Value |
|------|--------|
| Game | Out of Ore (Steam) |
| Engine | Unreal **4.27** (UE4SS override) |
| Mod runtime | **UE4SS** v3.0.1 Beta (working) |
| Primary mod type | Lua under `UE4SS\Mods\<Name>\Scripts\` |
| Docs home | `D:\OpenCode\Grok Out Of ore\` |
| Game home | `E:\SteamLibrary\steamapps\common\OutofOre\` |

## Files in this folder

| File | Contents |
|------|----------|
| `AI_MODDING_GUIDE.md` | Full handoff for AI |
| `PATHS.md` | All important paths |
| `ARCHITECTURE.md` | Game systems / key classes |
| `EXISTING_MODS.md` | Mods built in prior sessions |
| `MOD_RECIPES.md` | How to create a new mod |
| `PITFALLS.md` | What broke and how to avoid it |
| `TOOLS.md` | Mod Manager, installer kit, rebuild |
