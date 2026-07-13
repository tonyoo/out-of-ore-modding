# Vendor / UE4SS payload

Release kits **bundle a clean UE4SS** (MIT) for Out of Ore convenience:

- `dwmapi.dll` (injection proxy)
- `UE4SS/UE4SS.dll`, settings (UE 4.27), stock Mods, LICENSE

## Source of the payload

Built from a known-working local game install via:

```text
tools/installer/assemble_kit.ps1
```

(or the copy under `OutOfOreModManager` on the game drive).

That script **excludes** logs, crash dumps, and multi‑MB object dumps.

## Do not commit

Binary UE4SS payloads and EXEs stay out of git (see root `.gitignore`).  
They ship as **GitHub Release** assets (`OutOfOre-Modding-Kit-vX.Y.zip`).

## Official upstream

https://github.com/UE4SS-RE/RE-UE4SS  
Docs: https://docs.ue4ss.com/
