#!/bin/bash
# ─── Caelestia-Shell Post-Install Setup ───────────────────────────────────────
# Run this ONCE after caelestia-shell and vicinae are installed
# This script configures the shell for use with JaKooLit dotfiles

set -e

GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
RED='\033[0;31m'
NC='\033[0m' # No Color

print_step() { echo -e "${BLUE}[*]${NC} $1"; }
print_ok() { echo -e "${GREEN}[✓]${NC} $1"; }
print_warn() { echo -e "${YELLOW}[!]${NC} $1"; }
print_err() { echo -e "${RED}[✗]${NC} $1"; }

echo ""
echo -e "${BLUE}╔════════════════════════════════════════════════════════╗${NC}"
echo -e "${BLUE}║   Caelestia-Shell + JaKooLit Setup Script             ║${NC}"
echo -e "${BLUE}╚════════════════════════════════════════════════════════╝${NC}"
echo ""

# ─── 1. Check installed packages ──────────────────────────────────────────────
print_step "Checking required packages..."

MISSING=()
for pkg in caelestia-shell caelestia-cli vicinae quickshell; do
    if ! yay -Q "$pkg" &>/dev/null; then
        MISSING+=("$pkg")
    fi
done

if [ ${#MISSING[@]} -ne 0 ]; then
    print_err "Missing packages: ${MISSING[*]}"
    print_warn "Install them with: yay -S ${MISSING[*]}"
    exit 1
fi
print_ok "All required packages installed"

# ─── 2. Check caelestia-cli ───────────────────────────────────────────────────
print_step "Verifying caelestia-cli..."
if command -v caelestia &>/dev/null; then
    print_ok "caelestia-cli found: $(caelestia --version 2>/dev/null || echo 'ok')"
else
    print_err "caelestia-cli not found in PATH"
    print_warn "Try: yay -S caelestia-cli"
fi

# ─── 3. Config directory ──────────────────────────────────────────────────────
print_step "Setting up ~/.config/caelestia/..."
mkdir -p ~/.config/caelestia/monitors
print_ok "Config directory ready"

# ─── 4. Profile picture ───────────────────────────────────────────────────────
if [ ! -f ~/.face ]; then
    print_warn "No ~/.face file found (used for dashboard profile picture)"
    print_warn "Copy your avatar: cp /path/to/your/avatar.jpg ~/.face"
else
    print_ok "Profile picture found at ~/.face"
fi

# ─── 5. Set initial wallpaper ─────────────────────────────────────────────────
WALLPAPER_DIR="$HOME/Pictures/wallpapers"
if [ -d "$WALLPAPER_DIR" ]; then
    FIRST_WALL=$(ls "$WALLPAPER_DIR"/*.{jpg,png,webp} 2>/dev/null | head -1)
    if [ -n "$FIRST_WALL" ]; then
        print_step "Setting initial wallpaper: $FIRST_WALL"
        # Use swww if caelestia-shell isn't running yet
        if pgrep -x "swww-daemon" &>/dev/null; then
            swww img "$FIRST_WALL" --transition-type fade --transition-duration 1
            print_ok "Wallpaper set via swww"
        else
            print_warn "swww-daemon not running, start Hyprland first"
        fi
    else
        print_warn "No wallpapers found in $WALLPAPER_DIR"
    fi
fi

# ─── 6. Kill waybar if running ────────────────────────────────────────────────
if pgrep -x waybar &>/dev/null; then
    print_step "Stopping waybar..."
    pkill waybar || true
    print_ok "Waybar stopped"
fi

# ─── 7. Stop swaync if running ────────────────────────────────────────────────
if pgrep -x swaync &>/dev/null; then
    print_step "Stopping swaync (caelestia handles notifications)..."
    pkill swaync || true
    print_ok "swaync stopped"
fi

# ─── 8. Start caelestia-shell ─────────────────────────────────────────────────
print_step "Starting caelestia-shell..."
if command -v caelestia &>/dev/null; then
    caelestia shell -d &
    sleep 2
    if pgrep -f "caelestia" &>/dev/null; then
        print_ok "Caelestia-shell started!"
    else
        print_warn "Caelestia may have failed to start. Check: journalctl --user -u quickshell"
    fi
else
    print_err "caelestia command not found"
fi

echo ""
echo -e "${GREEN}╔════════════════════════════════════════════════════════╗${NC}"
echo -e "${GREEN}║   Setup complete! Here's what was configured:          ║${NC}"
echo -e "${GREEN}╠════════════════════════════════════════════════════════╣${NC}"
echo -e "${GREEN}║   • caelestia-shell replaces waybar                   ║${NC}"
echo -e "${GREEN}║   • vicinae is your new app launcher (Super+D)         ║${NC}"
echo -e "${GREEN}║   • Terminal: kitty (Super+Return)                     ║${NC}"
echo -e "${GREEN}║   • Files: nautilus (Super+E)                          ║${NC}"
echo -e "${GREEN}║   • Dashboard: Super+TAB                               ║${NC}"
echo -e "${GREEN}║   • Launcher (caelestia): press Super key              ║${NC}"
echo -e "${GREEN}║   • Lock: Super+L                                      ║${NC}"
echo -e "${GREEN}║   • Restart shell: Ctrl+Super+Shift+R                 ║${NC}"
echo -e "${GREEN}╠════════════════════════════════════════════════════════╣${NC}"
echo -e "${GREEN}║   Restore waybar: cp -r ~/.config/waybar.backup-*/    ║${NC}"
echo -e "${GREEN}║                      ~/.config/waybar                  ║${NC}"
echo -e "${GREEN}╚════════════════════════════════════════════════════════╝${NC}"
echo ""
