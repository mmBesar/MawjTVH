#!/usr/bin/env python3
"""Applies MawjTVH-specific settings to Flutter's generated platform shells.

Everything here is idempotent: bootstrap.sh may be rerun on an existing
checkout without duplicating permissions or icons.
"""

from __future__ import annotations

import re
import shutil
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
ANDROID = ROOT / "android"
LINUX = ROOT / "linux"
BRANDING = ROOT / "assets" / "branding"

APP_ID = "com.mmbesar.mawjtvh"
APP_LABEL = "MawjTVH"

PERMISSIONS = (
    "android.permission.INTERNET",
    "android.permission.ACCESS_NETWORK_STATE",
    "android.permission.WAKE_LOCK",
    "android.permission.FOREGROUND_SERVICE",
    "android.permission.FOREGROUND_SERVICE_MEDIA_PLAYBACK",
)

DESKTOP_FILE = """[Desktop Entry]
Type=Application
Name=MawjTVH
GenericName=Tvheadend Client
Comment=Tvheadend client with guide, recordings and signal info
Exec=mawjtvh
Icon=mawjtvh
Terminal=false
Categories=AudioVideo;Video;Player;TV;
Keywords=tvheadend;tv;dvr;epg;stream;
StartupWMClass=mawjtvh
"""


def read(path: Path) -> str:
    return path.read_text(encoding="utf-8")


def write(path: Path, text: str) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(text, encoding="utf-8")


def patch_android_manifest() -> None:
    manifest = ANDROID / "app" / "src" / "main" / "AndroidManifest.xml"
    if not manifest.exists():
        print("  AndroidManifest.xml not found; skipping")
        return

    text = read(manifest)
    missing = [
        permission for permission in PERMISSIONS if permission not in text
    ]
    if missing:
        lines = "".join(
            f'    <uses-permission android:name="{permission}" />\n'
            for permission in missing
        )
        match = re.search(r"<manifest\b[^>]*>", text)
        if not match:
            raise SystemExit("Could not find the <manifest> element")
        text = text[: match.end()] + "\n" + lines + text[match.end() :]

    if "usesCleartextTraffic" not in text:
        text = re.sub(
            r"<application\b",
            '<application\n        android:usesCleartextTraffic="true"',
            text,
            count=1,
        )

    if "supportsPictureInPicture" not in text:
        text = re.sub(
            r"<activity\b",
            '<activity\n            android:supportsPictureInPicture="true"',
            text,
            count=1,
        )

    if "KeepAliveService" not in text:
        service = (
            '    <service\n'
            '        android:name=".KeepAliveService"\n'
            '        android:exported="false"\n'
            '        android:foregroundServiceType="mediaPlayback" />\n'
        )
        if "</application>" not in text:
            raise SystemExit("Could not find </application>")
        text = text.replace("</application>", service + "  </application>", 1)

    text = re.sub(
        r'android:label="[^"]*"',
        f'android:label="{APP_LABEL}"',
        text,
        count=1,
    )
    write(manifest, text)
    print("  patched AndroidManifest.xml")


