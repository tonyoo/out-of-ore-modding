#!/usr/bin/env python3
"""
Out of Ore Mod Manager
- GUI list / enable / disable UE4SS Lua mods
- Pack mods into .ooomod (zip) packages
- Unpack .ooomod / .zip packages into the game
"""

from __future__ import annotations

import json
import os
import re
import shutil
import subprocess
import sys
import tempfile
import zipfile
from dataclasses import dataclass, field
from datetime import datetime, timezone
from pathlib import Path
from typing import Dict, List, Optional, Tuple

try:
    import tkinter as tk
    from tkinter import filedialog, messagebox, simpledialog, ttk
except ImportError as e:
    print("tkinter is required:", e)
    sys.exit(1)


APP_NAME = "Out of Ore Mod Manager"
APP_VERSION = "1.0.0"
PACK_FORMAT = "outofore-modpack"
PACK_FORMAT_VERSION = 1
PACK_EXT = ".ooomod"

# UE4SS stock mods — never pack as "custom only" by default, still listable
STOCK_MODS = {
    "CheatManagerEnablerMod",
    "ConsoleCommandsMod",
    "ConsoleEnablerMod",
    "SplitScreenMod",
    "LineTraceMod",
    "BPML_GenericFunctions",
    "BPModLoaderMod",
    "Keybinds",
    "shared",
}


def utc_now_iso() -> str:
    return datetime.now(timezone.utc).replace(microsecond=0).isoformat()


def app_dir() -> Path:
    """Directory containing this app (script or frozen EXE)."""
    if getattr(sys, "frozen", False):
        return Path(sys.executable).resolve().parent
    return Path(__file__).resolve().parent


def is_valid_game_root(root: Path) -> bool:
    exe = root / "OutOfOre" / "Binaries" / "Win64" / "OutOfOre-Win64-Shipping.exe"
    return exe.is_file()


def discover_game_root(start_dir: Optional[Path] = None) -> Path:
    """Prefer game root next to this manager folder, then common Steam paths."""
    start = start_dir or app_dir()
    parent = start.parent

    candidates = [
        parent,  # .../OutofOre/OutOfOreModManager -> .../OutofOre
        start,   # manager dropped inside game root
        parent.parent,
        Path(r"E:\SteamLibrary\steamapps\common\OutofOre"),
        Path(r"C:\Program Files (x86)\Steam\steamapps\common\OutofOre"),
        Path(r"C:\Program Files\Steam\steamapps\common\OutofOre"),
        Path(r"D:\SteamLibrary\steamapps\common\OutofOre"),
        Path(r"F:\SteamLibrary\steamapps\common\OutofOre"),
    ]

    # Steam install path from registry
    try:
        import winreg

        for hive, sub in (
            (winreg.HKEY_CURRENT_USER, r"Software\Valve\Steam"),
            (winreg.HKEY_LOCAL_MACHINE, r"SOFTWARE\WOW6432Node\Valve\Steam"),
        ):
            try:
                with winreg.OpenKey(hive, sub) as key:
                    steam_path, _ = winreg.QueryValueEx(key, "SteamPath")
                    candidates.append(
                        Path(steam_path) / "steamapps" / "common" / "OutofOre"
                    )
            except OSError:
                pass
    except Exception:
        pass

    for c in candidates:
        try:
            c = c.resolve()
        except OSError:
            continue
        if is_valid_game_root(c):
            return c
        # Manager nested as OutofOre/OutOfOreModManager
        if is_valid_game_root(c.parent):
            return c.parent

    return parent


@dataclass
class ModInfo:
    name: str
    path: Path
    enabled: bool = False
    is_stock: bool = False
    has_scripts: bool = False
    description: str = ""


