# Deploy repo mods\ into the live game UE4SS\Mods folder
# Usage:
#   .\scripts\deploy_to_game.ps1
#   .\scripts\deploy_to_game.ps1 -GameRoot "E:\SteamLibrary\steamapps\common\OutofOre"

param(
    [string]$GameRoot = "E:\SteamLibrary\steamapps\common\OutofOre",
    [switch]$EnableInModsTxt = $true
)

$ErrorActionPreference = "Stop"
$RepoRoot = Split-Path -Parent (Split-Path -Parent $MyInvocation.MyCommand.Path)
$ModsSrc = Join-Path $RepoRoot "mods"
$ModsDst = Join-Path $GameRoot "OutOfOre\Binaries\Win64\UE4SS\Mods"
$ModsTxt = Join-Path $ModsDst "mods.txt"

if (-not (Test-Path $ModsSrc)) { throw "Missing $ModsSrc" }
if (-not (Test-Path $ModsDst)) { throw "Missing game Mods folder: $ModsDst" }

Get-ChildItem $ModsSrc -Directory | ForEach-Object {
    $name = $_.Name
    $dest = Join-Path $ModsDst $name
    if (Test-Path $dest) { Remove-Item $dest -Recurse -Force }
    Copy-Item $_.FullName $dest -Recurse -Force
    Write-Host "Deployed $name"

    if ($EnableInModsTxt -and (Test-Path $ModsTxt)) {
        $lines = Get-Content $ModsTxt
        $found = $false
        $out = foreach ($line in $lines) {
            if ($line -match "^\s*$([regex]::Escape($name))\s*:") {
                $found = $true
                "$name : 1"
            } else { $line }
        }
        if (-not $found) { $out += "$name : 1" }
        $out | Set-Content $ModsTxt -Encoding UTF8
    }
}

Write-Host "Done. Restart Out of Ore so UE4SS reloads mods."
