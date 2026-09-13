# Assemble OutOfOre-Modding-Kit zip for distribution
# Run after build_exe.bat and build_installer_exe.bat

$ErrorActionPreference = "Stop"
$Root = Split-Path -Parent $MyInvocation.MyCommand.Path
$GameRoot = Split-Path -Parent $Root
$Win64 = Join-Path $GameRoot "OutOfOre\Binaries\Win64"
$UE4SS = Join-Path $Win64 "UE4SS"
$Dist = Join-Path $Root "dist"
$KitName = "OutOfOre-Modding-Kit-v1.3.0"
$KitDir = Join-Path $Dist $KitName
$Payload = Join-Path $KitDir "payload"

Write-Host "=== Assemble $KitName ==="

if (-not (Test-Path (Join-Path $Win64 "dwmapi.dll"))) {
    throw "dwmapi.dll not found at $Win64"
}
if (-not (Test-Path (Join-Path $UE4SS "UE4SS.dll"))) {
    throw "UE4SS.dll not found"
}

# Build EXEs if missing
$MgrExe = Join-Path $Dist "OutOfOreModManager.exe"
$InstExe = Join-Path $Dist "Install Out of Ore Mods.exe"
if (-not (Test-Path $MgrExe)) {
    Write-Host "Building Mod Manager EXE..."
    & cmd /c "`"$Root\build_exe.bat`""
}
if (-not (Test-Path $InstExe)) {
    Write-Host "Building Installer EXE..."
    # non-interactive: call pyinstaller directly
    Push-Location $Root
    python -m pip install --upgrade pyinstaller -q
    python -m PyInstaller --noconfirm --clean --onefile --windowed --name "Install Out of Ore Mods" `
        --distpath $Dist --workpath (Join-Path $Root "build") --specpath (Join-Path $Root "build") `
        ooo_mod_installer.py
    Pop-Location
}

if (-not (Test-Path $MgrExe)) { throw "Missing $MgrExe — run build_exe.bat" }
if (-not (Test-Path $InstExe)) { throw "Missing $InstExe" }

# Fresh kit dir
if (Test-Path $KitDir) { Remove-Item -Recurse -Force $KitDir }
New-Item -ItemType Directory -Force -Path $Payload | Out-Null
New-Item -ItemType Directory -Force -Path (Join-Path $Payload "UE4SS") | Out-Null
New-Item -ItemType Directory -Force -Path (Join-Path $Payload "ModManager") | Out-Null
New-Item -ItemType Directory -Force -Path (Join-Path $Payload "Optional") | Out-Null
New-Item -ItemType Directory -Force -Path (Join-Path $Payload "ModManager\packs") | Out-Null

# Proxy
Copy-Item (Join-Path $Win64 "dwmapi.dll") (Join-Path $Payload "dwmapi.dll") -Force

# Core UE4SS
Copy-Item (Join-Path $UE4SS "UE4SS.dll") (Join-Path $Payload "UE4SS\UE4SS.dll") -Force
if (Test-Path (Join-Path $UE4SS "LICENSE")) {
    Copy-Item (Join-Path $UE4SS "LICENSE") (Join-Path $Payload "UE4SS\LICENSE") -Force
}

# Sanitized settings
$settingsSrc = Join-Path $UE4SS "UE4SS-settings.ini"
$settingsDst = Join-Path $Payload "UE4SS\UE4SS-settings.ini"
if (Test-Path $settingsSrc) {
    $txt = Get-Content $settingsSrc -Raw
    $txt = $txt -replace "GuiConsoleEnabled\s*=\s*\d+", "GuiConsoleEnabled = 0"
    $txt = $txt -replace "GuiConsoleVisible\s*=\s*\d+", "GuiConsoleVisible = 0"
    $txt = $txt -replace "ConsoleEnabled\s*=\s*\d+", "ConsoleEnabled = 1"
    Set-Content -Path $settingsDst -Value $txt -Encoding UTF8
}

# Stock mods only
$stock = @(
    "CheatManagerEnablerMod", "ConsoleCommandsMod", "ConsoleEnablerMod",
    "SplitScreenMod", "LineTraceMod", "BPML_GenericFunctions", "BPModLoaderMod",
    "Keybinds", "shared"
)
$modsSrc = Join-Path $UE4SS "Mods"
$modsDst = Join-Path $Payload "UE4SS\Mods"
New-Item -ItemType Directory -Force -Path $modsDst | Out-Null

foreach ($name in $stock) {
    $s = Join-Path $modsSrc $name
    if (Test-Path $s) {
        Copy-Item $s (Join-Path $modsDst $name) -Recurse -Force
    }
}

# Clean stock mods.txt
@"
CheatManagerEnablerMod : 1
ConsoleCommandsMod : 1
ConsoleEnablerMod : 1
SplitScreenMod : 0
LineTraceMod : 0
BPML_GenericFunctions : 1
BPModLoaderMod : 1

; Built-in keybinds, do not move up!
Keybinds : 1
"@ | Set-Content (Join-Path $modsDst "mods.txt") -Encoding UTF8

$modsJson = @(
    @{ mod_name = "CheatManagerEnablerMod"; mod_enabled = $true },
    @{ mod_name = "ConsoleCommandsMod"; mod_enabled = $true },
    @{ mod_name = "ConsoleEnablerMod"; mod_enabled = $true },
    @{ mod_name = "SplitScreenMod"; mod_enabled = $false },
    @{ mod_name = "LineTraceMod"; mod_enabled = $false },
    @{ mod_name = "BPML_GenericFunctions"; mod_enabled = $true },
    @{ mod_name = "BPModLoaderMod"; mod_enabled = $true },
    @{ mod_name = "Keybinds"; mod_enabled = $true }
) | ConvertTo-Json
Set-Content (Join-Path $modsDst "mods.json") $modsJson -Encoding UTF8

# Manager EXE
Copy-Item $MgrExe (Join-Path $Payload "ModManager\OutOfOreModManager.exe") -Force
if (Test-Path (Join-Path $Root "README.md")) {
    Copy-Item (Join-Path $Root "README.md") (Join-Path $Payload "ModManager\README.md") -Force
}

# Optional MiniMapMod pack — installer checkbox, not enabled by default.
# Dirt/speed/tune stay in the private repo.
$miniSrc = $null
foreach ($c in @(
        (Join-Path $Root "optional_mods\MiniMapMod"),
        "D:\OpenCode\out-of-ore-modding\mods\MiniMapMod",
        (Join-Path $modsSrc "MiniMapMod")
    )) {
    if (Test-Path (Join-Path $c "Scripts\main.lua")) { $miniSrc = $c; break }
}
if ($miniSrc) {
    $stage = Join-Path $Dist "_minimap_pack"
    if (Test-Path $stage) { Remove-Item $stage -Recurse -Force }
    New-Item -ItemType Directory -Force -Path (Join-Path $stage "mods\MiniMapMod\Scripts") | Out-Null
    Copy-Item (Join-Path $miniSrc "Scripts\*") (Join-Path $stage "mods\MiniMapMod\Scripts\") -Force
    $miniReadme = Join-Path $miniSrc "README.md"
    if (Test-Path $miniReadme) {
        Copy-Item $miniReadme (Join-Path $stage "mods\MiniMapMod\README.md") -Force
    }
    @"
{
  "format": "outofore-modpack",
  "format_version": 1,
  "name": "MiniMapMod",
  "author": "tonyoo",
  "description": "HUD mini-map (optional)",
  "mods": [ { "name": "MiniMapMod", "enabled": true } ]
}
"@ | Set-Content (Join-Path $stage "manifest.json") -Encoding UTF8
    @"
MiniMapMod — optional HUD mini-map for Out of Ore.
Install via the installer checkbox, or Mod Manager → Unpack packs\MiniMapMod.ooomod
"@ | Set-Content (Join-Path $stage "README.txt") -Encoding UTF8
    $zipTmp = Join-Path $Dist "MiniMapMod.zip"
    if (Test-Path $zipTmp) { Remove-Item $zipTmp -Force }
    Compress-Archive -Path "$stage\*" -DestinationPath $zipTmp -Force
    Copy-Item $zipTmp (Join-Path $Payload "Optional\MiniMapMod.ooomod") -Force
    Copy-Item $zipTmp (Join-Path $Payload "ModManager\packs\MiniMapMod.ooomod") -Force
    Write-Host "Packed optional MiniMapMod.ooomod from $miniSrc"
} else {
    Write-Host "WARNING: MiniMapMod source not found — Optional pack skipped"
}

# Installer EXE at kit root
Copy-Item $InstExe (Join-Path $KitDir "Install Out of Ore Mods.exe") -Force

# README for end users
@"
Out of Ore Modding Kit v1.3.0
=============================

WHAT THIS INSTALLS
- UE4SS (mod loader runtime for Unreal games)
- Out of Ore Mod Manager (GUI .exe, no Python needed)
- Optional: MiniMapMod (HUD mini-map) — check the box in the installer,
  or later: Mod Manager → Unpack → packs\MiniMapMod.ooomod

Dirt / speed / other gameplay mods are NOT in this kit (private).

REQUIREMENTS
- Out of Ore installed via Steam
- Windows 10/11 64-bit

INSTALL
1. Make sure Out of Ore is installed and has been launched at least once.
2. Run "Install Out of Ore Mods.exe"
3. Confirm/browse to your game folder:
     ...\steamapps\common\OutofOre
   (the folder that CONTAINS the OutOfOre\ subfolder)
4. Install UE4SS + Mod Manager, then click Install.
5. Use the desktop shortcut "Out of Ore Mod Manager" (or open
     OutofOre\OutOfOreModManager\OutOfOreModManager.exe)
6. Launch Out of Ore. UE4SS loads automatically.

VERIFY
- After launching the game, check:
    OutOfOre\Binaries\Win64\UE4SS\UE4SS.log
  You should see "PS scan successful" and stock Lua mods starting.

PACK / SHARE YOUR OWN MODS
- Open Mod Manager -> select mods -> Pack Selected
- Share the .ooomod file
- Friends: Mod Manager -> Unpack Pack

TROUBLESHOOTING
- Antivirus may quarantine dwmapi.dll (UE4SS proxy). Restore it if blocked.
- If the game won't start: delete Binaries\Win64\dwmapi.dll and verify game files on Steam.
- GUI console is disabled by default for stability.

CREDITS
- UE4SS: https://github.com/UE4SS-RE/RE-UE4SS (MIT License)
- See payload\UE4SS\LICENSE
- Loader tools: https://github.com/tonyoo/out-of-ore-modding
"@ | Set-Content (Join-Path $KitDir "README.txt") -Encoding UTF8

# Zip the kit
$zipOut = Join-Path $Dist "$KitName.zip"
if (Test-Path $zipOut) { Remove-Item $zipOut -Force }
Compress-Archive -Path $KitDir -DestinationPath $zipOut -Force

# Copy optional .ooomod next to the kit zip so GitHub Release can attach them as extra assets
$optDir = Join-Path $Payload "Optional"
$assetArgs = @()
if (Test-Path $optDir) {
    Get-ChildItem $optDir -Filter "*.ooomod" | ForEach-Object {
        $dest = Join-Path $Dist $_.Name
        Copy-Item $_.FullName $dest -Force
        $assetArgs += $dest
        Write-Host "Release asset: $dest"
    }
}

Write-Host ""
Write-Host "=== DONE ==="
Write-Host "Kit folder: $KitDir"
Write-Host "Zip:        $zipOut"
Get-Item $zipOut | Format-List FullName, Length, LastWriteTime
Write-Host "GitHub Release (kit zip + ooomod assets):"
$ghFiles = @($zipOut) + $assetArgs
Write-Host ('gh release create v1.3.0 ' + (($ghFiles | ForEach-Object { '"' + $_ + '"' }) -join ' ') + ' --repo tonyoo/out-of-ore-modding --title "v1.3.0" --notes "Loader + optional MiniMapMod.ooomod asset"')
