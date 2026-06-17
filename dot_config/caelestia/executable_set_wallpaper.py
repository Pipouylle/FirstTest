#!/usr/bin/env python3
import sys
import os
import hashlib
from pathlib import Path
import subprocess

def get_hash(path_str):
    real_path = os.path.realpath(path_str)
    return hashlib.md5(real_path.encode('utf-8')).hexdigest()

def main():
    if len(sys.argv) < 2:
        sys.exit(1)

    clicked_path = Path(sys.argv[1]).resolve()
    target_path = clicked_path

    # If the clicked file is a waypaper cached thumbnail
    if clicked_path.parent.name == "waypaper" and clicked_path.suffix == ".png":
        clicked_hash = clicked_path.stem
        
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
            target_path = found_path

    # Run waypaper
    subprocess.run(["waypaper", "--wallpaper", str(target_path)])

if __name__ == "__main__":
    main()
