# Changelog

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
