# Finish GitHub setup (you do this once)

## 1. Log in with GitHub CLI

Open **PowerShell** or **Terminal** and run:

```powershell
gh auth login
```

Suggested choices:

- GitHub.com  
- HTTPS  
- Login with a web browser  
- Authenticate in the browser when it opens  

Check:

```powershell
gh auth status
```

## 2. Create remote + push (or ask the AI to run this after login)

```powershell
cd D:\OpenCode\out-of-ore-modding
gh repo create out-of-ore-modding --public --source=. --remote=origin --push --description "Out of Ore UE4SS mods, Mod Manager, and installer kit"
```

## 3. Publish Release v1.0.0 (kit zip)

The kit zip is already built at:

```text
E:\SteamLibrary\steamapps\common\OutofOre\OutOfOreModManager\dist\OutOfOre-Modding-Kit-v1.0.zip
```

```powershell
cd D:\OpenCode\out-of-ore-modding
gh release create v1.0.0 `
  "E:\SteamLibrary\steamapps\common\OutofOre\OutOfOreModManager\dist\OutOfOre-Modding-Kit-v1.0.zip" `
  --title "v1.0.0 — Modding Kit" `
  --notes "Full kit: UE4SS + OutOfOreModManager.exe + Installer + starter mods (DirtCapacity, VehicleSpeed). Run Install Out of Ore Mods.exe and point at your OutofOre game folder."
```

## 4. Tell the AI

Say: **“I’m logged into gh”** and we can finish create/push/release if not done yet.

---

Local repo is already initialized and committed at:

```text
D:\OpenCode\out-of-ore-modding
```