class ModsTxt:
    """Parse / write UE4SS mods.txt preserving comments and Keybinds position rules lightly."""

    def __init__(self, path: Path):
        self.path = path
        self.lines: List[str] = []
        self.enabled: Dict[str, bool] = {}

    def load(self) -> None:
        self.lines = []
        self.enabled = {}
        if not self.path.is_file():
            return
        text = self.path.read_text(encoding="utf-8", errors="replace")
        self.lines = text.splitlines()
        for line in self.lines:
            m = re.match(r"^\s*([A-Za-z0-9_]+)\s*:\s*([01])\s*$", line)
            if m:
                self.enabled[m.group(1)] = m.group(2) == "1"

    def set_enabled(self, name: str, enabled: bool) -> None:
        self.enabled[name] = enabled
        key = f"{name} :"
        found = False
        new_lines = []
        for line in self.lines:
            m = re.match(r"^\s*([A-Za-z0-9_]+)\s*:\s*([01])\s*$", line)
            if m and m.group(1) == name:
                new_lines.append(f"{name} : {'1' if enabled else '0'}")
                found = True
            else:
                new_lines.append(line)
        if not found:
            # Insert before trailing empty, or after Keybinds block
            insert_at = len(new_lines)
            for i, line in enumerate(new_lines):
                if line.strip().startswith("Keybinds"):
                    insert_at = i + 1
            new_lines.insert(insert_at, f"{name} : {'1' if enabled else '0'}")
        self.lines = new_lines

    def remove_mod(self, name: str) -> None:
        self.enabled.pop(name, None)
        self.lines = [
            line
            for line in self.lines
            if not re.match(rf"^\s*{re.escape(name)}\s*:\s*[01]\s*$", line)
        ]

    def save(self) -> None:
        self.path.parent.mkdir(parents=True, exist_ok=True)
        body = "\n".join(self.lines).rstrip() + "\n"
        self.path.write_text(body, encoding="utf-8")


class ModsJson:
    def __init__(self, path: Path):
        self.path = path
        self.data: List[dict] = []

    def load(self) -> None:
        self.data = []
        if not self.path.is_file():
            return
        try:
            raw = json.loads(self.path.read_text(encoding="utf-8"))
            if isinstance(raw, list):
                self.data = raw
        except json.JSONDecodeError:
            self.data = []

    def set_enabled(self, name: str, enabled: bool) -> None:
        for entry in self.data:
            if entry.get("mod_name") == name:
                entry["mod_enabled"] = enabled
                return
        self.data.append({"mod_name": name, "mod_enabled": enabled})

    def remove_mod(self, name: str) -> None:
        self.data = [e for e in self.data if e.get("mod_name") != name]

    def save(self) -> None:
        self.path.write_text(
            json.dumps(self.data, indent=4) + "\n", encoding="utf-8"
        )


class GamePaths:
    def __init__(self, game_root: Path):
        self.game_root = game_root
        self.ue4ss = game_root / "OutOfOre" / "Binaries" / "Win64" / "UE4SS"
        self.mods = self.ue4ss / "Mods"
        self.mods_txt = self.mods / "mods.txt"
        self.mods_json = self.mods / "mods.json"
        self.logic_mods = game_root / "OutOfOre" / "Content" / "Paks" / "LogicMods"
        self.exe = game_root / "OutOfOre" / "Binaries" / "Win64" / "OutOfOre-Win64-Shipping.exe"
        self.manager_dir = app_dir()
        self.packs_dir = self.manager_dir / "packs"

    def valid(self) -> bool:
        return self.mods.is_dir() and (
            self.mods_txt.is_file() or self.exe.is_file()
        )


def scan_mods(paths: GamePaths) -> List[ModInfo]:
    mods_txt = ModsTxt(paths.mods_txt)
    mods_txt.load()
    result: List[ModInfo] = []
    if not paths.mods.is_dir():
        return result

    for entry in sorted(paths.mods.iterdir(), key=lambda p: p.name.lower()):
        if not entry.is_dir():
            continue
        if entry.name.startswith("."):
            continue
        name = entry.name
        if name == "shared":
            # helper library, not a toggleable gameplay mod usually
            pass
        scripts = entry / "Scripts"
        has_scripts = scripts.is_dir() and any(scripts.glob("**/*"))
        # Prefer mods.txt; default enabled if has main.lua and not listed
        if name in mods_txt.enabled:
            enabled = mods_txt.enabled[name]
        else:
            enabled = False
        desc = ""
        readme = entry / "README.md"
        if readme.is_file():
            desc = readme.read_text(encoding="utf-8", errors="replace")[:200]
        else:
            main_lua = scripts / "main.lua" if scripts.is_dir() else None
            if main_lua and main_lua.is_file():
                head = main_lua.read_text(encoding="utf-8", errors="replace")[:400]
                m = re.search(r"--\[\[(.*?)\]\]", head, re.S)
                if m:
                    desc = " ".join(m.group(1).split())[:200]
        result.append(
            ModInfo(
                name=name,
                path=entry,
                enabled=enabled,
                is_stock=name in STOCK_MODS,
                has_scripts=has_scripts,
                description=desc,
            )
        )
    return result


