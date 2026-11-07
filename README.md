<div align="center">

# MawjTVH · موجة

**A Tvheadend client for Android and Linux.**
Native HTSP, a proper player, a set-top-box style on-screen display, and first-class Arabic and English.

[![Build](https://github.com/mmBesar/MawjTVH/actions/workflows/build.yml/badge.svg)](https://github.com/mmBesar/MawjTVH/actions/workflows/build.yml)
[![Release](https://img.shields.io/github/v/release/mmBesar/MawjTVH?include_prereleases&label=release)](https://github.com/mmBesar/MawjTVH/releases)
[![License: GPL-3.0-or-later](https://img.shields.io/badge/license-GPL--3.0--or--later-blue.svg)](LICENSE)
![Platforms](https://img.shields.io/badge/platforms-Android%20%7C%20Linux-informational)
![Built with Flutter](https://img.shields.io/badge/built%20with-Flutter-02569B?logo=flutter&logoColor=white)
![Status](https://img.shields.io/badge/status-under%20development-orange)
![Not official](https://img.shields.io/badge/Tvheadend-unofficial-lightgrey)

</div>

> [!WARNING]
> **MawjTVH is a personal project, under active development.** It is **not** an
> official Tvheadend app and is **not** affiliated with, endorsed by or
> supported by the Tvheadend project or its developers. Expect rough edges and
> changes between versions.

## What it is

MawjTVH (موجة, "a wave") lets you watch live TV from your own
[Tvheadend](https://tvheadend.org/) server, browse its programme guide, and
schedule and play recordings. It is built on the look, the player and the
Arabic/English right-to-left work of Mawjac, with Tvheadend-blue and orange
colours, several themes and an AMOLED mode.

It is a **Tvheadend client, not an IPTV player**: it does not bring channels or
playlists of its own. You need a Tvheadend server that you run or have an
account on.

## Features

- **Native HTSP.** Talks to Tvheadend over its own protocol (port 9982). Works
  for ordinary accounts that do **not** have the "web interface" permission.
  HTTP is kept as an option.
- **Live TV** through a local stream proxy that shares one subscription per
  channel, releases the tuner when you leave, reports a busy tuner, and
  re-subscribes after a signal loss.
- **Player.** libmpv on Android; on Linux the built-in player or your own mpv
  with your own configuration. Audio and subtitle language defaults, tracks
  remembered per channel, aspect ratio, deinterlacing, audio delay, local
  recording, Picture-in-Picture and a floating window on Android.
- **Set-top-box style on-screen display** by mouse, keyboard or touch: channel
  banner (now and next, source, network, mux, tags, stream facts, signal), a
  channel browser with tags and search, a guide panel, volume and brightness.
  Pin it, or let it fade after the time you choose.
- **Guide.** Timeline guide with episode, year, rating, credits and
  new/repeat/HD badges from the server's EPG.
- **Recordings.** Upcoming, finished and failed; record a programme, a series,
  or "record now" from the player. Play them over HTSP too, with seeking.
- **Channel views.** Cards, list, compact and a logo wall; favourites, recents
  and Tvheadend tags, remembered between runs.
- **Interface size** for the whole app and for the guide, so it reads well on
  a desktop screen as well as on a phone.
- **Settings** for the things people actually ask for. Arabic and English,
  right-to-left aware text.

## Keyboard shortcuts (player)

| Key | Action |
| --- | --- |
| `C` / `Enter` | Channel browser |
| `G` | Guide for the channel |
| `I` | Channel banner, `P` to pin it |
| `↑` `↓` / digits | Next, previous channel / number |
| `A` / `S` | Audio / subtitle track |
| `Z` | Aspect ratio |
| `X` | Reset aspect, deinterlace and audio delay |
| `T` | Deinterlace |
| `[` `]` | Audio delay |
| `R` | Record |
| `M`, `+`, `−` | Mute, volume |
| `F` / `F11` | Full screen |
| `H` / `F1` | Help |

The in-app help (`H`) always shows the current list.

## Status and known gaps

This is development software and I test it on my own setup only.

- HTSP streaming, tuner release, subtitles and the on-screen display are
  verified on my server, but not on every kind of Tvheadend setup.
- Digest login works for the web API, pictures and recordings in HTTP mode. It has only been tested against a fake server in the automated tests, not yet against a real Tvheadend set to Digest. MD5 is the only algorithm supported.
- Recordings play over HTSP, but a recording that is still being made plays
  only up to the point it had reached when you opened it.
- Timeshift, Android TV remote support and teletext are on the roadmap, not
  done.
- Passwords are kept in the app's preferences on the device, not encrypted.

## Install

Builds come from CI: see the
[Actions](https://github.com/mmBesar/MawjTVH/actions) page and the
[Releases](https://github.com/mmBesar/MawjTVH/releases) page for the Android
arm64 APK and Linux amd64/arm64 bundles. Nothing is published to a store.

## Build

See [docs/BUILDING.md](docs/BUILDING.md). The Flutter platform folders are
generated in CI and patched by `tool/configure_platforms.py`.

## Disclaimers

- **Unofficial.** "Tvheadend" is the name of a separate project. MawjTVH is an
  independent client and is not affiliated with it.
- **No warranty.** This software is provided as is, without warranty of any
  kind. See the licence. Use it at your own risk and keep backups of anything
  you care about, including your Tvheadend configuration and recordings.
- **Your server, your content.** MawjTVH does not supply, host or index any
  content. Use it only with servers and content you are entitled to access,
  and follow the laws that apply to you, including those on recording.
- **Privacy.** The app talks only to the server you configure. It has no
  analytics or advertising. Channel logos and programme pictures are loaded
  from the addresses your server gives it.
- **Trademarks** belong to their owners. Names are used only to say what the
  app works with.

## Contributing

It is a personal project, but issues and ideas are welcome. Please say which
Tvheadend version you use and what the app showed. Pull requests are welcome;
please keep to the existing style and run `python3 tool/check_strings.py`.

## Licence

[GPL-3.0-or-later](LICENSE). Copyright © 2026 Mohammed (mmBesar).
