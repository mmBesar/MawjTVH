# MawjTVH

**MawjTVH** (موجة, "a wave") is a fast, light IPTV player for Android and Linux.
It reads M3U playlists and XMLTV guides and is tested against **Tunarr** and
**ErsatzTV**. Arabic and English with full RTL, Catppuccin themes plus AMOLED.

## What it does

- **Watch**: a hero strip to resume, filter pills for All, Favorites and groups, live "now" progress on every channel.
- **Guide**: a 12-hour timeline with a now line, optional favorites-only view.
- **Search**: channels and programmes, with Arabic-aware matching (diacritics, alef and ya/ta-marbuta variants).
- **Player**: in-place channel zapping, swipe for brightness and volume, native window fullscreen on desktop, stall detection with copyable diagnostics.
- **Themes**: Mawj (dark), Foam (light), Catppuccin Latte/Frappé/Macchiato/Mocha, AMOLED, and system colours.

Favorites and recents survive playlist reordering because channel ids come from `tvg-id`, `channel-id` or name rather than position.

## ErsatzTV note

ErsatzTV's HLS master advertises a WebVTT subtitle rendition. media_kit's default
ffmpeg options (`strict=experimental`) make ffmpeg read only that rendition and
never open the video. MawjTVH sets its own demuxer options without that flag.

## Desktop playback

On Linux, MawjTVH plays each channel in its own native **mpv** window. mpv cannot
be embedded inside another window on Wayland, and its render API can freeze on
some Mesa setups, so a separate window gives GPU decoding, real compositor
fullscreen and mpv's own on-screen controls. MawjTVH stays open as a remote:
now/next, channel switching, favorites.

Settings lists the hardware decoders your mpv reports (VA-API, NVDEC, Vulkan…),
with a software fallback. The AppImage ships its own mpv; with a DEB/RPM or a
source build mpv is taken from `PATH`, or from `MAWJTVH_MPV=/path/to/mpv`. If no
mpv is found, the built-in renderer is used.

## Build

See [docs/BUILDING.md](docs/BUILDING.md) and [docs/SOURCES.md](docs/SOURCES.md).
CI builds an Android arm64 APK and Linux amd64/arm64 bundles.

```bash
tool/bootstrap.sh
flutter run -d linux
```

Linux hardware decoding is off by default; try `MAWJTVH_HWDEC=auto-copy-safe`.

## Licence

GPL-3.0-or-later. See [LICENSE](LICENSE).