def pack_mods(
    paths: GamePaths,
    mod_names: List[str],
    out_path: Path,
    pack_name: str,
    author: str = "",
    description: str = "",
    include_enabled_state: bool = True,
) -> Path:
    mods_txt = ModsTxt(paths.mods_txt)
    mods_txt.load()

    manifest = {
        "format": PACK_FORMAT,
        "format_version": PACK_FORMAT_VERSION,
        "name": pack_name,
        "author": author,
        "description": description,
        "created_utc": utc_now_iso(),
        "game": "Out of Ore",
        "target": "UE4SS",
        "mods": [],
    }

    with zipfile.ZipFile(out_path, "w", compression=zipfile.ZIP_DEFLATED) as zf:
        for name in mod_names:
            mod_dir = paths.mods / name
            if not mod_dir.is_dir():
                raise FileNotFoundError(f"Mod folder not found: {name}")
            if name == "shared":
                # allow packing shared if user insists
                pass
            enabled = mods_txt.enabled.get(name, True)
            manifest["mods"].append(
                {
                    "name": name,
                    "enabled": bool(enabled) if include_enabled_state else True,
                    "stock": name in STOCK_MODS,
                }
            )
            for root, _dirs, files in os.walk(mod_dir):
                for fn in files:
                    full = Path(root) / fn
                    rel = full.relative_to(paths.mods)
                    zf.write(full, arcname=str(Path("mods") / rel).replace("\\", "/"))

        zf.writestr(
            "manifest.json",
            json.dumps(manifest, indent=2) + "\n",
        )
        zf.writestr(
            "README.txt",
            (
                f"{pack_name}\n"
                f"Out of Ore mod pack ({PACK_FORMAT} v{PACK_FORMAT_VERSION})\n"
                f"Created: {manifest['created_utc']}\n\n"
                f"Install with Out of Ore Mod Manager → Unpack.\n"
                f"Mods: {', '.join(mod_names)}\n"
            ),
        )
    return out_path


def read_pack_manifest(zip_path: Path) -> dict:
    with zipfile.ZipFile(zip_path, "r") as zf:
        names = zf.namelist()
        # find manifest
        manifest_name = None
        for n in names:
            if n.replace("\\", "/").endswith("manifest.json"):
                manifest_name = n
                break
        if manifest_name:
            return json.loads(zf.read(manifest_name).decode("utf-8"))
        # infer from mods/ folders
        mods = set()
        for n in names:
            parts = Path(n).parts
            if len(parts) >= 2 and parts[0].lower() == "mods":
                mods.add(parts[1])
            elif len(parts) >= 1 and parts[0] not in ("manifest.json", "README.txt"):
                # loose mod folder at root
                if not n.endswith("/"):
                    mods.add(parts[0])
        return {
            "format": PACK_FORMAT,
            "format_version": 0,
            "name": zip_path.stem,
            "mods": [{"name": m, "enabled": True} for m in sorted(mods)],
            "inferred": True,
        }


def unpack_modpack(
    paths: GamePaths,
    pack_path: Path,
    enable_mods: bool = True,
    overwrite: bool = True,
) -> Tuple[List[str], dict]:
    """Extract pack into UE4SS Mods. Returns (installed_names, manifest)."""
    manifest = read_pack_manifest(pack_path)
    installed: List[str] = []

    with zipfile.ZipFile(pack_path, "r") as zf:
        # Normalize member paths
        members = zf.namelist()
        has_mods_prefix = any(
            m.replace("\\", "/").startswith("mods/") for m in members
        )

        with tempfile.TemporaryDirectory(prefix="ooo_pack_") as tmp:
            tmp_path = Path(tmp)
            zf.extractall(tmp_path)

            if has_mods_prefix:
                src_root = tmp_path / "mods"
            else:
                src_root = tmp_path

            if not src_root.is_dir():
                raise RuntimeError("Pack has no mods/ content")

            for child in src_root.iterdir():
                if not child.is_dir():
                    continue
                if child.name in ("__MACOSX",):
                    continue
                name = child.name
                dest = paths.mods / name
                if dest.exists():
                    if not overwrite:
                        continue
                    shutil.rmtree(dest)
                shutil.copytree(child, dest)
                installed.append(name)

    # Update mods.txt / mods.json
    mods_txt = ModsTxt(paths.mods_txt)
    mods_txt.load()
    mods_json = ModsJson(paths.mods_json)
    mods_json.load()

    manifest_mods = {
        m.get("name"): m for m in manifest.get("mods", []) if m.get("name")
    }
    for name in installed:
        en = True
        if name in manifest_mods:
            en = bool(manifest_mods[name].get("enabled", True))
        if not enable_mods:
            en = False
        if name == "shared":
            continue  # shared is a library folder
        mods_txt.set_enabled(name, en)
        mods_json.set_enabled(name, en)

    mods_txt.save()
    mods_json.save()
    return installed, manifest


