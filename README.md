# fdm-fedora — Free Download Manager for Fedora

Repackages the official Free Download Manager `.deb` as a native Fedora RPM, with automatic RPATH, Wayland/XCB, and AppStream fixes baked in. Includes a manual installation guide and script for those who prefer not to use RPM.

---

## Tested On

| Component | Version |
|-----------|---------|
| Fedora | 44 Beta |
| GNOME | 50 |
| FDM | 6.22 |
| RPM build tools | fc44 |

---

## Known Limitations

- **Window corners are square.** FDM's bundled Qt6 was compiled without `xdg-decoration` protocol support, which is what GNOME uses to apply rounded corners to non-GTK windows. This affects both XCB and native Wayland modes equally and cannot be fixed without FDM recompiling their Qt6. If this bothers you, install the [Rounded Window Corners Reloaded](https://extensions.gnome.org/extension/5237/rounded-window-corners-reloaded/) GNOME extension.

---

## Installation Methods

There are two ways to install FDM using this repo. Choose whichever suits you:

### Method 1 — RPM Package (Recommended)

Build and install a proper `.rpm` using Fedora's package manager. This is the cleanest approach — `dnf` tracks every file and uninstallation is a single command.

**Install and uninstall via terminal:**
```bash
sudo dnf install freedownloadmanager-6.22-1.fc44.x86_64.rpm
sudo dnf remove freedownloadmanager
```

**Install and uninstall via GNOME Software:**
You can also install and uninstall through the GNOME Software GUI. A few things to be aware of:
- Right-clicking and viewing app details will not show full details in the Software Center
- To uninstall via GUI, open GNOME Software → go to the **Installed** section → scroll to **F** (apps are listed alphabetically) → find Free Download Manager → uninstall from there
- The app will not display its official icon inside GNOME Software, only in the app grid after installation
- If you install via terminal (`dnf`), uninstall via terminal. If you install via GNOME Software, uninstall via GNOME Software. Don't mix the two.

> **Security note:** Downloading pre-built RPMs from individuals on the internet carries inherent risk. It is strongly recommended that you build the RPM yourself using the instructions below — that way you know exactly what is in the package.

---

### Method 2 — Manual Install Script

Extracts the `.deb` and places the files manually without using the RPM build system. Faster to get started but leaves no package manager entry — uninstallation is handled by running the same script with the `--uninstall` flag.

```bash
# Install
bash install-fdm.sh

# Or specify a custom path to the .deb
bash install-fdm.sh ~/Downloads/freedownloadmanager.deb

# Uninstall
bash install-fdm.sh --uninstall
```

See [`MANUAL_INSTALL.md`](MANUAL_INSTALL.md) for the full step-by-step guide.

---

## Building the RPM Yourself

### Prerequisites

Install the required build tools:

```bash
sudo dnf install rpm-build rpmdevtools
```

Set up the standard RPM build tree (only needed once):

```bash
rpmdev-setuptree
```

### Step-by-Step

**1. Download the official FDM `.deb`**

Go to [freedownloadmanager.org](https://www.freedownloadmanager.org/) and download the Linux `.deb` package. At time of writing the filename is `freedownloadmanager.deb`.

**2. Place the `.deb` in your SOURCES folder**

```bash
cp ~/Downloads/freedownloadmanager.deb ~/rpmbuild/SOURCES/
```

**3. Copy the spec file into place**

```bash
cp fdm.spec ~/rpmbuild/SPECS/fdm.spec
```

**4. Build the RPM**

```bash
rpmbuild -ba ~/rpmbuild/SPECS/fdm.spec
```

A successful build will print two lines at the end like:

```
Wrote: /home/<you>/rpmbuild/SRPMS/freedownloadmanager-6.22-1.fc44.src.rpm
Wrote: /home/<you>/rpmbuild/RPMS/x86_64/freedownloadmanager-6.22-1.fc44.x86_64.rpm
```

**5. Install**

```bash
sudo dnf install ~/rpmbuild/RPMS/x86_64/freedownloadmanager-*.rpm
```

FDM will appear in your GNOME app grid. You can also launch it from the terminal with `fdm`.

---

## What the Spec Does (Technical Summary)

| Problem | Solution in spec |
|---------|-----------------|
| FDM `.deb` binaries contain a hardcoded build-machine RPATH (`/home/jenkins/Qt/...`) | `patchelf --set-rpath` replaces it with `$ORIGIN`-relative paths in `%install` |
| RPM's QA check (`check-rpaths`) blocks the build on `ERROR 0002` | `QA_RPATHS=0x0002` suppresses the check as a safety net after patchelf already fixed the root cause |
| FDM crashes or shows a blank window on Wayland / GNOME 50 | `sed` patches the `.desktop` `Exec=` line to prepend `env QT_QPA_PLATFORM=xcb` |
| The `.deb` ships Qt6, not Qt5 | `AutoReqProv: no` prevents rpmbuild from auto-pulling conflicting system Qt packages |
| The `.deb` icon is `icon.png`, not `fdm.png` | Corrected copy path in `%install` |
| Hundreds of `.qml`/`qt.conf` files have the execute bit set | `find ... -exec chmod -x` strips it in `%install`, silencing brp warnings |
| GNOME Software shows FDM as a raw package, not an application | AppStream metainfo XML bundled in the RPM |

---

## Updating to a New FDM Version

1. Download the new `.deb` and drop it in `~/rpmbuild/SOURCES/`.
2. Edit `fdm.spec` — update the `Version:` field and add a `%changelog` entry.
3. Run `rpmbuild -ba ~/rpmbuild/SPECS/fdm.spec` again.

---

## Repository Structure

```
.
├── fdm.spec              # The RPM spec file
├── install-fdm.sh        # Manual installation and uninstallation script
├── README.md             # This file
├── MANUAL_INSTALL.md     # Step-by-step manual install guide
└── TROUBLESHOOTING.md    # Common build and runtime errors
```

> **Note:** The `.deb` source file is not included — download it directly from the official FDM website to ensure you always get the latest version and to respect their distribution terms.

---

## License

The spec file, scripts, and documentation in this repository are released to the public domain. Free Download Manager itself is proprietary software owned by FreeDownloadManager.ORG.
