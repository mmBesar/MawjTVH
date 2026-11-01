# Playlist and guide formats

MawjTVH reads one M3U/M3U8 playlist and one XMLTV guide per source. Locations may
be HTTP(S) URLs or local files, and playlists may reference relative stream and
logo URLs.

## Tunarr example

A typical self-hosted Tunarr source looks like this:

| Field | Value |
| --- | --- |
| Name | Home Tunarr |
| Playlist | `https://tunarr.hs.lan/api/channels.m3u` |
| XMLTV | `https://tunarr.hs.lan/api/xmltv.xml` |
| Allow self-signed certificate | On, if `tunarr.hs.lan` uses a private CA |

Tunarr's M3U header advertises the guide with `url-tvg`, so the XMLTV field can
also be left empty. An explicit XMLTV location always wins.

## M3U playlist

MawjTVH accepts the common extended M3U dialect:

```m3u
#EXTM3U url-tvg="https://tunarr.hs.lan/api/xmltv.xml"
#EXTINF:-1 tvg-id="C1.tunarr.com" tvg-chno="1" tvg-name="Arabic One" \
  tvg-logo="https://tunarr.hs.lan/logos/c1.png" group-title="Arabic",Arabic One HD
https://tunarr.hs.lan/stream/channels/C1.m3u8
```

Supported `#EXTM3U` attributes:

- `url-tvg`, `x-tvg-url`, `tvg-url`, `x-tvg` — guide location advertised by
  the playlist. If the value contains several comma-separated URLs, the first
  one is used.

Supported `#EXTINF` attributes:

| Attribute | Use |
| --- | --- |
| `tvg-id` | XMLTV channel id; the primary matching key |
| `channel-id` | Alternative matching key, falls back to `tvg-id` |
| `tvg-name` | Fallback display name |
| `tvg-chno` | Channel number; defaults to the playlist position |
| `tvg-logo` | Logo URL; relative paths are resolved against the playlist |
| `group-title` | Channel group; wins over `#EXTGRP` when both are present |

The display name is the text after the last unquoted comma of `#EXTINF`. Quoted
commas inside attribute values are preserved.

`#EXTGRP:Group` is supported both before `#EXTINF` (the common form) and
between `#EXTINF` and its URL. `group-title` always wins when both are present.

Lines starting with `#` that MawjTVH does not recognise are ignored. A non-comment
line is treated as the stream URL of the preceding `#EXTINF`. Entries without a
URL, or whose URL is `#`, are skipped without consuming a channel number.

Relative stream and logo locations are resolved against the playlist location:
HTTP(S) URLs against the playlist URL, and relative file paths against the
playlist file's directory.

## XMLTV guide

MawjTVH parses the parts of XMLTV that the guide actually displays:

```xml
<tv>
  <channel id="C1.tunarr.com">
    <display-name>Arabic One</display-name>
    <icon src="https://tunarr.hs.lan/logos/c1.png"/>
  </channel>

  <programme start="20261028142553 +0000"
             stop="20261028154453 +0000"
             channel="C1.tunarr.com">
    <title>وجهة نظر</title>
    <sub-title>حلقة 1</sub-title>
    <desc>وصف الحلقة</desc>
    <category>دراما</category>
    <episode-num system="xmltv_ns">0.1.</episode-num>
    <icon src="https://tunarr.hs.lan/posters/ep1.jpg"/>
  </programme>
</tv>
```

### Time format

`start` and `stop` use `YYYYMMDDHHmmss` with an optional timezone:

- `20261028142553 +0000`
- `20261028142553 +03:00`
- `20261028142553` (no zone; interpreted as local time)

Seconds and the timezone are optional. Invalid or inverted ranges are skipped.
Only programmes overlapping the guide window are retained: **12 hours in the
past** and **72 hours in the future**. This keeps memory bounded on phones with
multi-day, multi-channel guides.

### Matching channels

MawjTVH creates internal channel ids from the source id and playlist position, so
XMLTV ids never leak into storage. A programme is attached to a channel using,
in order:

1. Exact `tvg-id` match.
2. Exact `channel-id` match.
3. A normalised id match (case folded, punctuation/whitespace removed, Arabic
   letters preserved).
4. A `<display-name>` match against the playlist's `tvg-id`, `channel-id` or
   channel name (also normalised).

Programmes without a non-empty `channel` attribute are ignored; they never
match channels that happen to have an empty `tvg-id`. XMLTV `<channel>` entries
without an id are ignored as well.

Because display-name matching is intentionally forgiving, two channels with the
same normalised name may resolve to the first playlist entry. Give Tunarr (or
your provider) distinct display names or `tvg-id` values when that matters.

### Fields displayed

- `title` — required; programmes without one are skipped.
- `sub-title` — shown under the title in the 12-hour guide and in the programme
  details sheet.
- `desc`, `category`, `icon` — shown in the programme details sheet.
- `episode-num` — `system="onscreen"` is shown as-is; `xmltv_ns` is converted
  to `S01E02` style.

## Local files

Use the **File** endpoint kind in the source editor to pick a playlist or guide
from disk. For Linux, paths are expanded from `~` to the current user's home
directory. XMLTV files may be plain XML or gzip-compressed; gzip is detected by
its magic bytes, so a `.xml.gz` file works even if the server omits
`Content-Encoding`.

## HTTP, HTTPS and self-signed certificates

- Plain HTTP is accepted for LAN sources.
- HTTPS uses the platform trust store by default.
- The per-source **Allow self-signed certificates** switch disables certificate
  verification for that source only. It applies to the playlist, the guide,
  channel logos and playback.

Only enable the switch for servers you control. It disables protection against
man-in-the-middle attacks for that source.

Playlist URLs may contain HTTP Basic credentials
(`https://user:password@host/playlist.m3u`). MawjTVH strips them from the request
URL and sends an `Authorization` header instead. Credentials are stored as part
of the source URL in the application's preferences; they are not encrypted at
rest beyond the operating system's user isolation.

## Caching and offline behaviour

- Each source has its own cache under
  `<app support directory>/cache/source_<id>.json`.
- The cache is keyed by the playlist and XMLTV locations, and expires after
  30 days.
- If the playlist cannot be fetched, MawjTVH shows the cached channel list and
  guide with a warning instead of an empty screen.
- If only the guide fails, the playlist stays live and the cached guide is used
  when available.
- **Test connection** in the source editor always performs a real fetch; it
  never reports a cached success.
- Only the active source is loaded. Switching sources clears the visible channel
  and guide data before loading the new snapshot, so ids from different
  providers never mix.

## Limits

- Responses are capped at 128 MiB.
- Connect timeout is 20 seconds; guide/playlist reads time out after 45 seconds.
- Redirects are followed up to five times.
- UTF-8 is assumed; Latin-1/Windows-1252 content is decoded when the server
  declares that charset, and invalid UTF-8 is decoded leniently.

## Troubleshooting

| Symptom | Likely cause |
| --- | --- |
| Playlist loads, guide is empty | XMLTV `channel` ids/names do not match the playlist, or the guide has no programmes inside the ±window |
| Logos are missing | Logo URL is relative to the playlist and not reachable, or the host certificate is self-signed and the switch is off |
| "TLS handshake failed" | Self-signed certificate without the per-source switch |
| Guide shows old programmes | Cached snapshot is being used after a failed refresh; check the warning banner and Retry |
| Some channels have no numbers | Playlist omits `tvg-chno`; MawjTVH falls back to playlist position |
| Duplicate programmes | The XMLTV file contains overlapping entries; MawjTVH keeps them all and the guide draws each block |
