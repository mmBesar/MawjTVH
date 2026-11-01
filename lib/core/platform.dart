import 'dart:io' show Platform;

/// True on Linux, Windows and macOS: the layouts and behaviours that suit a
/// pointer, keyboard and resizable window rather than a touch screen.
final bool kIsDesktop =
    Platform.isLinux || Platform.isWindows || Platform.isMacOS;