MAIN_ACTIVITY = """package com.mmbesar.mawjtvh

import android.app.PictureInPictureParams
import android.content.ActivityNotFoundException
import android.content.Intent
import android.net.Uri
import android.os.Build
import android.util.Rational
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel

// Picture-in-picture for the player: Dart asks to float the video, and
// (optionally) the window floats by itself when the user leaves the app.
// It also hands a stream to an external player (mpv, VLC) and returns where
// that player stopped.
class MainActivity : FlutterActivity() {
    private var channel: MethodChannel? = null
    private var autoEnter = false
    private var playerResult: MethodChannel.Result? = null
    private val playerRequest = 4711

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        val pip = MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "mawjtvh/pip")
        channel = pip
        pip.setMethodCallHandler { call, result ->
            when (call.method) {
                "enter" -> result.success(enterPip())
                "autoEnter" -> {
                    autoEnter = call.arguments as? Boolean ?: false
                    result.success(null)
                }
                else -> result.notImplemented()
            }
        }
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "mawjtvh/external_player")
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "play" -> playExternal(call, result)
                    else -> result.notImplemented()
                }
            }
    }

    private fun playExternal(call: MethodCall, result: MethodChannel.Result) {
        val url = call.argument<String>("url")
        val pkg = call.argument<String>("package")
        if (url == null || pkg == null) {
            result.error("args", "url and package are required", null)
            return
        }
        if (playerResult != null) {
            result.error("busy", "A player is already open", null)
            return
        }
        val title = call.argument<String>("title") ?: ""
        val positionMs = call.argument<Number>("positionMs")?.toInt() ?: 0
        val intent = Intent(Intent.ACTION_VIEW).apply {
            setDataAndType(Uri.parse(url), "video/*")
            setPackage(pkg)
            putExtra("title", title)
            if (positionMs > 0) {
                putExtra("position", positionMs)
            }
        }
        playerResult = result
        keepAlive(true)
        try {
            startActivityForResult(intent, playerRequest)
        } catch (e: ActivityNotFoundException) {
            playerResult = null
            keepAlive(false)
            result.error("missing", "$pkg is not installed", null)
        } catch (e: Exception) {
            playerResult = null
            keepAlive(false)
            result.error("failed", e.message, null)
        }
    }

    // While the external player is in front, this app is in the background and
    // Android may freeze it, which would stop the local server that feeds the
    // player (it then fails the moment it seeks). A foreground service keeps
    // the app running for as long as the player is open.
    private fun keepAlive(on: Boolean) {
        try {
            val service = Intent(this, KeepAliveService::class.java)
            if (!on) {
                stopService(service)
            } else if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                startForegroundService(service)
            } else {
                startService(service)
            }
        } catch (e: Exception) {
            // Playing still works without it; it is only a safeguard.
        }
    }

    // mpv answers with position and duration, VLC with extra_position and
    // extra_duration; both are milliseconds, as Int or Long.
    private fun readMillis(data: Intent?, vararg keys: String): Long? {
        val extras = data?.extras ?: return null
        for (key in keys) {
            val value = extras.get(key)
            if (value is Int) return value.toLong()
            if (value is Long) return value
        }
        return null
    }

    override fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?) {
        if (requestCode != playerRequest) {
            super.onActivityResult(requestCode, resultCode, data)
            return
        }
        val pending = playerResult
        playerResult = null
        keepAlive(false)
        val reply = HashMap<String, Any?>()
        reply["code"] = resultCode
        reply["position"] = readMillis(data, "position", "extra_position")
        reply["duration"] = readMillis(data, "duration", "extra_duration")
        pending?.success(reply)
    }

    private fun enterPip(): Boolean {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.O) {
            return false
        }
        return try {
            val params = PictureInPictureParams.Builder()
                .setAspectRatio(Rational(16, 9))
                .build()
            enterPictureInPictureMode(params)
        } catch (e: Exception) {
            false
        }
    }

    override fun onUserLeaveHint() {
        super.onUserLeaveHint()
        if (autoEnter) {
            enterPip()
        }
    }

    override fun onPictureInPictureModeChanged(isInPictureInPictureMode: Boolean) {
        super.onPictureInPictureModeChanged(isInPictureInPictureMode)
        channel?.invokeMethod("pip", isInPictureInPictureMode)
    }
}
"""


KEEP_ALIVE_SERVICE = """package com.mmbesar.mawjtvh

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.Service
import android.content.Intent
import android.content.pm.ServiceInfo
import android.os.Build
import android.os.IBinder

// Runs while an external player is open, so Android keeps the app (and the
// local server that feeds the player) running in the background.
class KeepAliveService : Service() {
    override fun onBind(intent: Intent?): IBinder? = null

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        val manager = getSystemService(NOTIFICATION_SERVICE) as NotificationManager
        val builder: Notification.Builder
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            manager.createNotificationChannel(
                NotificationChannel("playback", "Playback", NotificationManager.IMPORTANCE_LOW)
            )
            builder = Notification.Builder(this, "playback")
        } else {
            builder = Notification.Builder(this)
        }
        val notification = builder
            .setContentTitle("MawjTVH")
            .setContentText("Feeding the external player")
            .setSmallIcon(applicationInfo.icon)
            .setOngoing(true)
            .build()
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
            startForeground(4712, notification, ServiceInfo.FOREGROUND_SERVICE_TYPE_MEDIA_PLAYBACK)
        } else {
            startForeground(4712, notification)
        }
        return START_NOT_STICKY
    }
}
"""


def patch_android_activity() -> None:
    kotlin = ANDROID / "app" / "src" / "main" / "kotlin" / "com" / "mmbesar" / "mawjtvh"
    if not (ANDROID / "app" / "src" / "main").is_dir():
        print("  android sources not found; skipping MainActivity")
        return
    target = kotlin / "MainActivity.kt"
    if target.exists() and read(target) == MAIN_ACTIVITY:
        return
    write(target, MAIN_ACTIVITY)
    write(kotlin / "KeepAliveService.kt", KEEP_ALIVE_SERVICE)
    print("  wrote MainActivity.kt (picture-in-picture, external player)")


SIGNING_HEADER = """import java.io.FileInputStream
import java.util.Properties

// Release signing: read android/key.properties when it exists (CI writes it
// from repository secrets). Without it the build falls back to the debug key,
// so local builds still work, but such an APK cannot update a signed one.
val keystoreProperties = Properties().apply {
    val file = rootProject.file("key.properties")
    if (file.exists()) {
        FileInputStream(file).use { load(it) }
    }
}

"""

