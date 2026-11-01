# Security policy

## Supported versions

MawjTVH is pre-1.0. Security fixes are applied to the latest release and `main`.
There are no long-term support branches yet.

| Version | Supported |
| --- | --- |
| 0.1.x | Yes |
| < 0.1 | No |

## Reporting a vulnerability

Please **do not open a public issue** for a security problem.

Use GitHub's private vulnerability reporting for this repository
(**Security → Report a vulnerability**) or email
[mbesar@proton.me](mailto:mbesar@proton.me) with:

- A description of the issue and its impact.
- The affected version or commit.
- Reproduction steps or a proof of concept.
- Any suggested fix or mitigation.

You should receive an acknowledgement within a few days. This is a
volunteer-maintained project, so timelines are best-effort; please allow time
for a fix and coordinated disclosure before publishing details.

## Scope

MawjTVH reads untrusted playlists, XMLTV files, images and media streams. Reports
that are particularly relevant include:

- Parser bugs in `lib/data/m3u_parser.dart` or `lib/data/xmltv_parser.dart`
  (for example denial of service, unexpected file/network access, or memory
  exhaustion).
- TLS or HTTP handling issues in `lib/data/fetcher.dart`,
  `lib/core/network_image.dart` or playback.
- Credential leakage from playlist URLs, logs, caches or error messages.
- Path traversal or unintended file access when loading local playlists/guides.
- Cache poisoning or cross-source data mixing.

The following are **not** vulnerabilities by themselves:

- The per-source **Allow self-signed HTTPS certificates** option disabling
  certificate verification. That is an explicit, documented opt-in for local
  servers and is limited to the source where it is enabled.
- Plain HTTP being accepted for LAN sources.
- The Android release APK being signed with a debug key. It is documented as a
  sideload build and is not intended for app-store distribution.
- A malicious *server* returning content the user chose to load. Only report
  this if MawjTVH mishandles it in a way that crosses a documented boundary
  (for example writing outside its cache directory).
- Missing certificate pinning.

## Handling secrets

Never include credentials, tokens, private playlist URLs or keystores in an
issue, pull request or test fixture. If you need to demonstrate a problem,
redact hosts, usernames and passwords and use a minimal synthetic fixture.
