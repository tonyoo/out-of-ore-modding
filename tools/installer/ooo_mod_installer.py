#!/usr/bin/env python3
"""
Out of Ore Modding Installer
Installs UE4SS + OutOfOreModManager.exe into a game folder.
Expects a payload/ folder next to this script or frozen EXE.
"""

from __future__ import annotations

import os
import shutil
import sys
import zipfile
from datetime import datetime
from pathlib import Path
from typing import List, Optional

try:
    import tkinter as tk
    from tkinter import filedialog, messagebox, scrolledtext, ttk
except ImportError as e:
    print("tkinter is required:", e)
    sys.exit(1)


APP_NAME = "Out of Ore Modding Setup"
APP_VERSION = "1.0.0"


def app_dir() -> Path:
    if getattr(sys, "frozen", False):
        return Path(sys.executable).resolve().parent
    return Path(__file__).resolve().parent


def payload_dir() -> Path:
    """payload/ beside installer, or extracted next to EXE in kit root."""
    base = app_dir()
    for candidate in (base / "payload", base.parent / "payload"):
        if candidate.is_dir():
            return candidate
    return base / "payload"


def is_valid_game_root(root: Path) -> bool:
    return (
        root / "OutOfOre" / "Binaries" / "Win64" / "OutOfOre-Win64-Shipping.exe"
    ).is_file()


def detect_game_roots() -> List[Path]:
    candidates: List[Path] = []
    bases = [
        Path(r"E:\SteamLibrary\steamapps\common\OutofOre"),
        Path(r"C:\Program Files (x86)\Steam\steamapps\common\OutofOre"),
        Path(r"C:\Program Files\Steam\steamapps\common\OutofOre"),
        Path(r"D:\SteamLibrary\steamapps\common\OutofOre"),
        Path(r"F:\SteamLibrary\steamapps\common\OutofOre"),
        Path(r"G:\SteamLibrary\steamapps\common\OutofOre"),
    ]
    try:
        import winreg

        for hive, sub in (
            (winreg.HKEY_CURRENT_USER, r"Software\Valve\Steam"),
            (winreg.HKEY_LOCAL_MACHINE, r"SOFTWARE\WOW6432Node\Valve\Steam"),
        ):
            try:
                with winreg.OpenKey(hive, sub) as key:
                    steam_path, _ = winreg.QueryValueEx(key, "SteamPath")
                    bases.append(
                        Path(steam_path.replace("/", "\\"))
                        / "steamapps"
                        / "common"
                        / "OutofOre"
                    )
            except OSError:
                pass
    except Exception:
        pass

    # Also scan common SteamLibrary roots on fixed drives
    for letter in "CDEFGHIJ":
        bases.append(Path(f"{letter}:/SteamLibrary/steamapps/common/OutofOre"))
        bases.append(Path(f"{letter}:/Steam/steamapps/common/OutofOre"))

    seen = set()
    out: List[Path] = []
    for b in bases:
        try:
            b = b.resolve()
        except OSError:
            continue
        key = str(b).lower()
        if key in seen:
            continue
        seen.add(key)
        if is_valid_game_root(b):
            out.append(b)
    return out


def copy_tree_merge(src: Path, dst: Path, skip_names: Optional[set] = None) -> int:
    """Copy files from src to dst, creating dirs. Returns file count."""
    skip_names = skip_names or set()
    count = 0
    for root, dirs, files in os.walk(src):
        root_p = Path(root)
        rel = root_p.relative_to(src)
        # prune skipped dir names
        dirs[:] = [d for d in dirs if d not in skip_names]
        target_dir = dst / rel
        target_dir.mkdir(parents=True, exist_ok=True)
        for fn in files:
            if fn in skip_names:
                continue
            s = root_p / fn
            d = target_dir / fn
            shutil.copy2(s, d)
            count += 1
    return count


def timestamp() -> str:
    return datetime.now().strftime("%Y%m%d_%H%M%S")