SIGNING_CONFIGS = """    signingConfigs {
        create("release") {
            if (keystoreProperties.containsKey("keyAlias")) {
                keyAlias = keystoreProperties["keyAlias"] as String
                keyPassword = keystoreProperties["keyPassword"] as String
                storeFile = file(keystoreProperties["storeFile"] as String)
                storePassword = keystoreProperties["storePassword"] as String
            }
        }
    }

"""


def add_release_signing_kts(text: str) -> str:
    if "keystoreProperties" in text:
        return text
    text = SIGNING_HEADER + text
    text = text.replace("    buildTypes {", SIGNING_CONFIGS + "    buildTypes {", 1)
    text = re.sub(
        r'signingConfig\s*=\s*signingConfigs\.getByName\("debug"\)',
        'signingConfig = if (keystoreProperties.containsKey("keyAlias")) '
        'signingConfigs.getByName("release") else signingConfigs.getByName("debug")',
        text,
    )
    return text


def patch_android_gradle() -> None:
    kts = ANDROID / "app" / "build.gradle.kts"
    groovy = ANDROID / "app" / "build.gradle"
    if kts.exists():
        text = read(kts)
        text = re.sub(
            r'applicationId\s*=\s*"[^"]*"',
            f'applicationId = "{APP_ID}"',
            text,
        )
        text = re.sub(
            r"minSdk\s*=\s*(flutter\.minSdkVersion|\d+)",
            "minSdk = 24",
            text,
        )
        text = add_release_signing_kts(text)
        write(kts, text)
        print("  patched android/app/build.gradle.kts")
    elif groovy.exists():
        text = read(groovy)
        text = re.sub(
            r'applicationId\s+"[^"]*"',
            f'applicationId "{APP_ID}"',
            text,
        )
        text = re.sub(
            r"minSdkVersion\s+(flutter\.minSdkVersion|\d+)",
            "minSdkVersion 24",
            text,
        )
        write(groovy, text)
        print("  patched android/app/build.gradle")


def patch_android_icons() -> None:
    source = BRANDING / "android"
    res = ANDROID / "app" / "src" / "main" / "res"
    if not source.is_dir() or not res.is_dir():
        print("  launcher icons not found; skipping")
        return

    for directory in sorted(source.iterdir()):
        if not directory.is_dir():
            continue
        destination = res / directory.name
        destination.mkdir(parents=True, exist_ok=True)
        shutil.copy2(directory / "ic_launcher.png", destination / "ic_launcher.png")

    # Flutter templates may ship adaptive icons that would hide our legacy
    # launcher PNGs on Android 8+. Remove them so every device uses MawjTVH.
    for anydpi in res.glob("mipmap-anydpi*"):
        for name in ("ic_launcher.xml", "ic_launcher_round.xml"):
            target = anydpi / name
            if target.exists():
                target.unlink()
    print("  installed Android launcher icons")


def patch_linux() -> None:
    cmake = LINUX / "CMakeLists.txt"
    if cmake.exists():
        text = read(cmake)
        text = re.sub(
            r'set\(APPLICATION_ID\s+"[^"]*"\)',
            f'set(APPLICATION_ID "{APP_ID}")',
            text,
        )
        write(cmake, text)
        print("  patched linux/CMakeLists.txt")

    runner = LINUX / "runner" / "my_application.cc"
    if runner.exists():
        text = read(runner)
        text = text.replace(
            'gtk_header_bar_set_title(header_bar, "mawjtvh");',
            'gtk_header_bar_set_title(header_bar, "MawjTVH");',
        )
        text = text.replace(
            'gtk_window_set_title(window, "mawjtvh");',
            'gtk_window_set_title(window, "MawjTVH");',
        )
        text = text.replace(
            "gtk_window_set_default_size(window, 1280, 720);",
            "gtk_window_set_default_size(window, 1280, 820);",
        )
        write(runner, text)
        print("  patched linux/runner/my_application.cc")


def write_desktop_entry() -> None:
    write(BRANDING / "mawjtvh.desktop", DESKTOP_FILE)


def main() -> int:
    if not ANDROID.is_dir() and not LINUX.is_dir():
        print("No generated platform directories found. Run tool/bootstrap.sh first.")
        return 1

    print("Configuring MawjTVH platform shells:")
    patch_android_manifest()
    patch_android_activity()
    patch_android_gradle()
    patch_android_icons()
    patch_linux()
    write_desktop_entry()
    print("Platform configuration complete.")
    return 0


if __name__ == "__main__":
    sys.exit(main())
