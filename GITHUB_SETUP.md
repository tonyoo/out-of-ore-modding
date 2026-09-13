# GitHub setup — COMPLETE

- Repo: https://github.com/tonyoo/out-of-ore-modding
- Release: https://github.com/tonyoo/out-of-ore-modding/releases/tag/v1.0.0
- Logged in as: tonyoo

To push later:
```powershell
cd D:\OpenCode\out-of-ore-modding
git add -A
git commit -m "your message"
git push
```

New loader release — attach the kit zip **and** each optional `.ooomod` as Release assets:
```powershell
gh release create v1.3.0 `
  path\to\OutOfOre-Modding-Kit-v1.3.0.zip `
  path\to\MiniMapMod.ooomod `
  --title "v1.3.0" --notes "Loader + MiniMapMod.ooomod"
```
