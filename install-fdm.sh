#!/bin/bash
# install-fdm.sh — Manual installer for Free Download Manager on Fedora 44 / GNOME 50
# Usage: bash install-fdm.sh [path/to/freedownloadmanager.deb]
#        If no .deb path is given, the script looks in ~/Downloads automatically.

set -e

# ─────────────────────────────────────────────
# Colours
# ─────────────────────────────────────────────
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
BOLD='\033[1m'
NC='\033[0m' # No Colour

info()    { echo -e "${BLUE}[INFO]${NC}  $*"; }
success() { echo -e "${GREEN}[OK]${NC}    $*"; }
warn()    { echo -e "${YELLOW}[WARN]${NC}  $*"; }
error()   { echo -e "${RED}[ERROR]${NC} $*"; exit 1; }
step()    { echo -e "\n${BOLD}── $* ${NC}"; }

# ─────────────────────────────────────────────
# Banner
# ─────────────────────────────────────────────
echo -e "${BOLD}"
echo "╔══════════════════════════════════════════════════╗"
echo "║   Free Download Manager — Fedora Manual Installer  ║"
echo "║   Tested on Fedora 44 / GNOME 50                   ║"
echo "╚══════════════════════════════════════════════════╝"
echo -e "${NC}"

# ─────────────────────────────────────────────
# Uninstall mode
# ─────────────────────────────────────────────
if [ "$1" = "--uninstall" ]; then
    step "Uninstalling FDM"
    sudo rm -rf /opt/freedownloadmanager
    sudo rm -f /usr/share/applications/freedownloadmanager.desktop
    sudo rm -f /usr/share/pixmaps/fdm.png
    sudo update-desktop-database
    read -rp "Also remove saved settings and download history? [y/N]: " purge
    [[ "$purge" =~ ^[Yy]$ ]] && rm -rf "$HOME/.local/share/Free Download Manager"
    success "FDM uninstalled"
    exit 0
fi

# ─────────────────────────────────────────────
# Locate the .deb
# ─────────────────────────────────────────────
step "Locating .deb package"

if [ -n "$1" ]; then
    DEB="$1"
else
    DEB="$HOME/Downloads/freedownloadmanager.deb"
fi

[ -f "$DEB" ] || error "Cannot find .deb at '$DEB'. Usage: bash install-fdm.sh [path/to/freedownloadmanager.deb]"
success "Found: $DEB"

# ─────────────────────────────────────────────
# Check for existing installation
# ─────────────────────────────────────────────
if [ -d /opt/freedownloadmanager ]; then
    warn "FDM is already installed at /opt/freedownloadmanager."
    read -rp "Reinstall/overwrite? [y/N]: " confirm
    [[ "$confirm" =~ ^[Yy]$ ]] || { echo "Aborted."; exit 0; }
fi

# ─────────────────────────────────────────────
# Phase 1: Dependencies
# ─────────────────────────────────────────────
step "Phase 1: Installing dependencies"
info "Installing binutils, patchelf, openssl-libs, libX11, xcb-util..."
sudo dnf install -y binutils patchelf openssl-libs libX11 xcb-util
success "Dependencies installed"

# ─────────────────────────────────────────────
# Phase 2: Extraction
# ─────────────────────────────────────────────
step "Phase 2: Extracting .deb"

WORKDIR=$(mktemp -d)
info "Working directory: $WORKDIR"
trap 'rm -rf "$WORKDIR"' EXIT

cp "$DEB" "$WORKDIR/freedownloadmanager.deb"
cd "$WORKDIR"
ar x freedownloadmanager.deb

if [ -f data.tar.zst ]; then
    info "Detected data.tar.zst (newer dpkg format)"
    tar -xf data.tar.zst
elif [ -f data.tar.xz ]; then
    info "Detected data.tar.xz"
    tar -xf data.tar.xz
else
    error "Cannot find data.tar.* inside the .deb — unsupported format"
fi

success "Extraction complete"

# ─────────────────────────────────────────────
# Phase 3: Install files
# ─────────────────────────────────────────────
step "Phase 3: Installing application files"

sudo mkdir -p /opt/freedownloadmanager
sudo cp -r opt/freedownloadmanager/* /opt/freedownloadmanager/
success "Copied application to /opt/freedownloadmanager"

sudo cp usr/share/applications/freedownloadmanager.desktop /usr/share/applications/
success "Installed desktop launcher"

# Icon — handle both naming schemes across FDM versions
if [ -f /opt/freedownloadmanager/icon.png ]; then
    sudo cp /opt/freedownloadmanager/icon.png /usr/share/pixmaps/fdm.png
elif [ -f /opt/freedownloadmanager/fdm.png ]; then
    sudo cp /opt/freedownloadmanager/fdm.png /usr/share/pixmaps/fdm.png
else
    warn "No icon found — app will launch without a taskbar icon"
fi
success "Icon installed"

# ─────────────────────────────────────────────
# Phase 4: RPATH fix
# ─────────────────────────────────────────────
step "Phase 4: Fixing bundled library paths (RPATH)"
info "FDM's binaries contain a hardcoded Jenkins build-machine path."
info "Patching with patchelf so they find their bundled Qt6 libs..."

for binary in /opt/freedownloadmanager/fdm /opt/freedownloadmanager/wenativehost; do
    if [ -f "$binary" ]; then
        sudo patchelf --set-rpath '$ORIGIN:$ORIGIN/lib:$ORIGIN/plugins/platforms' "$binary"
        success "Patched: $binary"
    fi
done

for solib in /opt/freedownloadmanager/lib/libdownloads*.so* \
             /opt/freedownloadmanager/lib/liblogger*.so* \
             /opt/freedownloadmanager/lib/libquazip*.so* \
             /opt/freedownloadmanager/lib/libvmsclshared*.so*; do
    if [ -f "$solib" ] && [ ! -L "$solib" ]; then
        sudo patchelf --set-rpath '$ORIGIN' "$solib"
    fi
done
success "All library RPATHs patched"

# Verify
RPATH=$(patchelf --print-rpath /opt/freedownloadmanager/fdm)
info "Verified RPATH: $RPATH"

# ─────────────────────────────────────────────
# Phase 5: Wayland / XCB fix
# ─────────────────────────────────────────────
step "Phase 5: Applying Wayland / XCB fix"
info "FDM's bundled Qt6 lacks xdg-decoration protocol support."
info "Forcing XCB (XWayland) mode for stable rendering on GNOME 50..."

sudo sed -i 's|Exec=/opt/freedownloadmanager/fdm|Exec=env QT_QPA_PLATFORM=xcb /opt/freedownloadmanager/fdm|g' \
    /usr/share/applications/freedownloadmanager.desktop

sudo update-desktop-database
success "Wayland/XCB fix applied"

# ─────────────────────────────────────────────
# Done
# ─────────────────────────────────────────────
echo -e "\n${GREEN}${BOLD}Installation complete!${NC}"
echo -e "FDM is now available in your GNOME app grid."
echo -e "You can also launch it from the terminal:\n"
echo -e "  ${BOLD}QT_QPA_PLATFORM=xcb /opt/freedownloadmanager/fdm${NC}\n"
echo -e "${YELLOW}Note:${NC} Window corners will appear square — this is a known limitation"
echo -e "of FDM's bundled Qt6 (missing xdg-decoration protocol support)."
echo -e "Install 'Rounded Window Corners Reloaded' from extensions.gnome.org to fix it.\n"
echo -e "To uninstall, run:  ${BOLD}bash install-fdm.sh --uninstall${NC}"