class ModManagerApp(tk.Tk):
    def __init__(self, game_root: Optional[Path] = None):
        super().__init__()
        self.title(f"{APP_NAME} v{APP_VERSION}")
        self.geometry("920x560")
        self.minsize(780, 480)

        root = game_root or discover_game_root(app_dir())
        self.paths = GamePaths(root)
        self.mods: List[ModInfo] = []
        self._check_vars: Dict[str, tk.BooleanVar] = {}

        self._build_ui()
        self.refresh()

    def _build_ui(self) -> None:
        style = ttk.Style(self)
        try:
            style.theme_use("vista")
        except tk.TclError:
            pass

        top = ttk.Frame(self, padding=8)
        top.pack(fill=tk.X)

        ttk.Label(top, text="Game:").pack(side=tk.LEFT)
        self.game_var = tk.StringVar(value=str(self.paths.game_root))
        ent = ttk.Entry(top, textvariable=self.game_var, width=70)
        ent.pack(side=tk.LEFT, padx=6, fill=tk.X, expand=True)
        ttk.Button(top, text="Browse…", command=self.browse_game).pack(side=tk.LEFT)
        ttk.Button(top, text="Refresh", command=self.refresh).pack(side=tk.LEFT, padx=4)

        mid = ttk.Frame(self, padding=(8, 0))
        mid.pack(fill=tk.BOTH, expand=True)

        # Tree
        cols = ("enabled", "type", "name", "path")
        self.tree = ttk.Treeview(
            mid, columns=cols, show="headings", selectmode="extended"
        )
        self.tree.heading("enabled", text="On")
        self.tree.heading("type", text="Type")
        self.tree.heading("name", text="Mod")
        self.tree.heading("path", text="Folder")
        self.tree.column("enabled", width=50, anchor=tk.CENTER)
        self.tree.column("type", width=80, anchor=tk.CENTER)
        self.tree.column("name", width=220)
        self.tree.column("path", width=420)
        scroll = ttk.Scrollbar(mid, orient=tk.VERTICAL, command=self.tree.yview)
        self.tree.configure(yscrollcommand=scroll.set)
        self.tree.pack(side=tk.LEFT, fill=tk.BOTH, expand=True)
        scroll.pack(side=tk.RIGHT, fill=tk.Y)
        self.tree.bind("<Double-1>", self._on_double_click)

        # Buttons
        btn = ttk.Frame(self, padding=8)
        btn.pack(fill=tk.X)

        ttk.Button(btn, text="Enable", command=lambda: self.set_selected(True)).pack(
            side=tk.LEFT, padx=2
        )
        ttk.Button(btn, text="Disable", command=lambda: self.set_selected(False)).pack(
            side=tk.LEFT, padx=2
        )
        ttk.Button(btn, text="Open Folder", command=self.open_selected_folder).pack(
            side=tk.LEFT, padx=2
        )
        ttk.Button(btn, text="Delete Selected…", command=self.delete_selected).pack(
            side=tk.LEFT, padx=2
        )

        ttk.Separator(btn, orient=tk.VERTICAL).pack(side=tk.LEFT, fill=tk.Y, padx=8)

        ttk.Button(btn, text="Pack Selected…", command=self.pack_selected).pack(
            side=tk.LEFT, padx=2
        )
        ttk.Button(btn, text="Unpack Pack…", command=self.unpack_pack).pack(
            side=tk.LEFT, padx=2
        )
        ttk.Button(btn, text="Open Packs Folder", command=self.open_packs_folder).pack(
            side=tk.LEFT, padx=2
        )

        ttk.Separator(btn, orient=tk.VERTICAL).pack(side=tk.LEFT, fill=tk.Y, padx=8)
        ttk.Button(btn, text="Launch Game", command=self.launch_game).pack(
            side=tk.LEFT, padx=2
        )

        # Status
        self.status = tk.StringVar(value="Ready")
        status_bar = ttk.Label(self, textvariable=self.status, relief=tk.SUNKEN, anchor=tk.W)
        status_bar.pack(fill=tk.X, side=tk.BOTTOM)

        # Help line
        help_f = ttk.Frame(self, padding=(8, 0, 8, 4))
        help_f.pack(fill=tk.X)
        ttk.Label(
            help_f,
            text=(
                "Pack = share mods as .ooomod  ·  Unpack = install a pack  ·  "
                "Enable/Disable writes mods.txt  ·  Stock mods = UE4SS built-ins"
            ),
            foreground="#444",
        ).pack(anchor=tk.W)

    def browse_game(self) -> None:
        d = filedialog.askdirectory(
            title="Select Out of Ore game root (folder containing OutOfOre\\)",
            initialdir=str(self.paths.game_root),
        )
        if not d:
            return
        self.paths = GamePaths(Path(d))
        self.game_var.set(str(self.paths.game_root))
        self.refresh()

    def refresh(self) -> None:
        root = Path(self.game_var.get())
        self.paths = GamePaths(root)
        self.tree.delete(*self.tree.get_children())
        if not self.paths.valid():
            self.status.set(
                f"Invalid game path — need OutOfOre\\Binaries\\Win64\\UE4SS\\Mods under: {root}"
            )
            return
        self.mods = scan_mods(self.paths)
        for m in self.mods:
            typ = "stock" if m.is_stock else "custom"
            on = "YES" if m.enabled else "no"
            self.tree.insert(
                "",
                tk.END,
                iid=m.name,
                values=(on, typ, m.name, str(m.path)),
            )
        enabled_n = sum(1 for m in self.mods if m.enabled)
        self.status.set(
            f"{len(self.mods)} mods  ·  {enabled_n} enabled  ·  {self.paths.mods}"
        )

    def _selected_names(self) -> List[str]:
        return list(self.tree.selection())

    def set_selected(self, enabled: bool) -> None:
        names = self._selected_names()
        if not names:
            messagebox.showinfo(APP_NAME, "Select one or more mods first.")
            return
        if not self.paths.valid():
            return
        mods_txt = ModsTxt(self.paths.mods_txt)
        mods_txt.load()
        mods_json = ModsJson(self.paths.mods_json)
        mods_json.load()
        for name in names:
            if name == "shared":
                continue
            mods_txt.set_enabled(name, enabled)
            mods_json.set_enabled(name, enabled)
        mods_txt.save()
        mods_json.save()
        self.refresh()
        self.status.set(
            f"{'Enabled' if enabled else 'Disabled'}: {', '.join(names)}"
        )

    def _on_double_click(self, _event=None) -> None:
        names = self._selected_names()
        if not names:
            return
        name = names[0]
        mod = next((m for m in self.mods if m.name == name), None)
        if not mod or name == "shared":
            return
        self.set_selected(not mod.enabled)

    def open_selected_folder(self) -> None:
        names = self._selected_names()
        if not names:
            messagebox.showinfo(APP_NAME, "Select a mod.")
            return
        path = self.paths.mods / names[0]
        if path.is_dir():
            os.startfile(path)  # type: ignore[attr-defined]

    def open_packs_folder(self) -> None:
        self.paths.packs_dir.mkdir(parents=True, exist_ok=True)
        os.startfile(self.paths.packs_dir)  # type: ignore[attr-defined]

    def delete_selected(self) -> None:
        names = [n for n in self._selected_names() if n != "shared"]
        if not names:
            messagebox.showinfo(APP_NAME, "Select custom mods to delete.")
            return
        stock = [n for n in names if n in STOCK_MODS]
        if stock:
            if not messagebox.askyesno(
                APP_NAME,
                "You selected stock UE4SS mods:\n"
                + ", ".join(stock)
                + "\n\nDelete them anyway? (not recommended)",
            ):
                names = [n for n in names if n not in STOCK_MODS]
        if not names:
            return
        if not messagebox.askyesno(
            APP_NAME,
            "Permanently delete these mod folders?\n\n" + "\n".join(names),
        ):
            return
        mods_txt = ModsTxt(self.paths.mods_txt)
        mods_txt.load()
        mods_json = ModsJson(self.paths.mods_json)
        mods_json.load()
        for name in names:
            folder = self.paths.mods / name
            if folder.is_dir():
                shutil.rmtree(folder)
            mods_txt.remove_mod(name)
            mods_json.remove_mod(name)
        mods_txt.save()
        mods_json.save()
        self.refresh()

    def pack_selected(self) -> None:
        names = [n for n in self._selected_names() if n != "shared"]
        if not names:
            # allow packing all custom
            if messagebox.askyesno(
                APP_NAME,
                "No selection. Pack all CUSTOM mods?",
            ):
                names = [m.name for m in self.mods if not m.is_stock and m.name != "shared"]
            else:
                return
        if not names:
            messagebox.showinfo(APP_NAME, "No mods to pack.")
            return

        pack_name = simpledialog.askstring(
            APP_NAME, "Pack display name:", initialvalue="My OutOfOre Mods"
        )
        if not pack_name:
            return
        author = simpledialog.askstring(APP_NAME, "Author (optional):", initialvalue="") or ""
        desc = (
            simpledialog.askstring(APP_NAME, "Description (optional):", initialvalue="")
            or ""
        )

        self.paths.packs_dir.mkdir(parents=True, exist_ok=True)
        safe = re.sub(r"[^\w\-]+", "_", pack_name).strip("_") or "modpack"
        default_path = self.paths.packs_dir / f"{safe}{PACK_EXT}"
        out = filedialog.asksaveasfilename(
            title="Save mod pack",
            defaultextension=PACK_EXT,
            initialfile=default_path.name,
            initialdir=str(self.paths.packs_dir),
            filetypes=[
                ("Out of Ore mod pack", f"*{PACK_EXT}"),
                ("Zip archive", "*.zip"),
                ("All files", "*.*"),
            ],
        )
        if not out:
            return
        out_path = Path(out)
        try:
            pack_mods(
                self.paths,
                names,
                out_path,
                pack_name=pack_name,
                author=author,
                description=desc,
            )
        except Exception as e:
            messagebox.showerror(APP_NAME, f"Pack failed:\n{e}")
            return
        messagebox.showinfo(
            APP_NAME,
            f"Packed {len(names)} mod(s):\n{out_path}\n\n"
            f"Share this file. Others install it with Unpack.",
        )
        self.status.set(f"Packed → {out_path.name}")

    def unpack_pack(self) -> None:
        path = filedialog.askopenfilename(
            title="Select mod pack to install",
            initialdir=str(self.paths.packs_dir if self.paths.packs_dir.is_dir() else self.paths.game_root),
            filetypes=[
                ("Out of Ore mod pack", f"*{PACK_EXT}"),
                ("Zip archive", "*.zip"),
                ("All files", "*.*"),
            ],
        )
        if not path:
            return
        pack_path = Path(path)
        try:
            preview = read_pack_manifest(pack_path)
        except Exception as e:
            messagebox.showerror(APP_NAME, f"Cannot read pack:\n{e}")
            return

        mod_list = ", ".join(
            m.get("name", "?") for m in preview.get("mods", [])
        ) or "(will scan archive)"
        if not messagebox.askyesno(
            APP_NAME,
            f"Install pack?\n\n"
            f"Name: {preview.get('name', pack_path.stem)}\n"
            f"Mods: {mod_list}\n\n"
            f"Existing folders with the same name will be replaced.",
        ):
            return
        try:
            installed, manifest = unpack_modpack(self.paths, pack_path, enable_mods=True)
        except Exception as e:
            messagebox.showerror(APP_NAME, f"Unpack failed:\n{e}")
            return
        self.refresh()
        messagebox.showinfo(
            APP_NAME,
            f"Installed {len(installed)} mod(s):\n"
            + "\n".join(installed)
            + "\n\nRestart Out of Ore so UE4SS reloads mods.",
        )
        self.status.set(f"Unpacked {manifest.get('name', pack_path.name)}")

    def launch_game(self) -> None:
        exe = self.paths.exe
        if not exe.is_file():
            messagebox.showerror(APP_NAME, f"Game exe not found:\n{exe}")
            return
        try:
            subprocess.Popen([str(exe)], cwd=str(exe.parent))
            self.status.set("Launched game")
        except Exception as e:
            messagebox.showerror(APP_NAME, f"Launch failed:\n{e}")


def main() -> None:
    # Optional CLI
    if len(sys.argv) > 1 and sys.argv[1] in ("-h", "--help"):
        print(
            f"{APP_NAME} v{APP_VERSION}\n"
            "  (no args)     open GUI\n"
            "  --game PATH   set game root\n"
        )
        return
    game_root = None
    if len(sys.argv) > 2 and sys.argv[1] == "--game":
        game_root = Path(sys.argv[2])
    app = ModManagerApp(game_root=game_root)
    app.mainloop()


if __name__ == "__main__":
    main()
