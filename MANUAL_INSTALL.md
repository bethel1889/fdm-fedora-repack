# Manual Installation — Free Download Manager on Fedora 44 / GNOME 50

This guide covers the manual extraction method: a direct way to get FDM running without the RPM build system. It incorporates the Wayland fix, the RPATH fix, the icon path fix, and the data archive format fallback.

> **Tip:** If you want clean `dnf`-managed installs and easy uninstallation, use the RPM method instead. The manual method is faster but leaves no package database entry — you uninstall by deleting files yourself.

---

## Phase 1: Preparation

Install the extraction and patching tools FDM needs on Fedora. Note that FDM bundles its own Qt6 — do **not** install `qt5-qtbase-gui`.

```bash
sudo dnf install binutils patchelf openssl-libs libX11 xcb-util
```

---

## Phase 2: Extraction

```bash
cd ~/Downloads
mkdir -p fdm-manual && cd fdm-manual

# Extract the Debian package structure
ar x ../freedownloadmanager.deb

# Extract the application data — handle both .xz (older) and .zst (newer dpkg)
if [ -f data.tar.zst ]; then
    tar -xvf data.tar.zst
elif [ -f data.tar.xz ]; then
    tar -xvf data.tar.xz
else
    echo "ERROR: Cannot find data.tar.*" && exit 1
fi
```

---

## Phase 3: Manual Installation

**1. Copy the application files:**

```bash
sudo mkdir -p /opt/freedownloadmanager
sudo cp -r opt/freedownloadmanager/* /opt/freedownloadmanager/
```

**2. Install the desktop launcher:**

```bash
sudo cp usr/share/applications/freedownloadmanager.desktop /usr/share/applications/
```

**3. Install the icon:**

The `.deb` ships `icon.png`. This command covers both naming schemes found across FDM versions:

```bash
sudo cp /opt/freedownloadmanager/icon.png /usr/share/pixmaps/fdm.png 2>/dev/null || \
sudo cp /opt/freedownloadmanager/fdm.png /usr/share/pixmaps/fdm.png
```

---

## Phase 4: Fix the Bundled Library Paths (RPATH)

This step is **required**. FDM's binaries were compiled with a hardcoded path to the developer's build machine (`/home/jenkins/Qt/6.10.1/gcc_64/lib`). That path does not exist on your system, so without this fix FDM will crash on launch with a library error.

`patchelf` rewrites the embedded library search path to use `$ORIGIN` — a dynamic reference to the binary's own directory — so FDM correctly finds its bundled Qt6 libs at runtime.

```bash
# Fix the main binary and wenativehost
for binary in /opt/freedownloadmanager/fdm /opt/freedownloadmanager/wenativehost; do
    if [ -f "$binary" ]; then
        sudo patchelf --set-rpath '$ORIGIN:$ORIGIN/lib:$ORIGIN/plugins/platforms' "$binary"
    fi
done

# Fix the bundled FDM .so libraries
for solib in /opt/freedownloadmanager/lib/libdownloads*.so* \
             /opt/freedownloadmanager/lib/liblogger*.so* \
             /opt/freedownloadmanager/lib/libquazip*.so* \
             /opt/freedownloadmanager/lib/libvmsclshared*.so*; do
    if [ -f "$solib" ] && [ ! -L "$solib" ]; then
        sudo patchelf --set-rpath '$ORIGIN' "$solib"
    fi
done
```

You can verify the fix was applied:

```bash
patchelf --print-rpath /opt/freedownloadmanager/fdm
# Expected: $ORIGIN:$ORIGIN/lib:$ORIGIN/plugins/platforms
```

---

## Phase 5: The Wayland / XCB Fix

Fedora 44 runs GNOME 50 on Wayland. FDM's Qt6 must be forced into XCB (XWayland) mode or it will show a blank window or crash.

```bash
# Patch the Exec= line in the desktop launcher
sudo sed -i 's|Exec=/opt/freedownloadmanager/fdm|Exec=env QT_QPA_PLATFORM=xcb /opt/freedownloadmanager/fdm|g' \
    /usr/share/applications/freedownloadmanager.desktop

# Refresh the desktop database so the icon appears in GNOME
sudo update-desktop-database
```

---

## Phase 6: Cleanup

```bash
cd ~/Downloads
rm -rf fdm-manual
```

FDM will now appear in your GNOME app grid. You can also run it from a terminal:

```bash
QT_QPA_PLATFORM=xcb /opt/freedownloadmanager/fdm
```

---

## Uninstalling

Because this method bypasses the package manager, you remove FDM by deleting the files manually:

```bash
sudo rm -rf /opt/freedownloadmanager
sudo rm /usr/share/applications/freedownloadmanager.desktop
sudo rm /usr/share/pixmaps/fdm.png
# Optionally remove saved settings and download history
rm -rf ~/.local/share/Free\ Download\ Manager
```

---
