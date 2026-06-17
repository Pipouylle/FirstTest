#!/usr/bin/env python3
import sys
import os
import hashlib
from pathlib import Path
import subprocess
import datetime

def get_hash(path_str):
    real_path = os.path.realpath(path_str)
    return hashlib.md5(real_path.encode('utf-8')).hexdigest()

def log_message(msg):
    log_path = Path.home() / "set_wallpaper.log"
    timestamp = datetime.datetime.now().isoformat()
    with open(log_path, "a") as f:
        f.write(f"[{timestamp}] {msg}\n")

def main():
    log_message(f"Script started with args: {sys.argv}")
    if len(sys.argv) < 2:
        log_message("Error: missing argument")
        sys.exit(1)

    clicked_path = Path(sys.argv[1]).resolve()
    target_path = clicked_path
    log_message(f"Clicked path: {clicked_path}")

    # If the clicked file is a waypaper cached thumbnail
    if clicked_path.parent.name == "waypaper" and clicked_path.suffix == ".png":
        clicked_hash = clicked_path.stem
        log_message(f"Detected waypaper thumbnail with hash: {clicked_hash}")
        
        # Scan Steam workshop folder
        workshop_dir = Path.home() / ".steam/root/steamapps/workshop/content/431960"
        found_path = None
        
        if workshop_dir.exists():
            for p in workshop_dir.glob("**/preview.*"):
                if get_hash(str(p)) == clicked_hash:
                    found_path = p
                    break
        
        # Scan other potential wallpaper folders
        if not found_path:
            pictures_dir = Path.home() / "Pictures"
            if pictures_dir.exists():
                for p in pictures_dir.glob("**/*"):
                    if p.is_file() and p.suffix.lower() in [".jpg", ".jpeg", ".png", ".webp"]:
                        try:
                            if get_hash(str(p)) == clicked_hash:
                                found_path = p
                                break
                        except Exception:
                            continue

        if found_path:
            log_message(f"Successfully mapped to high-res: {found_path}")
            target_path = found_path
        else:
            log_message("Warning: could not find matching high-res wallpaper")

    # Update Caelestia's path.txt so the QML shell renders the high-res file
    path_txt = Path.home() / ".local/state/caelestia/wallpaper/path.txt"
    try:
        path_txt.parent.mkdir(parents=True, exist_ok=True)
        path_txt.write_text(str(target_path))
        log_message(f"Updated caelestia path.txt to: {target_path}")
    except Exception as e:
        log_message(f"Error writing path.txt: {e}")

    # Run waypaper
    log_message(f"Running waypaper --wallpaper {target_path}")
    res = subprocess.run(["waypaper", "--wallpaper", str(target_path)], capture_output=True, text=True)
    log_message(f"Waypaper return code: {res.returncode}")
    log_message(f"Waypaper stdout: {res.stdout.strip()}")
    log_message(f"Waypaper stderr: {res.stderr.strip()}")

if __name__ == "__main__":
    main()
