Name:           freedownloadmanager
Version:        6.22
Release:        3%{?dist}
Summary:        A powerful and easy-to-use download manager
License:        Proprietary
URL:            https://www.freedownloadmanager.org/
Source0:        freedownloadmanager.deb

# Tell rpmbuild NOT to strip or mangle the bundled binaries
%global __strip /bin/true
%global _build_id_links none

# Suppress the RPATH check (0x0002 = invalid RPATHs).
# These are pre-built proprietary binaries — we cannot recompile them.
# We fix the bad RPATH with patchelf in %install instead.
%global __arch_install_post \
    export QA_RPATHS=0x0002 \
    %{__arch_install_post}

# Don't let rpmbuild auto-generate Requires from the bundled .so files
AutoReqProv:    no

# patchelf is only needed at build time to fix the bad RPATH — not at runtime
BuildRequires:  patchelf

# Runtime dependencies FDM needs (Qt6 — the .deb bundles Qt6, NOT Qt5)
Requires:       openssl-libs
Requires:       libX11
Requires:       xcb-util

%description
Free Download Manager (FDM) is a popular download manager that
allows you to monitor and accelerate downloads.
Repackaged from the official .deb for Fedora, with the following fixes:
- Wayland/XCB fix for stable rendering on GNOME 50
- RPATH fix so bundled Qt6 libs are found correctly
- AppStream metainfo so GNOME Software shows FDM as an application

%prep
mkdir -p %{_builddir}/%{name}-%{version}
cd %{_builddir}/%{name}-%{version}
ar x %{SOURCE0}
# The .deb may use data.tar.xz or data.tar.zst depending on version
if [ -f data.tar.zst ]; then
    tar -xvf data.tar.zst
elif [ -f data.tar.xz ]; then
    tar -xvf data.tar.xz
else
    echo "ERROR: Cannot find data.tar.*" && exit 1
fi

%build
# No compilation needed

%install
cd %{_builddir}/%{name}-%{version}

mkdir -p %{buildroot}/opt/freedownloadmanager
mkdir -p %{buildroot}/usr/share/applications
mkdir -p %{buildroot}/usr/share/pixmaps
mkdir -p %{buildroot}/usr/share/metainfo
mkdir -p %{buildroot}/usr/bin

# Copy the application files
cp -r opt/freedownloadmanager/* %{buildroot}/opt/freedownloadmanager/

# Use icon.png (the .deb ships icon.png, not fdm.png)
cp opt/freedownloadmanager/icon.png %{buildroot}/usr/share/pixmaps/fdm.png

# Copy and patch the .desktop file
cp usr/share/applications/freedownloadmanager.desktop %{buildroot}/usr/share/applications/

# Apply the Wayland/XCB fix to the .desktop launcher
# Note: FDM's bundled Qt6 lacks xdg-decoration protocol support so native
# Wayland produces square corners identical to XCB. XCB is more stable.
sed -i 's|Exec=/opt/freedownloadmanager/fdm|Exec=env QT_QPA_PLATFORM=xcb /opt/freedownloadmanager/fdm|g' \
    %{buildroot}/usr/share/applications/freedownloadmanager.desktop

# Create a convenience symlink in /usr/bin (relative path avoids rpmbuild warning)
ln -sf ../../opt/freedownloadmanager/fdm %{buildroot}/usr/bin/fdm

# ---------------------------------------------------------------
# APPSTREAM METAINFO
# Without this GNOME Software shows FDM as a raw package, not an app.
# ---------------------------------------------------------------
cat > %{buildroot}/usr/share/metainfo/freedownloadmanager.metainfo.xml << 'EOF'
<?xml version="1.0" encoding="UTF-8"?>
<component type="desktop-application">
  <id>freedownloadmanager</id>
  <name>Free Download Manager</name>
  <summary>A powerful and easy-to-use download manager</summary>
  <description>
    <p>Free Download Manager lets you adjust traffic usage, organize
    downloads, control file priorities for torrents, and much more.</p>
  </description>
  <url type="homepage">https://www.freedownloadmanager.org/</url>
  <launchable type="desktop-id">freedownloadmanager.desktop</launchable>
  <icon type="stock">fdm</icon>
  <categories>
    <category>Network</category>
    <category>FileTransfer</category>
  </categories>
  <releases>
    <release version="6.22" date="2026-04-05"/>
  </releases>
</component>
EOF

# ---------------------------------------------------------------
# SILENCE THE QML / qt.conf EXECUTABLE BIT WARNINGS
# The .deb ships hundreds of .qml and config files with +x set.
# Strip it here so rpmbuild's brp scripts don't flood the build log.
# ---------------------------------------------------------------
find %{buildroot}/opt/freedownloadmanager/qml -type f \
    \( -name "*.qml" -o -name "*.qmltypes" -o -name "qmldir" \) \
    -exec chmod -x {} \;
chmod -x %{buildroot}/opt/freedownloadmanager/qt.conf 2>/dev/null || true

# ---------------------------------------------------------------
# FIX THE BAD RPATH
# The binaries have /home/jenkins/Qt/6.10.1/gcc_64/lib hardcoded.
# Replace it with $ORIGIN so they find their bundled Qt libs.
# ---------------------------------------------------------------
for binary in \
    %{buildroot}/opt/freedownloadmanager/fdm \
    %{buildroot}/opt/freedownloadmanager/wenativehost \
    %{buildroot}/opt/freedownloadmanager/lib/*.so*; do
    if [ -f "$binary" ] && [ ! -L "$binary" ]; then
        patchelf --remove-rpath "$binary" 2>/dev/null || true
        patchelf --set-rpath '$ORIGIN:$ORIGIN/lib:$ORIGIN/plugins/platforms' "$binary" 2>/dev/null || true
    fi
done

# Fix RPATH on the bundled FDM .so libs (they only need $ORIGIN)
for solib in %{buildroot}/opt/freedownloadmanager/lib/libdownloads*.so* \
             %{buildroot}/opt/freedownloadmanager/lib/liblogger*.so* \
             %{buildroot}/opt/freedownloadmanager/lib/libquazip*.so* \
             %{buildroot}/opt/freedownloadmanager/lib/libvmsclshared*.so*; do
    if [ -f "$solib" ] && [ ! -L "$solib" ]; then
        patchelf --set-rpath '$ORIGIN' "$solib" 2>/dev/null || true
    fi
done

%files
/opt/freedownloadmanager/
/usr/share/applications/freedownloadmanager.desktop
/usr/share/pixmaps/fdm.png
/usr/share/metainfo/freedownloadmanager.metainfo.xml
/usr/bin/fdm

%changelog
* Sun Apr 05 2026 Bethel - 6.22-3
- Added AppStream metainfo so GNOME Software shows FDM as an application
- Documented XCB fix rationale (Qt6 lacks xdg-decoration protocol support)

* Sun Apr 05 2026 Bethel - 6.22-2
- Moved patchelf from Requires to BuildRequires (build-time tool, not runtime dep)
- Strip execute bit from .qml/qmltypes/qmldir/qt.conf files to silence brp warnings
- Symlink uses relative path ../../opt/... (no absolute symlink warning)

* Sun Apr 05 2026 Bethel - 6.22-1
- Initial RPM build with Wayland XCB fix
- Fixed invalid Jenkins RPATH using patchelf
- Corrected icon path (icon.png not fdm.png)
- Added /usr/bin/fdm symlink
- Disabled AutoReqProv for bundled Qt6 libs
