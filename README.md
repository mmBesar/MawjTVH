# MawjTVH

**MawjTVH** (موجة, "a wave") is a Tvheadend client for Android and Linux, built
on the look, player and Arabic/English RTL work of Mawjac. Catppuccin themes
plus AMOLED.

It talks to Tvheadend's HTTP API (works over plain HTTP, HTTPS, reverse proxies
and web roots). **The server decides what each account may do**: admins see
signal and server status, normal users watch and record as their account allows.

## What it does

- **Watch**: channels grouped by Tvheadend channel tags, live "now" progress, favorites, recents.
- **Guide**: timeline guide (12 to 72 h) from the server's EPG, with episode, year, rating and credits in the programme sheet.
- **Recordings**: upcoming, recorded and failed; play (even while recording), stop, cancel, delete. Record a programme, a whole series, or "record now" for 30 min to 4 h from the player.
- **Signal**: SNR and SS next to the channel in the player bar (admin accounts; from the server's tuner status).
- **Server status** (admins): tuners, running streams, connections.
- **Stream profile**: pick `pass`, `matroska` or a transcoding profile per server.
- **Search**: channels and programmes, with Arabic-aware matching.
- **Player**: libmpv on Android; a native mpv window on Linux (Wayland-safe, GPU decoding).

## Notes

- Login uses HTTP Basic. Tvheadend must allow plain or "both" authentication (digest-only is not supported yet).
- Passwords are stored in the app's preferences on the device, not encrypted.
- Signal numbers over the HTSP port for non-admin accounts are planned, not done.

## Build

See [docs/BUILDING.md](docs/BUILDING.md). CI builds an Android arm64 APK and Linux amd64/arm64 bundles.

Licence: GPL-3.0-or-later.
