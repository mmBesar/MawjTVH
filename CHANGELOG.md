# Changelog

## 0.2.0

- Desktop: video now plays in a separate native mpv window (Wayland-safe, GPU decoding, real fullscreen, mpv's own controls). MawjTVH shows a now-playing remote beside it. The AppImage ships its own mpv; `MAWJTVH_MPV` overrides the binary.
- Settings: player engine, hardware decoder (listed from what the installed mpv reports), video output, own mpv config, start fullscreen.
- Desktop layout: sidebar with Ctrl+1..4, Ctrl+F and Ctrl+R shortcuts; wide thumbnail tiles.
- Channels: tap the logo to play, tap the name or programme to open that channel's own guide. In the guide grid, a long press or right click on a channel opens its guide.
- Programme artwork is shown landscape (16:9) in cards and the detail sheet.
- Images: shared keep-alive HTTP clients and more parallel fetches, so logos and artwork load much faster on self-hosted servers.
- Desktop waves are drawn still, to stop idle GPU use.

## 0.1.0

- First release: Watch, Guide, Search, Player and Settings.
- M3U + XMLTV with Tunarr and ErsatzTV; favorites, groups, recents.
- Arabic/English with RTL; Mawj, Foam, Catppuccin and AMOLED themes.
