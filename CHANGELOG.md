# Changelog

## 0.1.17

- Recordings in the built-in player: the seek bar was redrawn for every video frame (25 or more times a second, even while hidden), which live TV never does, and mpv read minutes of the file ahead at full speed. The bar now updates once a second and the read-ahead is limited to about 20 seconds and 32 MB. Aimed at the dropped frames seen on Linux with the recording that plays fine in the external mpv window.

## 0.1.16

- HTSP messages are joined once when they are whole instead of being copied again for every piece that arrives; a block of a recording is now copied twice in total, not about five to thirty times. Reads ahead go back to four chunks.
- The problem report (copy diagnostics) now also shows, for recordings, how fast the server delivered the file and the slowest waits, and mpv's dropped-frame, frame-rate, A/V sync and cache figures.

## 0.1.15

- Resume is asked before the recording starts: a full-screen message ("Continue from 12:34", Resume / Start over) on both Linux and Android, instead of a small bar over the picture. Resume waits for the file to be known, jumps to the saved point, and then starts playing; before, the button could do nothing on desktop because the jump came too early.
- Linux in-app player: the "Hardware decoding" setting now applies to it as well (it was fixed to auto-safe) and is shown under the renderer setting. Try "Off" or "Copy back" if frames drop.
- Recordings read eight chunks ahead.

## 0.1.14

- Recordings over HTSP read four chunks ahead instead of one, so a slow or distant connection (VPN, internet) no longer limits the playback speed to one chunk per round trip. A short read near the end of a file that is still being recorded is handled by asking again from that point.

## 0.1.13

- Resume: a recording remembers where you stopped. The next time you play it, a prompt offers "Continue from 12:34" or "Start over" for a few seconds. The position is saved every 15 seconds and when you leave; stopping in the first 30 seconds keeps the earlier position, and finishing (or the last minute) clears it.
- Over HTSP the position is stored on the Tvheadend server with the recording (`playposition`), so every client of the account that uses it, such as other MawjTVH devices or Kodi, shares it. Local files, and sources used over HTTP only, keep it on this device.
- Not yet in the external mpv window.

## 0.1.12

- Fixed: a recording kept playing sound after Back, with no picture, until the app was killed. Leaving a recording asked the local stream proxy to cut its connections, and that step failed once the file was streaming (Dart cannot detach a response that has started); the error aborted the player page's clean-up before the player was stopped. The proxy now closes the connections properly, the player is stopped first, and a failure in the release step can no longer skip it. The same applies to the external mpv window page. This also stops the lingering server connections seen after leaving a recording.

## 0.1.11

- Recordings can be seeked: a seek bar (tap or drag) with elapsed and total time, ±10 s buttons, and on a phone a horizontal swipe jumps ±30 s. Keyboard: Left/Right ±10 s, Shift+Left/Right ±60 s, PgUp/PgDn ±5 min, Up/Down volume. Live TV keeps zapping on those keys.
- Leaving a recording now stops playback before releasing the player, drops a player that finished opening after you had left, and the external mpv window is force-closed if it ignores the quit request. This is meant to end audio carrying on after Back; it could not be reproduced here, so please report if it still happens.

## 0.1.10

- Digest login: servers set to Digest-only authentication now work for everything the app fetches over HTTP (the web API, channel logos and programme pictures, recordings in HTTP mode). The app answers the server's challenge and signs later requests straight away. HTSP already had its own login and is unchanged.
- New tests: the RFC 2617 example request, reading challenges, and a fake Digest-only server that the app's HTTP transport logs in to.

## 0.1.9

- Recordings: all of the player's connections to one recording share a single open file on the server, each connection closes when its request is done, and leaving the recording ends them all and closes the file at once.
- Audio and subtitle menu: the chosen track is highlighted and ticked; there are no radio circles.

## 0.1.8

- Recordings play over HTSP: the app's local stream proxy reads the file from the server with HTSP `fileOpen`/`fileRead` and serves it to the player with byte ranges (so seeking works). Accounts without the web interface permission can now watch their recordings. Servers set to HTTP-only still use the web address.
- The audio and subtitle sheet no longer uses the deprecated radio widgets.
- The image loader's user agent follows the app version.
- New test: a fake HTSP server hands out a file and the proxy is checked for full, ranged, tail, open-ended and out-of-range requests.

## 0.1.7

- Releases no longer rebuild everything: pushing a tag runs a separate `Release` workflow that publishes the files from the green build of that commit (see docs/BUILDING.md).
- The channel browser and guide panels no longer dim the picture, are as tall as the window allows (down to the control bar on desktop) and adjust to small windows.
- The About text and package description say what MawjTVH is: an unofficial Tvheadend client, a personal project still in development.
- New README with badges and disclaimers.

## 0.1.6

- Packaging: the Linux build no longer fails at random on a broken pipe.
- Player: the channel browser and guide now cover the whole app (also when the player is a small window on a phone) and no longer react as volume or brightness gestures. On desktop they stop above the control bar, which stays visible.
- Aspect ratio, deinterlacing and audio delay go back to normal on every channel change; `X` resets them on demand.
- Android controls are laid out in rows (top bar, transport, buttons, now playing, channel strip) so nothing hides behind anything else.
- Landscape phone: the channel browser and guide are full-height side panels with a slim header, and the guide shows programmes and details side by side.
- Info banner is smaller, sizes itself from both the width and height of the window, and shows tags, source, video, audio, decoder and dropped frames as icon rows.
- Guide details use icon rows for time, date, length, rating, category and each credit role.
- Phone Cards view: real cards, two per row, separate from the List view.
- The hover play button sits in the bottom corner of channel cards.
- Fix: a channel that would not tune until the app was restarted. A server that stops answering now closes the session so the app reconnects by itself (with a 30 s keep-alive), and every play or local recording first makes sure it has a working stream address.
- Channel banner shows the network, mux and provider the server tuned, and the channel's tags.
- Bigger channel logos on cards and the logo wall when there is no programme picture; the hover play button no longer covers the logo.
- Tag rows (Watch, Guide, in-player browser) scroll with the mouse wheel as well as by dragging.

