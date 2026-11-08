#!/usr/bin/env bash
# Lists the release files that are missing from a folder.
#
#   tool/check_release_files.sh DIR VERSION [--no-arm64]
#
# Exits 0 when the Android APK and the Linux DEB, RPM and AppImage for both
# amd64 and arm64 are all there; otherwise prints what is missing and exits 1.
# --no-arm64 skips the arm64 Linux packages (the Build workflow does not make
# them for private repositories).
set -euo pipefail

dir="${1:?folder}"
version="${2:?version}"
arm64=1
[[ "${3:-}" == "--no-arm64" ]] && arm64=0

missing=0
need() {
  # need LABEL GLOB
  if ! compgen -G "$dir/$2" >/dev/null; then
    echo "missing: $1 ($2)"
    missing=1
  fi
}

need "Android APK" "MawjTVH-${version}-arm64-v8a.apk"
need "Linux amd64 DEB" "mawjtvh_${version}_amd64.deb"
need "Linux amd64 RPM" "*.x86_64.rpm"
need "Linux amd64 AppImage" "MawjTVH-${version}-x86_64.AppImage"
if [[ "$arm64" == 1 ]]; then
  need "Linux arm64 DEB" "mawjtvh_${version}_arm64.deb"
  need "Linux arm64 RPM" "*.aarch64.rpm"
  need "Linux arm64 AppImage" "MawjTVH-${version}-aarch64.AppImage"
fi
exit "$missing"
