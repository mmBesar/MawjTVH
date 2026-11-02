#!/usr/bin/env bash
# Packages a Flutter Linux release bundle as DEB, RPM and AppImage.
#
# Usage:
#   tool/package_linux.sh --bundle build/linux/x64/release/bundle \
#     --arch amd64 --version 0.1.0
#
# AppImage output requires appimagetool. Set APPIMAGETOOL to an existing
# binary, otherwise the script downloads one for the target architecture.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
BUNDLE=""
ARCH=""
VERSION=""
OUT="$ROOT/dist"
FORMATS="deb,rpm,appimage"

usage() {
  cat <<'EOF'
Usage: tool/package_linux.sh --bundle DIR --arch amd64|arm64 [options]

Options:
  --bundle DIR        Flutter Linux release bundle directory
  --arch ARCH         amd64 (x86_64) or arm64 (aarch64)
  --version VERSION   Package version (defaults to pubspec.yaml)
  --out DIR           Output directory (default: dist)
  --formats LIST      Comma-separated subset of deb,rpm,appimage
  -h, --help          Show this help
EOF
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --bundle) BUNDLE="${2:-}"; shift 2 ;;
    --arch) ARCH="${2:-}"; shift 2 ;;
    --version) VERSION="${2:-}"; shift 2 ;;
    --out) OUT="${2:-}"; shift 2 ;;
    --formats) FORMATS="${2:-}"; shift 2 ;;
    -h|--help) usage; exit 0 ;;
    *) echo "Unknown argument: $1" >&2; usage >&2; exit 2 ;;
  esac
done

if [[ -z "$BUNDLE" || -z "$ARCH" ]]; then
  usage >&2
  exit 2
fi

case "$ARCH" in
  amd64|x86_64)
    DEB_ARCH="amd64"
    RPM_ARCH="x86_64"
    APPIMAGE_ARCH="x86_64"
    ;;
  arm64|aarch64)
    DEB_ARCH="arm64"
    RPM_ARCH="aarch64"
    APPIMAGE_ARCH="aarch64"
    ;;
  *)
    echo "Unsupported architecture: $ARCH (expected amd64 or arm64)" >&2
    exit 2
    ;;
esac

BUNDLE="$(cd "$BUNDLE" && pwd)"
if [[ ! -x "$BUNDLE/mawjtvh" ]]; then
  echo "No executable 'mawjtvh' found in $BUNDLE" >&2
  exit 1
fi

if [[ -z "$VERSION" ]]; then
  VERSION="$(sed -n 's/^version: *\([0-9][0-9.]*\).*/\1/p' "$ROOT/pubspec.yaml" | head -n1)"
fi
if [[ ! "$VERSION" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
  echo "Invalid version: $VERSION" >&2
  exit 2
fi

ICON="$ROOT/assets/branding/linux/mawjtvh.png"
DESKTOP="$ROOT/assets/branding/mawjtvh.desktop"
if [[ ! -f "$ICON" ]]; then
  echo "Missing $ICON; run tool/generate_icons.py" >&2
  exit 1
fi
if [[ ! -f "$DESKTOP" ]]; then
  echo "Missing $DESKTOP" >&2
  exit 1
fi

# Libraries that must come from the host: glibc, graphics drivers, display
# servers and the desktop toolkit. Everything else (notably libmpv and its
# FFmpeg/libass closure, plus libraries the Flutter engine links directly) is
# shipped with the app so the AppImage runs on systems without mpv installed.
should_skip_lib() {
  case "$1" in
    ld-linux*|libc.so.*|libm.so.*|libdl.so.*|libpthread.so.*|librt.so.*|libresolv.so.*|libutil.so.*|libgcc_s.so.*|libstdc++.so.*|libnss_*.so.*|libjvm.so*|libjawt.so*)
      return 0 ;;
    libGL.so.*|libGLX.so.*|libGLdispatch.so.*|libOpenGL.so.*|libEGL.so.*|libgbm.so.*|libdrm.so.*|libvulkan.so.*|libnvidia-*.so.*)
      return 0 ;;
    libX11.so.*|libX11-xcb.so.*|libxcb*.so.*|libXau.so.*|libXdmcp.so.*|libXext.so.*|libXrender.so.*|libXfixes.so.*|libXi.so.*|libXrandr.so.*|libXcomposite.so.*|libXdamage.so.*|libXinerama.so.*|libXcursor.so.*|libwayland*.so.*|libxkbcommon*.so.*)
      return 0 ;;
    libgtk-3.so.*|libgdk-3.so.*|libgdk_pixbuf*.so.*|libglib-2.0.so.*|libgobject-2.0.so.*|libgio-2.0.so.*|libgmodule-2.0.so.*|libgthread-2.0.so.*|libpango*.so.*|libcairo*.so.*|libharfbuzz.so.*|libfontconfig.so.*|libfreetype.so.*|libatk*.so.*|libatspi*.so.*|librsvg-2.so.*)
      return 0 ;;
    libasound.so.*|libpulse*.so.*|libpipewire*.so.*|libdbus-1.so.*|libsystemd.so.*)
      return 0 ;;
    # Core system/glib dependencies. These are provided by every distro and
    # are also loaded by the host GTK stack, so an older bundled copy shadows
    # the host one and can break it (libmount's MOUNT_2_40 on NixOS).
    libmount.so.*|libblkid.so.*|libselinux.so.*|libpcre2-*.so.*|libapparmor.so.*|libexpat.so.*|libgraphite2.so.*|libdatrie.so.*|libthai.so.*|libpixman-1.so.*|libfribidi.so.*|libbrotli*.so.*|libz.so.*|liblzma.so.*|libudev.so.*|libcap.so.*)
      return 0 ;;
    # Keep bz2 bundled. Debian/Ubuntu's soname is libbz2.so.1.0 while NixOS
    # ships libbz2.so.1, so appimage-run's FHS rootfs cannot satisfy
    # libavformat/libarchive even though it has bzip2 installed. Bundling the
    # .1.0 name is harmless: host libraries ask for libbz2.so.1 and therefore
    # still get their own copy.
    libbz2.so.1.0|libbz2.so.1.0.*)
      return 1 ;;
  esac
  return 1
}