## 0.1.5

- Aspect ratio fixed: it now reshapes the normally fitted picture, `Auto` always returns to the original, and Zoom fills the window without stretching.
- Channel banner: wider (up to 96% of the window), much bigger type that scales with the window, pin and close buttons, `P` pins it from the keyboard, a click anywhere else dismisses it, and it goes away by itself after the time set in Settings. Bigger notices too.
- Channel guide panel over the picture (`G`, or the guide button on mobile): what is on and next, details of the highlighted programme, record and record series.
- More from the server guide over HTSP: new / repeat / premiere / HD / widescreen / subtitled / audio description flags, genre, season and episode counts, first aired date, rating and age.
- Mobile player: channel list with tags and search (bottom sheet), channel guide, and a floating (picture-in-picture) window, also automatically when leaving the app (Settings).
- Interface zoom for the whole app (desktop defaults to 120%, Ctrl + / Ctrl − / Ctrl 0) plus a separate Guide size.
- Channel page views: Cards, List, Compact and Logo wall (header menu and Settings).
- Settings: on-screen display time, interface size, guide size, view, floating window.

## 0.1.4

- Channels no longer vanish from the list during a session: server updates that carry only part of a channel (or programme, or recording) are merged instead of replacing it.
- Desktop OSD rebuilt in a set-top-box style: big lower-third volume bar with segmented level, notices for muted / audio / subtitle changes, a REC badge, and a full channel banner (logo, number, clock, now with progress, next, stream details, signal bars). `I` pins or hides the banner; it also shows for a few seconds when a channel opens (setting).
- Default audio language and default subtitle language (or subtitles off) in Settings.
- Audio and subtitle choices are remembered per channel.
- Local recordings carry the programme title when the guide knows it.
- Desktop player: channel and tag browser over the picture (`C` / `Enter` / list button): tags across the top (All, Favourites, your Tvheadend tags), channels with what is on now, type to search by name or number, arrows / Enter / click to tune; the chosen tag is remembered.
- Desktop shortcuts: number keys enter a channel number, `A`/`J` cycle audio and subtitles, `S` track menu, `Z` aspect ratio (16:9, 4:3, 21:9, zoom), `T` deinterlace, `[` `]` audio delay, `R` record, `H`/`F1` shortcut sheet; more buttons on the control bar.

## 0.1.3

- Tuner is released the moment you close a channel or zap away (it used to stay locked until the app was closed); a second subscription can no longer be opened by the signal badge or by a quick close and reopen.
- Busy tuner, weak signal, encrypted channel and similar server refusals are shown in the player instead of an endless spinner.
- Desktop player: mouse wheel changes volume, arrow keys and +/- too, `I` toggles a stream info panel (now/next, resolution, codecs, decoder), `D` shows diagnostics; volume OSD.
- New look from the Tvheadend logo colours: deep blue base with orange accent (Studio), a light blue Daylight; icon recoloured to match.
- The last used group is remembered across restarts.

## 0.1.2

- One HTSP subscription per channel, shared by the player and local recording.
- Server record button turns into Stop / Abort while the channel records, and can record the current programme.
- Radio stations: All / TV / Radio filter on Watch and Guide.
- Guide shows episode numbers; HTSP guide carries more detail (credits, rating, year, HD).
- New default look "Studio" (pine-black, broadcast green) and "Daylight"; Mawj and the others stay as options.
- Desktop plays in the app by default (the separate mpv window stays an option).
- Audio & subtitles picker with real language names; DVB subtitles are carried through the HTSP stream.
- Desktop: a proper control bar (title bar, one bottom bar, volume slider); in-app video uses the GPU path by default (setting + MAWJTVH_RENDERER=cpu to go back); the system mpv window now uses your own mpv config and defaults.
- Episode numbers on every list (channels, channel guide, search, player).
- Signal no longer opens a second HTSP subscription while you watch.
- Darker green in Studio and Daylight.
- Favourite star moved to the bottom row on Android so nothing covers it.

## 0.1.1

- Native HTSP protocol (optional per server): live channels, groups, guide and recordings pushed by the server; recording actions over HTSP.
- Local recording rewritten: the stream is copied over its own HTTP connection (fixes Android and desktop failures).
- HTSP mode needs no HTTP API / "web interface" permission; live TV can play over HTSP through a resilient loopback proxy that re-subscribes when the signal drops.
- New settings: programme artwork on cards, reduce motion.
- Signal strength for any account over HTSP (not just admins).
- Programme text in the guide follows the viewport; Watch cards use programme artwork when the guide has it.
- Shared group filter between Watch and Guide, per-page search, new icon, recordings page with channel filter and grouping, record indicators, release signing.

## 0.1.0

- First release: a Tvheadend client forked from Mawjac 0.2.0's UI and player.
- Tvheadend HTTP API: login, channels and tags, paged EPG, stream profiles, recordings (schedule, series, record now, stop, cancel, delete, play), signal (SNR/SS) and server status for admins.
- Removed the M3U/XMLTV sources.
