# MawjTVH project notes

Hand-off for any person or AI assistant who picks the project up. House rules
are in `AGENTS.md`. Keep this file current: update the status log with every
meaningful change.

## What it is

A Tvheadend client for Android and Linux (Flutter), by Mohammed (`mmBesar`).
Native HTSP first (works for accounts without the web interface permission),
HTTP as an option. Built on the UI, player and Arabic/English RTL work of
Mawjac (his IPTV player). Not an IPTV player: it brings no channels.

## Architecture

- `lib/data/htsp_connection.dart`, `htsp_message.dart`: the HTSP wire protocol
  (login, request/reply, async messages). `http_digest.dart` for Digest auth.
- `lib/data/htsp_backend.dart`: one session. Holds channels, tags, events
  (EPG) and DVR entries pushed by the server, exposes them as models, sends
  requests (record, play position, `getEvents`, file reads). Guide: the server
  pushes EPG only to `guideHours + 3`; later days are fetched per channel on
  demand (`ensureEvents`, 20 min TTL); `_probeGuideEnd` finds how far the
  server's guide goes.
- `lib/data/htsp_stream_proxy.dart`: loopback HTTP server that players use.
  `/live/<id>`: one shared subscription per channel, remuxed to MPEG-TS
  (`ts_muxer.dart`). `/dvr/<id>`: recordings served over HTSP
  `fileOpen/fileRead` with byte ranges, read ahead in chunks, shared
  refcounted file handle. The player never talks to Tvheadend directly.
- `lib/data/app_state.dart`: the single `ChangeNotifier` the UI reads:
  sources, settings, content, recordings, favourites/recents, resume
  positions, search, HTSP session lifecycle (retry with backoff after a drop).
- `lib/data/tvh_client.dart`, `tvh_loader.dart`: HTTP API path and the loader
  that builds `SourceContent` (HTSP or HTTP).
- `lib/ui/`: pages (`watch`, `guide`, `recordings`, `search`, `settings`,
  `server`, ...), the player (`player_page.dart` Android/mobile,
  `desktop_player_page.dart` Linux), set-top-box style OSD widgets
  (`stb_*.dart`). `lib/core/`: theme, text/search folding, zoom, PiP,
  external player bridge. `lib/l10n/`: English and Arabic strings
  (`tool/check_strings.py` checks they match).
- Players: media_kit (libmpv) built in. Linux can instead use the system mpv
  window (`mpv_runtime.dart`). Android can hand off to mpv-android or VLC
  (`lib/core/external_player.dart` + Kotlin in `tool/configure_platforms.py`),
  which return where playback stopped, used for resume.
- Android native code lives only as strings in `tool/configure_platforms.py`:
  `MainActivity` (PiP, external player channel) and `KeepAliveService` (a
  foreground service while an external player is open, so Android does not
  freeze the app that feeds it).

## Release flow

1. Push to `main`. `.github/workflows/build.yml` runs quality (analyze, tests),
   Android arm64 APK (signed from repository secrets), Linux amd64 and arm64
   bundles/packages (deb, rpm, AppImage via `tool/package_linux.sh`).
2. When CI is green the owner tags: `git tag -a vX.Y.Z -m "X.Y.Z" &&
   git push origin vX.Y.Z`.
3. `.github/workflows/release.yml` finds the green build for that commit,
   downloads its artifacts, runs `tool/check_release_files.sh` (all expected
   packages present), rebuilds via `workflow_dispatch` if something is missing,
   requires a successful run, writes checksums and publishes the release
   (plain tags are "latest", not pre-release).
4. The Android build retries downloads (GitHub sometimes returns 502/504 for
   media_kit's jars); re-run a failed job before suspecting the code.

## Open

- Everything since 0.1.22 is unverified on real devices (no compiler or device
  in the assistant's sandbox; CI compiles). v0.1.22 to the latest are not
  tagged yet.
- mpv-android closes when seeking in a recording (reported on 0.1.27). 0.1.28
  adds a foreground service as the best theory; if it persists, get the
  mpv-android log (`adb logcat -s mpv`) and a problem report.
- Android app lost recordings and channel logos after a long time open;
  0.1.29 changes the reconnect/sync handling (found by reading, not
  reproduced).
- Satellite subtitles (reported 2026-11-11; Kodi showed them). Tvheadend decodes teletext subtitle pages itself and sends `TEXTSUB` streams (UTF-8 + `<font color>`; empty text clears), see `src/parsers/parser_teletext.c` in tvheadend and `AddTVHStream` in kodi-pvr/pvr.hts. 0.1.31 hands them from the stream proxy (`onSubtitle`) to the in-app player, which draws them (`lib/data/text_subtitles.dart`, overlay in `player_page.dart`). Unverified; no timing correction; raw `TELETEXT` streams and the Linux mpv window still show nothing.
- Design gaps: live pause has no back-pressure; one slow HTSP request can kill
  the session; the loopback proxy has no token; the "Tomorrow" day chip is
  stale after midnight; in-app Linux playback has baseline frame drops with
  nvdec-copy.
- Roadmap (frozen while testing): recently watched strip, timeshift (design
  talk first: buffer length and location), Android TV remote/D-pad, teletext,
  merge the Favourites page into the tag row.

## Status log

- 0.1.0-0.1.7 (2026-11-01..07): fork of Mawjac onto Tvheadend; HTSP backend and
  stream proxy; busy-tuner handling and tuner release; blue/orange theme;
  release workflow publishes from the existing green build.
- 0.1.8-0.1.13: recordings over HTSP with seeking; shared file handle; Digest
  auth; seek controls; fix for audio continuing after Back (proxy called
  `detachSocket` on a started response); resume of recordings.
- 0.1.14-0.1.22: Linux in-app recording playback tuning (read-ahead, cache
  limits, `Media(start:)` resume); acceptable by 0.1.22, baseline drops remain.
- 0.1.23-0.1.24: day-by-day guide with lazy loading and horizon probe;
  forgiving search with Channels/Programmes switch; release completeness check.
- 0.1.25-0.1.26: audit fixes (packaging `set -e`, release from red build,
  player/proxy leaks); on-device guide history removed ("stick to what the
  server offers").
- 0.1.27: optional external player on Android (mpv, VLC) with resume.
- 0.1.28: foreground service while the external player is open.
- 0.1.29: recordings/channels survive a dropped HTSP session.
- 0.1.30: stream list and subtitle tracks in the problem report.
- 0.1.31: teletext (TEXTSUB) subtitles drawn by the app.
- 0.1.35/0.1.36: tried a side pill gauge on Android, then (owner preference) the desktop `StbValueOsd` panel is used on every platform.
- 0.1.34: Android libmpv (media-kit/libmpv-android-video-build, default flavor) has the dvbsub decoder but no dvbsub parser, so on Android the muxer sends DVBSUB packets without the 0x20 0x00 header and 0xFF end marker (`TsMuxer(subtitleHeader: !Platform.isAndroid)`). Unverified.
- 0.1.33: media_kit sets `sub-visibility=no` (libass off), so bitmap subtitles were never drawn: the player now sets it per selected track codec; track names for org/und/etc.; server languages fill in for streams the player has no language for.
- 0.1.32: DVBSUB fix (Tvheadend strips 0x20 0x00 and the 0xFF end marker from the packet; the muxer restores them); audio/subtitle menu ticks and first-change memory fixed.
- 2026-11-11: AI-assistance disclosure added to the README; `AGENTS.md` and
  this file added; commits stay authored by `mmbesar` with no AI trailers.