bundle_runtime_libraries() {
  local libdir="$BUNDLE/lib"
  mkdir -p "$libdir"

  local mpv=""
  local candidate
  for candidate in "$libdir/libmpv.so.2" "$libdir/libmpv.so"; do
    if [[ -e "$candidate" ]]; then
      mpv="$candidate"
      break
    fi
  done
  if [[ -z "$mpv" ]] && command -v ldconfig >/dev/null 2>&1; then
    mpv="$(ldconfig -p 2>/dev/null | awk '/libmpv\.so\.2 /{print $NF; exit}')"
  fi
  if [[ -z "$mpv" ]]; then
    for candidate in /usr/lib/*/libmpv.so.2 /usr/lib/libmpv.so.2 \
      /usr/local/lib/libmpv.so.2; do
      if [[ -e "$candidate" ]]; then
        mpv="$candidate"
        break
      fi
    done
  fi
  if [[ -z "$mpv" || ! -e "$mpv" ]]; then
    echo "warning: libmpv.so.2 was not found; the AppImage will need the host mpv" >&2
  else
    if [[ "$mpv" != "$libdir/libmpv.so.2" ]]; then
      cp -L "$mpv" "$libdir/libmpv.so.2"
    fi
    ln -sfn libmpv.so.2 "$libdir/libmpv.so"
  fi

  # Walk the shared-library graph from libmpv, the app binary and the plugin
  # libraries already in the bundle. Only *direct* NEEDED entries are followed:
  # `ldd` prints the whole transitive closure, including libraries used by
  # host-provided GTK/glib, and shipping the build host's older copies makes
  # them shadow newer host ones at runtime (NixOS's MOUNT_2_40 failure).
  declare -A seen=()
  local queue=()
  if [[ -e "$libdir/libmpv.so.2" ]]; then
    queue+=("$libdir/libmpv.so.2")
  fi
  if [[ -f "$BUNDLE/mawjtvh" ]]; then
    queue+=("$BUNDLE/mawjtvh")
  fi
  local bundled
  for bundled in "$libdir"/*.so*; do
    if [[ -e "$bundled" ]]; then
      queue+=("$bundled")
    fi
  done

  local index=0
  local current dep name needed_lib copied=0 resolved ldd_output
  while ((index < ${#queue[@]})); do
    current="${queue[$index]}"
    index=$((index + 1))
    if [[ -n "${seen[$current]:-}" ]]; then
      continue
    fi
    seen[$current]=1

    ldd_output="$(LD_LIBRARY_PATH="$libdir${LD_LIBRARY_PATH:+:$LD_LIBRARY_PATH}" \
      ldd "$current" 2>/dev/null || true)"

    if command -v readelf >/dev/null 2>&1; then
      while IFS= read -r needed_lib; do
        if [[ -z "$needed_lib" ]]; then
          continue
        fi
        resolved="$(printf '%s\n' "$ldd_output" | awk -v n="$needed_lib" '
          $1 == n && $2 == "=>" { print $3; exit }
          $1 == n && $2 != "=>" { print $1; exit }
        ')"
        if [[ -z "$resolved" || ! -e "$resolved" ]]; then
          continue
        fi
        name="$(basename "$resolved")"
        if should_skip_lib "$name"; then
          continue
        fi
        if [[ ! -e "$libdir/$name" ]]; then
          cp -L "$resolved" "$libdir/$name"
          copied=$((copied + 1))
        fi
        queue+=("$libdir/$name")
      done < <(readelf -d "$current" 2>/dev/null |
        awk '/NEEDED/ { gsub(/[\[\]]/, "", $5); print $5 }')
    else
      # binutils is normally available; fall back to ldd's full closure.
      while IFS= read -r resolved; do
        if [[ -z "$resolved" || ! -e "$resolved" ]]; then
          continue
        fi
        name="$(basename "$resolved")"
        if should_skip_lib "$name"; then
          continue
        fi
        if [[ ! -e "$libdir/$name" ]]; then
          cp -L "$resolved" "$libdir/$name"
          copied=$((copied + 1))
        fi
        queue+=("$libdir/$name")
      done < <(printf '%s\n' "$ldd_output" |
        awk '/=> \//{print $3} /^\//{print $1}')
    fi
  done

  echo "Bundled $copied runtime libraries into $libdir."
}

bundle_runtime_libraries

# AppStream metadata, with this build's version and today's date filled in.
write_metainfo() {
  sed -e "s/@VERSION@/$VERSION/" -e "s/@DATE@/$(date -u +%F)/" \
    "$ROOT/packaging/linux/mawjtvh.metainfo.xml" > "$1"
  chmod 644 "$1"
}

WORK="$ROOT/build/package/$DEB_ARCH"
ROOTFS="$WORK/rootfs"
rm -rf "$WORK"
mkdir -p "$OUT" "$ROOTFS/opt/mawjtvh" \
  "$ROOTFS/usr/bin" \
  "$ROOTFS/usr/share/applications" \
  "$ROOTFS/usr/share/metainfo" \
  "$ROOTFS/usr/share/icons/hicolor/512x512/apps"

cp -a "$BUNDLE/." "$ROOTFS/opt/mawjtvh/"
chmod +x "$ROOTFS/opt/mawjtvh/mawjtvh"
ln -sfn /opt/mawjtvh/mawjtvh "$ROOTFS/usr/bin/mawjtvh"
install -m644 "$ICON" "$ROOTFS/usr/share/icons/hicolor/512x512/apps/mawjtvh.png"
install -m644 "$DESKTOP" "$ROOTFS/usr/share/applications/mawjtvh.desktop"
write_metainfo "$ROOTFS/usr/share/metainfo/mawjtvh.appdata.xml"

echo "Staged $(du -sh "$ROOTFS/opt/mawjtvh" | cut -f1) application bundle for $DEB_ARCH."

has_format() {
  [[ ",$FORMATS," == *",$1,"* ]]
}

build_deb() {
  command -v dpkg-deb >/dev/null 2>&1 || {
    echo "dpkg-deb is required for DEB output" >&2
    return 1
  }

  local deb_root="$WORK/deb"
  rm -rf "$deb_root"
  cp -a "$ROOTFS" "$deb_root"
  mkdir -p "$deb_root/DEBIAN"

  cat > "$deb_root/DEBIAN/control" <<EOF
Package: mawjtvh
Version: $VERSION-1
Section: video
Priority: optional
Architecture: $DEB_ARCH
Installed-Size: $(du -sk "$deb_root/opt" | cut -f1)
Maintainer: mmbesar <mbesar@proton.me>
Homepage: https://github.com/mmbesar/MawjTVH
Depends: libgtk-3-0t64 | libgtk-3-0, libmpv2 | libmpv1, libstdc++6, libblkid1, liblzma5
Recommends: fonts-noto-core, mpv
Description: Tvheadend client for Android and Linux
 MawjTVH is a Tvheadend client: live TV, a timeline guide, recordings,
 signal numbers and first-class Arabic/English text. It supports Catppuccin,
 AMOLED and system themes, several servers and self-signed HTTPS.
EOF

  dpkg-deb --build --root-owner-group "$deb_root" \
    "$OUT/mawjtvh_${VERSION}_${DEB_ARCH}.deb" >/dev/null
  echo "  built mawjtvh_${VERSION}_${DEB_ARCH}.deb"
}

build_rpm() {
  command -v rpmbuild >/dev/null 2>&1 || {
    echo "rpmbuild is required for RPM output" >&2
    return 1
  }

  local rpmbuild_root="$WORK/rpmbuild"
  local spec="$WORK/mawjtvh.spec"
  mkdir -p "$rpmbuild_root"/{BUILD,BUILDROOT,RPMS,SOURCES,SPECS,SRPMS}

  cat > "$spec" <<EOF
%global debug_package %{nil}
Name:           mawjtvh
Version:        $VERSION
Release:        1
Summary:        Tvheadend client with guide and recordings
License:        GPL-3.0-or-later
URL:            https://github.com/mmbesar/MawjTVH
BuildArch:      $RPM_ARCH
Requires:       gtk3
Requires:       mpv-libs
Recommends:     mpv

%description
MawjTVH is a Tvheadend client: live TV, a timeline guide, recordings,
signal numbers and first-class Arabic/English text. It supports Catppuccin,
AMOLED and system themes, several servers and self-signed HTTPS.

%prep

%build

%install
rm -rf %{buildroot}
mkdir -p %{buildroot}
cp -a "$ROOTFS/." %{buildroot}/

%files
/opt/mawjtvh
/usr/bin/mawjtvh
/usr/share/applications/mawjtvh.desktop
/usr/share/metainfo/mawjtvh.appdata.xml
/usr/share/icons/hicolor/512x512/apps/mawjtvh.png
EOF

  rpmbuild -bb \
    --define "_topdir $rpmbuild_root" \
    --target "$RPM_ARCH" \
    "$spec" >/dev/null

  local package
  package="$(find "$rpmbuild_root/RPMS" -type f -name '*.rpm' -print -quit)"
  if [[ -z "$package" ]]; then
    echo "rpmbuild did not produce a package" >&2
    return 1
  fi
  cp "$package" "$OUT/"
  echo "  built $(basename "$package")"
}

build_appimage() {
  local appdir="$WORK/MawjTVH.AppDir"
  rm -rf "$appdir"
  mkdir -p "$appdir/usr/bin" \
    "$appdir/usr/share/applications" \
    "$appdir/usr/share/metainfo" \
    "$appdir/usr/share/icons/hicolor/512x512/apps"

  cp -a "$BUNDLE/." "$appdir/usr/bin/"
  install -m644 "$ICON" "$appdir/usr/share/icons/hicolor/512x512/apps/mawjtvh.png"
  install -m644 "$DESKTOP" "$appdir/usr/share/applications/mawjtvh.desktop"
  write_metainfo "$appdir/usr/share/metainfo/mawjtvh.appdata.xml"
  install -m644 "$ICON" "$appdir/mawjtvh.png"
  install -m644 "$DESKTOP" "$appdir/mawjtvh.desktop"
  ln -sfn mawjtvh.png "$appdir/.DirIcon"

  cat > "$appdir/AppRun" <<'EOF'
#!/bin/sh
HERE="$(dirname "$(readlink -f "$0")")"
export LD_LIBRARY_PATH="$HERE/usr/bin/lib${LD_LIBRARY_PATH:+:$LD_LIBRARY_PATH}"
exec "$HERE/usr/bin/mawjtvh" "$@"
EOF
  chmod +x "$appdir/AppRun"

  local tool="${APPIMAGETOOL:-$WORK/appimagetool}"
  if [[ ! -x "$tool" ]]; then
    command -v curl >/dev/null 2>&1 || {
      echo "curl is required to download appimagetool" >&2
      return 1
    }
    echo "Downloading appimagetool for $APPIMAGE_ARCH"
    curl -fsSL \
      "https://github.com/AppImage/appimagetool/releases/download/continuous/appimagetool-${APPIMAGE_ARCH}.AppImage" \
      -o "$tool"
    chmod +x "$tool"
  fi

  # appimagetool's AppStream check is stricter than the DEB/RPM tooling and
  # has rejected valid files before; the metadata is still shipped.
  ARCH="$APPIMAGE_ARCH" APPIMAGE_EXTRACT_AND_RUN=1 "$tool" --no-appstream \
    "$appdir" "$OUT/MawjTVH-${VERSION}-${APPIMAGE_ARCH}.AppImage" >/dev/null
  chmod +x "$OUT/MawjTVH-${VERSION}-${APPIMAGE_ARCH}.AppImage"
  echo "  built MawjTVH-${VERSION}-${APPIMAGE_ARCH}.AppImage"
}

STATUS=0
if has_format deb; then build_deb || STATUS=1; fi
if has_format rpm; then build_rpm || STATUS=1; fi
if has_format appimage; then build_appimage || STATUS=1; fi

echo "Release files in $OUT:"
ls -lh "$OUT"
exit "$STATUS"
