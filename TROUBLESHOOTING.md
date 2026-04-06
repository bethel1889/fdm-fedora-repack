# Troubleshooting

## Build Errors

### `ERROR 0002: file contains an invalid runpath`

**Cause:** The FDM binaries were compiled with a hardcoded path to the developer's Qt installation (`/home/jenkins/Qt/6.10.1/gcc_64/lib`). RPM's RPATH security check catches this and fails the build.

**Fix:** Make sure you are using the spec file from this repo. It runs `patchelf` during `%install` to replace all bad RPATHs with `$ORIGIN`-relative paths. If you are still seeing this error, confirm `patchelf` is installed:

```bash
patchelf --version
# If not found:
sudo dnf install patchelf
```

---

### `cp: cannot stat 'opt/freedownloadmanager/fdm.png': No such file or directory`

**Cause:** The `.deb` ships `icon.png`, not `fdm.png`. An older version of the spec had the wrong filename.

**Fix:** Use the spec file from this repo — it copies `icon.png` correctly.

---

### `ERROR: Cannot find data.tar.*`

**Cause:** Newer versions of `dpkg` produce `data.tar.zst` (Zstandard) instead of `data.tar.xz`. The `%prep` section checks for both, but something went wrong with extraction.

**Fix:** Inspect what's actually inside the `.deb`:

```bash
cd /tmp && cp ~/Downloads/freedownloadmanager.deb . && ar t freedownloadmanager.deb
```

You should see either `data.tar.xz` or `data.tar.zst` listed. If you see a different extension, open an issue and paste the output.

---

### `Bad exit status from %install`

This is a generic catch-all. Scroll up in the `rpmbuild` output to find the first line that says `ERROR` or `cannot` — that is the real cause. Common culprits are the RPATH error (see above) or a missing file during `cp`.

---

## Runtime Issues

### FDM launches but the window is blank / invisible

**Cause:** FDM's Qt6 is trying to use the native Wayland compositor directly and failing silently.

**Fix:** The spec file patches the `.desktop` launcher automatically. If you installed FDM a different way (e.g. directly from the `.deb`), you can apply the fix manually:

```bash
sudo sed -i 's|Exec=/opt/freedownloadmanager/fdm|Exec=env QT_QPA_PLATFORM=xcb /opt/freedownloadmanager/fdm|g' \
    /usr/share/applications/freedownloadmanager.desktop
```

Or launch it from the terminal to test:

```bash
QT_QPA_PLATFORM=xcb /opt/freedownloadmanager/fdm
```

---

### FDM crashes immediately with `symbol lookup error` or `SIGSEGV`

**Cause:** The bundled Qt6 libraries cannot be found because the RPATH patch did not apply correctly.

**Fix:** Check the RPATH of the main binary:

```bash
patchelf --print-rpath /opt/freedownloadmanager/fdm
```

It should output something like `$ORIGIN:$ORIGIN/lib:$ORIGIN/plugins/platforms`. If it still shows `/home/jenkins/Qt/...`, the patchelf step did not run. Rebuild from scratch:

```bash
rm -rf ~/rpmbuild/BUILD/freedownloadmanager-*
rpmbuild -ba ~/rpmbuild/SPECS/fdm.spec
sudo dnf reinstall ~/rpmbuild/RPMS/x86_64/freedownloadmanager-*.rpm
```

---

### Browser extension / `fdm` command not found after install

The spec installs a symlink at `/usr/bin/fdm`. If it is missing:

```bash
ls -la /usr/bin/fdm
```

If absent, your installed package may be from an older spec version. Rebuild with the current spec and reinstall.

---

## Updating FDM

When a new FDM version is released:

1. Download the new `.deb` from [freedownloadmanager.org](https://www.freedownloadmanager.org/).
2. Replace the old source: `cp ~/Downloads/freedownloadmanager.deb ~/rpmbuild/SOURCES/`
3. Edit `fdm.spec` — bump `Version:` and add a `%changelog` entry.
4. Rebuild: `rpmbuild -ba ~/rpmbuild/SPECS/fdm.spec`
5. Upgrade: `sudo dnf upgrade ~/rpmbuild/RPMS/x86_64/freedownloadmanager-*.rpm`

`dnf upgrade` (not `install`) will cleanly replace the old package.
