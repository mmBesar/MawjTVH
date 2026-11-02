# Changelog

## 0.1.1

- Native HTSP protocol (optional per server): live channels, groups, guide and recordings pushed by the server; recording actions over HTSP.
- Local recording rewritten: the stream is copied over its own HTTP connection (fixes Android and desktop failures).
- Signal strength for any account over HTSP (not just admins).
- Programme text in the guide follows the viewport; Watch cards use programme artwork when the guide has it.
- Shared group filter between Watch and Guide, per-page search, new icon, recordings page with channel filter and grouping, record indicators, release signing.

## 0.1.0

- First release: a Tvheadend client forked from Mawjac 0.2.0's UI and player.
- Tvheadend HTTP API: login, channels and tags, paged EPG, stream profiles, recordings (schedule, series, record now, stop, cancel, delete, play), signal (SNR/SS) and server status for admins.
- Removed the M3U/XMLTV sources.