class InstallerApp(tk.Tk):
    def __init__(self) -> None:
        super().__init__()
        self.title(f"{APP_NAME} v{APP_VERSION}")
        self.geometry("720x520")
        self.minsize(640, 440)

        self.payload = payload_dir()
        detected = detect_game_roots()
        self.game_var = tk.StringVar(
            value=str(detected[0]) if detected else ""
        )
        self.opt_ue4ss = tk.BooleanVar(value=True)
        self.opt_manager = tk.BooleanVar(value=True)
        self.opt_starter = tk.BooleanVar(value=False)  # loader kit has no gameplay packs
        self.opt_shortcut = tk.BooleanVar(value=True)

        self._build_ui()
        self.log(f"Payload folder: {self.payload}")
        if not self.payload.is_dir():
            self.log("WARNING: payload/ not found next to installer.")
        if detected:
            self.log(f"Auto-detected game: {detected[0]}")
        else:
            self.log("Game not auto-detected — browse to OutofOre folder.")

    def _build_ui(self) -> None:
        try:
            ttk.Style(self).theme_use("vista")
        except tk.TclError:
            pass

        frm = ttk.Frame(self, padding=10)
        frm.pack(fill=tk.BOTH, expand=True)

        ttk.Label(
            frm,
            text="Installs UE4SS (required for mods) and the Out of Ore Mod Manager.",
        ).pack(anchor=tk.W)

        path_f = ttk.Frame(frm)
        path_f.pack(fill=tk.X, pady=8)
        ttk.Label(path_f, text="Game folder:").pack(side=tk.LEFT)
        ttk.Entry(path_f, textvariable=self.game_var).pack(
            side=tk.LEFT, fill=tk.X, expand=True, padx=6
        )
        ttk.Button(path_f, text="Browse…", command=self.browse).pack(side=tk.LEFT)
        ttk.Button(path_f, text="Auto-detect", command=self.autodetect).pack(
            side=tk.LEFT, padx=4
        )

        opts = ttk.LabelFrame(frm, text="Components", padding=8)
        opts.pack(fill=tk.X, pady=4)
        ttk.Checkbutton(
            opts, text="Install UE4SS (dwmapi.dll + UE4SS folder)", variable=self.opt_ue4ss
        ).pack(anchor=tk.W)
        ttk.Checkbutton(
            opts, text="Install Mod Manager (OutOfOreModManager.exe)", variable=self.opt_manager
        ).pack(anchor=tk.W)
        ttk.Checkbutton(
            opts,
            text="Install optional pack from payload/Optional (if present)",
            variable=self.opt_starter,
        ).pack(anchor=tk.W)
        ttk.Label(
            opts,
            text="Default kit is loader-only (no dirt/speed gameplay mods).",
            foreground="#555",
        ).pack(anchor=tk.W)
        ttk.Checkbutton(
            opts, text="Create desktop shortcut to Mod Manager", variable=self.opt_shortcut
        ).pack(anchor=tk.W)

        ttk.Label(frm, text="Log:").pack(anchor=tk.W, pady=(8, 0))
        self.log_box = scrolledtext.ScrolledText(frm, height=14, state=tk.DISABLED)
        self.log_box.pack(fill=tk.BOTH, expand=True, pady=4)

        btns = ttk.Frame(frm)
        btns.pack(fill=tk.X, pady=6)
        ttk.Button(btns, text="Install", command=self.install).pack(side=tk.LEFT)
        ttk.Button(btns, text="Open payload folder", command=self.open_payload).pack(
            side=tk.LEFT, padx=6
        )
        ttk.Button(btns, text="Close", command=self.destroy).pack(side=tk.RIGHT)

        ttk.Label(
            frm,
            text="UE4SS is MIT-licensed (https://github.com/UE4SS-RE/RE-UE4SS). "
            "Antivirus may flag the proxy DLL — that is normal for injectors.",
            foreground="#555",
            wraplength=680,
        ).pack(anchor=tk.W)

    def log(self, msg: str) -> None:
        self.log_box.configure(state=tk.NORMAL)
        self.log_box.insert(tk.END, msg + "\n")
        self.log_box.see(tk.END)
        self.log_box.configure(state=tk.DISABLED)
        self.update_idletasks()

    def browse(self) -> None:
        d = filedialog.askdirectory(title="Select OutofOre game root folder")
        if d:
            self.game_var.set(d)

    def autodetect(self) -> None:
        found = detect_game_roots()
        if not found:
            messagebox.showwarning(APP_NAME, "Could not find Out of Ore automatically.")
            self.log("Auto-detect failed.")
            return
        self.game_var.set(str(found[0]))
        self.log(f"Auto-detected: {found[0]}")
        if len(found) > 1:
            self.log("Other installs: " + " | ".join(str(p) for p in found[1:]))

    def open_payload(self) -> None:
        p = self.payload
        p.mkdir(parents=True, exist_ok=True)
        os.startfile(p)  # type: ignore[attr-defined]

    def install(self) -> None:
        game = Path(self.game_var.get().strip().strip('"'))
        if not is_valid_game_root(game):
            messagebox.showerror(
                APP_NAME,
                "Invalid game folder.\n\n"
                "Select the folder that contains OutOfOre\\Binaries\\Win64\\"
                "OutOfOre-Win64-Shipping.exe\n"
                "(usually ...\\steamapps\\common\\OutofOre)",
            )
            return

        payload = self.payload
        if not payload.is_dir():
            messagebox.showerror(
                APP_NAME,
                f"payload folder missing:\n{payload}\n\n"
                "Re-download the full Modding Kit zip.",
            )
            return

        win64 = game / "OutOfOre" / "Binaries" / "Win64"
        ue4ss_dst = win64 / "UE4SS"
        ts = timestamp()

        try:
            if self.opt_ue4ss.get():
                self._install_ue4ss(payload, win64, ue4ss_dst, ts)

            if self.opt_manager.get():
                self._install_manager(payload, game, ts)

            if self.opt_starter.get():
                self._install_starter_pack(payload, ue4ss_dst)

            if self.opt_shortcut.get() and self.opt_manager.get():
                self._desktop_shortcut(game / "OutOfOreModManager" / "OutOfOreModManager.exe")

            log_path = game / "OutOfOreModManager" / "INSTALL_LOG.txt"
            log_path.parent.mkdir(parents=True, exist_ok=True)
            log_path.write_text(
                f"Installed {ts}\nGame: {game}\nPayload: {payload}\n",
                encoding="utf-8",
            )
            self.log("DONE.")
            messagebox.showinfo(
                APP_NAME,
                "Install finished.\n\n"
                "1. Start the Mod Manager (desktop shortcut or OutOfOreModManager folder)\n"
                "2. Launch Out of Ore once so UE4SS creates a log\n"
                "3. Restart the game after enabling/unpacking mods",
            )
        except Exception as e:
            self.log(f"ERROR: {e}")
            messagebox.showerror(APP_NAME, f"Install failed:\n{e}")

    def _install_ue4ss(self, payload: Path, win64: Path, ue4ss_dst: Path, ts: str) -> None:
        proxy_src = payload / "dwmapi.dll"
        ue4ss_src = payload / "UE4SS"
        if not proxy_src.is_file():
            raise FileNotFoundError(f"Missing {proxy_src}")
        if not ue4ss_src.is_dir():
            raise FileNotFoundError(f"Missing {ue4ss_src}")

        # Backup existing proxy
        proxy_dst = win64 / "dwmapi.dll"
        if proxy_dst.is_file():
            bak = win64 / f"dwmapi.dll.bak_{ts}"
            shutil.copy2(proxy_dst, bak)
            self.log(f"Backed up existing dwmapi.dll → {bak.name}")

        shutil.copy2(proxy_src, proxy_dst)
        self.log(f"Installed proxy: {proxy_dst}")

        # Backup existing UE4SS folder (rename aside once)
        if ue4ss_dst.is_dir():
            # Preserve custom mods before merge
            custom_backup = win64 / f"UE4SS_custom_mods_backup_{ts}"
            mods_src = ue4ss_dst / "Mods"
            if mods_src.is_dir():
                custom_backup.mkdir(parents=True, exist_ok=True)
                for child in mods_src.iterdir():
                    if child.is_dir() and child.name not in {
                        "CheatManagerEnablerMod",
                        "ConsoleCommandsMod",
                        "ConsoleEnablerMod",
                        "SplitScreenMod",
                        "LineTraceMod",
                        "BPML_GenericFunctions",
                        "BPModLoaderMod",
                        "Keybinds",
                        "shared",
                    }:
                        dest = custom_backup / child.name
                        if dest.exists():
                            shutil.rmtree(dest)
                        shutil.copytree(child, dest)
                        self.log(f"Preserved custom mod: {child.name}")

            bak_dir = win64 / f"UE4SS_backup_{ts}"
            if not bak_dir.exists():
                # Only backup settings/dll, not huge dumps if present
                bak_dir.mkdir(parents=True, exist_ok=True)
                for name in ("UE4SS.dll", "UE4SS-settings.ini", "LICENSE", "mods.txt"):
                    p = ue4ss_dst / name
                    if p.is_file():
                        shutil.copy2(p, bak_dir / name)
                self.log(f"Backed up core UE4SS files → {bak_dir.name}")

        # Copy clean UE4SS tree (includes stock Mods)
        n = copy_tree_merge(
            ue4ss_src,
            ue4ss_dst,
            skip_names={
                "UE4SS.log",
                "UE4SS_ObjectDump.txt",
                "imgui.ini",
            },
        )
        self.log(f"Installed UE4SS files ({n} files) → {ue4ss_dst}")

        # Restore custom mods if we backed them up
        custom_backup = win64 / f"UE4SS_custom_mods_backup_{ts}"
        if custom_backup.is_dir():
            mods_dst = ue4ss_dst / "Mods"
            for child in custom_backup.iterdir():
                if child.is_dir():
                    dest = mods_dst / child.name
                    if dest.exists():
                        shutil.rmtree(dest)
                    shutil.copytree(child, dest)
                    self.log(f"Restored custom mod: {child.name}")
            # Ensure they are in mods.txt as enabled
            self._ensure_mods_txt_entries(
                ue4ss_dst / "Mods" / "mods.txt",
                [c.name for c in custom_backup.iterdir() if c.is_dir()],
                enable=True,
            )

    def _ensure_mods_txt_entries(
        self, mods_txt: Path, names: List[str], enable: bool
    ) -> None:
        if not names:
            return
        lines: List[str] = []
        if mods_txt.is_file():
            lines = mods_txt.read_text(encoding="utf-8", errors="replace").splitlines()
        existing = set()
        import re

        out_lines = []
        for line in lines:
            m = re.match(r"^\s*([A-Za-z0-9_]+)\s*:\s*([01])\s*$", line)
            if m and m.group(1) in names:
                out_lines.append(f"{m.group(1)} : {'1' if enable else '0'}")
                existing.add(m.group(1))
            else:
                out_lines.append(line)
        for name in names:
            if name not in existing and name != "shared":
                out_lines.append(f"{name} : {'1' if enable else '0'}")
        mods_txt.write_text("\n".join(out_lines).rstrip() + "\n", encoding="utf-8")

    def _install_manager(self, payload: Path, game: Path, ts: str) -> None:
        mgr_src_dir = payload / "ModManager"
        exe_src = mgr_src_dir / "OutOfOreModManager.exe"
        if not exe_src.is_file():
            # allow exe sitting directly in payload
            exe_src = payload / "OutOfOreModManager.exe"
        if not exe_src.is_file():
            raise FileNotFoundError("OutOfOreModManager.exe not found in payload")

        dest_dir = game / "OutOfOreModManager"
        dest_dir.mkdir(parents=True, exist_ok=True)
        dest_exe = dest_dir / "OutOfOreModManager.exe"
        shutil.copy2(exe_src, dest_exe)
        (dest_dir / "packs").mkdir(exist_ok=True)

        # Copy optional README
        for name in ("README.md", "README_DISTRIBUTION.md", "README.txt"):
            src = mgr_src_dir / name
            if src.is_file():
                shutil.copy2(src, dest_dir / name)

        self.log(f"Installed Mod Manager → {dest_exe}")

    def _install_starter_pack(self, payload: Path, ue4ss_dst: Path) -> None:
        opt = payload / "Optional"
        packs = list(opt.glob("*.ooomod")) + list(opt.glob("*.zip")) if opt.is_dir() else []
        # also packs next to manager
        packs += list((payload / "ModManager" / "packs").glob("*.ooomod"))
        if not packs:
            self.log("No starter pack found (skipped).")
            return

        pack = packs[0]
        self.log(f"Installing starter pack: {pack.name}")
        mods_dir = ue4ss_dst / "Mods"
        mods_dir.mkdir(parents=True, exist_ok=True)

        with zipfile.ZipFile(pack, "r") as zf:
            names = zf.namelist()
            has_mods = any(n.replace("\\", "/").startswith("mods/") for n in names)
            import tempfile

            with tempfile.TemporaryDirectory() as tmp:
                tmp_p = Path(tmp)
                zf.extractall(tmp_p)
                src_root = tmp_p / "mods" if has_mods else tmp_p
                installed = []
                if src_root.is_dir():
                    for child in src_root.iterdir():
                        if not child.is_dir():
                            continue
                        if child.name in ("__MACOSX",):
                            continue
                        dest = mods_dir / child.name
                        if dest.exists():
                            shutil.rmtree(dest)
                        shutil.copytree(child, dest)
                        installed.append(child.name)
                        self.log(f"  + {child.name}")
                self._ensure_mods_txt_entries(
                    mods_dir / "mods.txt", installed, enable=True
                )
                # lightweight mods.json update
                self._merge_mods_json(mods_dir / "mods.json", installed, enable=True)

    def _merge_mods_json(self, path: Path, names: List[str], enable: bool) -> None:
        import json

        data = []
        if path.is_file():
            try:
                data = json.loads(path.read_text(encoding="utf-8"))
                if not isinstance(data, list):
                    data = []
            except json.JSONDecodeError:
                data = []
        by_name = {e.get("mod_name"): e for e in data if isinstance(e, dict)}
        for name in names:
            if name == "shared":
                continue
            by_name[name] = {"mod_name": name, "mod_enabled": enable}
        path.write_text(
            json.dumps(list(by_name.values()), indent=4) + "\n", encoding="utf-8"
        )

    def _desktop_shortcut(self, target: Path) -> None:
        if not target.is_file():
            self.log("Shortcut skipped (manager exe missing).")
            return
        desktop = Path.home() / "Desktop"
        link = desktop / "Out of Ore Mod Manager.lnk"
        try:
            # PowerShell COM shortcut
            ps = f"""
$ws = New-Object -ComObject WScript.Shell
$s = $ws.CreateShortcut('{str(link).replace("'", "''")}')
$s.TargetPath = '{str(target).replace("'", "''")}'
$s.WorkingDirectory = '{str(target.parent).replace("'", "''")}'
$s.Description = 'Out of Ore Mod Manager'
$s.Save()
"""
            import subprocess

            subprocess.run(
                ["powershell", "-NoProfile", "-Command", ps],
                check=False,
                capture_output=True,
            )
            if link.is_file():
                self.log(f"Desktop shortcut: {link}")
            else:
                self.log("Could not create desktop shortcut (optional).")
        except Exception as e:
            self.log(f"Shortcut failed: {e}")


def main() -> None:
    app = InstallerApp()
    app.mainloop()


if __name__ == "__main__":
    main()
