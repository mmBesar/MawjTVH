# Changelog

## 0.1.25

An audit of 0.1.23 and 0.1.24 (a separate reviewer read the code without my notes; I checked each finding).

- Release: never publishes from a Build that is not green (the jobs of a Build are independent, so the files could exist although the tests failed); a tag with a suffix such as `v0.2.0-beta1` is checked against the right file names; the rebuilt run is picked by tag, so another manual Build can't be mistaken for it; the dispatch input is passed safely.
- Packaging: a failed DEB, RPM or AppImage step is now really an error. Bash had switched `set -e` off inside the functions (they were called as `build_x || STATUS=1`), so a failed AppImage download left the step green and the file missing, which is probably how the ARM64 AppImage went missing.
- Guide history: the running timeline now shows programmes that ended in the last hours (today and yesterday stay loaded and are read when the guide opens); a programme captured while a file was being written is no longer dropped; duplicates after the seen-list reset are avoided; unsaved history is written when the app closes; removing a source removes its history.
- Guide: window lengths use calendar days (daylight-saving days were an hour off); the app asks again where the server's guide ends when the first try found nothing; later-day requests state an explicit count.
- Android: tapping two tabs quickly (Favorites, then Settings) could leave the view on the first; a finished slide now yields to a later tap.
- Search: accents typed as separate combining marks, and Arabic vowel signs, are ignored.
- Known, left as is: the search text cache is rebuilt whenever the guide changes (typing in search re-folds the guide each time); a chip for "Tomorrow" chosen before midnight keeps showing that day after midnight until another chip is tapped.

## 0.1.24

- Desktop: pages are drawn smaller (the automatic interface size is 100% instead of 120%, and the guide no longer stacks its own extra zoom on top). The sidebar keeps its size. Interface size now also offers 80% and 90%.
- Guide, future: the day chips reach as far as the server's guide does. After connecting, the app asks three channels for three weeks of guide and offers exactly the days that exist (a week until it knows). Later days are fetched per visible channel and carried on from the last programme instead of downloaded again.
- Guide, past: day chips for earlier days. Tvheadend deletes programmes soon after they end, so the app keeps its own history on the device: while it runs it copies every programme that has started into one small file per day, and reads a day back only when you open it. Setting "Past guide days to keep" (off, 1, 2, 3, 5, 7, 14; default 3) decides how many days are kept; off deletes what was saved. Days from before this version can't be shown.
- Search: punctuation, accents and word order no longer matter ("man united" finds "Man. United"), and when nothing matches exactly, small typos are forgiven ("manchster"). Used in channel search, guide search and the recordings list.
- Search page: a Channels / Programmes switch, with a hint that says what each searches. Channel search opened from Watch still looks at channels; the Guide's opens on programmes.
- Android: tapping a far tab (Settings) the first time could end up on Favorites, because the slide passed through and built every page in between. Far tabs now jump straight to the page.
- Release: before publishing, the release checks that the APK and the DEB, RPM and AppImage for amd64 and arm64 are all there (`tool/check_release_files.sh`). If something is missing it starts a new Build on the tag, waits, and publishes from that, or stops without releasing. The AppImage tool download retries on GitHub errors, which is the likely reason an ARM64 AppImage went missing.

## 0.1.23

- The guide has day chips (Today, Tomorrow, then Wed 11 and so on, up to a week). Today keeps the running timeline; any other day shows midnight to midnight.
- Days are loaded lazily. Over HTSP the server pushes only the next few hours; for a later day the guide asks for each channel it actually builds on screen (`getEvents` with the channel and an end time) and keeps it for 20 minutes, so scrolling a long list fetches only what you look at and the whole week of the whole server is never held. Old programmes are dropped as they pass.
- Without HTSP (web API only) the guide still shows only what was loaded; the chips then cover the days that the guide-hours setting reaches, and are hidden when that is one day.
- Not tested against a real server yet: whether a given server returns a full day for every channel.

## 0.1.22

- Resume starts the recording at the saved point as it opens (mpv's own start position), instead of opening it paused and jumping afterwards. Measured on Linux: a recording played from the start dropped a few frames, but one resumed with the old method dropped 20 to 60 frames per 5 seconds for 25 to 60 seconds. The decoder may also skip the frames before a jump target again (`hr-seek-framedrop`), which makes seeking in recordings quicker.

## 0.1.21

- The problem report (copy diagnostics) now shows how Flutter's own frames behaved while the page was open (how many, how many were slow to build or draw, the worst times) and how many video frames mpv dropped in each 5-second slice. This tells whether the drops come from Flutter's drawing or from mpv's rendering, and whether they come in bursts. No playback change.

## 0.1.20

- The resume prompt has a Cancel button, and Escape cancels it: nothing plays and you go back. This applies to the built-in player's prompt and to the dialog shown before the mpv window opens (where Escape or a click outside also cancels).

## 0.1.19

- Likely cause of the dropped frames in the built-in player on recordings: media_kit turns on mpv's on-disk cache, which ignores the memory limits, so mpv read the whole recording as fast as the server could send it (14 MB/s for minutes). That traffic goes through the app's own stream proxy on the thread Flutter needs to present each video frame. Recordings now use an in-memory cache limited to 30 seconds and 48 MB, so the file is read at about the speed it plays. The problem report shows `cache-on-disk` and `cache-secs`, and `demuxer-cache-duration` should now stay near 30.
- "Play recordings in mpv" (0.1.18) is now off by default, so the built-in player is what gets tested; turn it on to open recordings in the mpv window.

## 0.1.18

- Desktop: recordings now open in the mpv window by default when mpv is installed (new setting "Play recordings in mpv", on by default; off keeps them in the built-in player). On Linux the built-in player drops frames on recordings that mpv plays smoothly, and the cause is not found yet. Live TV is unchanged.
- Resume works in the mpv window too: a dialog asks before it opens, mpv starts at the saved point, and the position is saved every 5 seconds and when the window closes.

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
