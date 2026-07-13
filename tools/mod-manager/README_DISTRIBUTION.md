# Sharing Out of Ore mods with friends

## What to send them

Send this zip:

```text
OutOfOreModManager\dist\OutOfOre-Modding-Kit-v1.0.zip
```

(~25 MB)

## What they do

1. Install **Out of Ore** from Steam (launch it once).
2. Unzip the kit anywhere.
3. Run **`Install Out of Ore Mods.exe`**
4. Point it at:
   ```text
   ...\steamapps\common\OutofOre
   ```
   (folder that **contains** the `OutOfOre\` subfolder)
5. Leave checkboxes on → **Install**
6. Open **Out of Ore Mod Manager** (desktop shortcut)
7. Launch the game

They do **not** need Python.

## Rebuild the kit (on your PC)

```text
cd OutOfOreModManager
build_exe.bat
build_installer_exe.bat
powershell -ExecutionPolicy Bypass -File assemble_kit.ps1
```

## Local shortcuts (your machine)

| File | Purpose |
|------|---------|
| `OutOfOreModManager.exe` | Mod manager (no Python) |
| `Launch Mod Manager.bat` | Runs Python script (dev) |
| `dist\Install Out of Ore Mods.exe` | Installer only (needs `payload\`) |
| `dist\OutOfOre-Modding-Kit-v1.0.zip` | Full share package |
