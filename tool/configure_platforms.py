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
    "android.permission.POST_NOTIFICATIONS",
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

    if ".RadioService" not in text:
        service = (
            '    <service\n'
            '        android:name=".RadioService"\n'
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
import android.content.pm.PackageManager
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
// that player stopped, and drives the radio's media session (RadioService).
class MainActivity : FlutterActivity() {
    private var channel: MethodChannel? = null
    private var mediaChannel: MethodChannel? = null
    private var askedNotifications = false
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
        val media = MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "mawjtvh/media")
        mediaChannel = media
        RadioService.listener = { action -> media.invokeMethod("action", action) }
        media.setMethodCallHandler { call, result ->
            when (call.method) {
                "update" -> {
                    mediaUpdate(call)
                    result.success(null)
                }
                "stop" -> {
                    stopService(Intent(this, RadioService::class.java))
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

    // Android 13+ hides notifications until the user allows them. The radio
    // plays either way; the question is asked once, when it first starts.
    private fun askForNotifications() {
        if (askedNotifications || Build.VERSION.SDK_INT < 33) {
            return
        }
        askedNotifications = true
        if (checkSelfPermission("android.permission.POST_NOTIFICATIONS") !=
            PackageManager.PERMISSION_GRANTED
        ) {
            requestPermissions(arrayOf("android.permission.POST_NOTIFICATIONS"), 4713)
        }
    }

    private fun mediaUpdate(call: MethodCall) {
        askForNotifications()
        val title = call.argument<String>("title") ?: ""
        val subtitle = call.argument<String>("subtitle") ?: ""
        val playing = call.argument<Boolean>("playing") ?: false
        val canSkip = call.argument<Boolean>("canSkip") ?: false
        val running = RadioService.instance
        if (running != null) {
            running.applyState(title, subtitle, playing, canSkip)
            return
        }
        val intent = Intent(this, RadioService::class.java).apply {
            action = RadioService.ACTION_UPDATE
            putExtra("title", title)
            putExtra("subtitle", subtitle)
            putExtra("playing", playing)
            putExtra("canSkip", canSkip)
        }
        try {
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                startForegroundService(intent)
            } else {
                startService(intent)
            }
        } catch (e: Exception) {
            // Audio still plays; only the notification and the background
            // protection are missing.
        }
    }

    // The Flutter engine (and with it the radio player) goes with the
    // activity, so the media service must not outlive it.
    override fun onDestroy() {
        if (isFinishing) {
            RadioService.listener = null
            stopService(Intent(this, RadioService::class.java))
        }
        super.onDestroy()
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


RADIO_SERVICE = """package com.mmbesar.mawjtvh

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.app.Service
import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.content.IntentFilter
import android.content.pm.ServiceInfo
import android.graphics.drawable.Icon
import android.media.AudioAttributes
import android.media.AudioFocusRequest
import android.media.AudioManager
import android.media.MediaMetadata
import android.media.session.MediaSession
import android.media.session.PlaybackState
import android.net.wifi.WifiManager
import android.os.Build
import android.os.IBinder
import android.os.PowerManager

// The radio as an Android media player: a foreground service that keeps the
// app (and the audio) alive with the screen off or another app in front,
// shows the media notification, answers the lock screen and headset buttons,
// and respects audio focus (calls, other players) and unplugged headphones.
// The audio itself is decoded by the Dart side; this only holds the session.
class RadioService : Service() {
    companion object {
        const val ACTION_UPDATE = "mawjtvh.radio.update"
        private const val ACTION_PREFIX = "mawjtvh.radio.do."
        private const val CHANNEL_ID = "radio"
        private const val NOTIFICATION_ID = 4713

        @Volatile
        var instance: RadioService? = null

        // Set by MainActivity: sends a button press to Dart.
        var listener: ((String) -> Unit)? = null
    }

    private var session: MediaSession? = null
    private var wakeLock: PowerManager.WakeLock? = null
    private var wifiLock: WifiManager.WifiLock? = null
    private var focusRequest: AudioFocusRequest? = null
    private var hasFocus = false
    private var pausedByFocus = false
    private var foreground = false
    private var title = ""
    private var subtitle = ""
    private var playing = false
    private var canSkip = false

    private val noisy = object : BroadcastReceiver() {
        override fun onReceive(context: Context?, intent: Intent?) {
            if (playing) emit("pause")
        }
    }

    private val focusListener = AudioManager.OnAudioFocusChangeListener { change ->
        when (change) {
            AudioManager.AUDIOFOCUS_LOSS -> {
                pausedByFocus = false
                hasFocus = false
                emit("pause")
            }
            AudioManager.AUDIOFOCUS_LOSS_TRANSIENT -> {
                pausedByFocus = playing
                hasFocus = false
                emit("pause")
            }
            AudioManager.AUDIOFOCUS_GAIN -> {
                hasFocus = true
                if (pausedByFocus) {
                    pausedByFocus = false
                    emit("play")
                }
            }
            else -> {}
        }
    }

    override fun onBind(intent: Intent?): IBinder? = null

    @Suppress("DEPRECATION")
    override fun onCreate() {
        super.onCreate()
        instance = this
        val manager = getSystemService(NOTIFICATION_SERVICE) as NotificationManager
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            manager.createNotificationChannel(
                NotificationChannel(CHANNEL_ID, "Radio", NotificationManager.IMPORTANCE_LOW)
            )
        }
        val created = MediaSession(this, "MawjTVH radio")
        created.setFlags(
            MediaSession.FLAG_HANDLES_MEDIA_BUTTONS or MediaSession.FLAG_HANDLES_TRANSPORT_CONTROLS
        )
        created.setCallback(object : MediaSession.Callback() {
            override fun onPlay() = emit("play")
            override fun onPause() = emit("pause")
            override fun onStop() = emit("stop")
            override fun onSkipToNext() = emit("next")
            override fun onSkipToPrevious() = emit("previous")
        })
        created.isActive = true
        session = created
        registerReceiver(noisy, IntentFilter(AudioManager.ACTION_AUDIO_BECOMING_NOISY))
    }

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        val action = intent?.action
        if (intent != null && action == ACTION_UPDATE) {
            applyState(
                intent.getStringExtra("title") ?: "",
                intent.getStringExtra("subtitle") ?: "",
                intent.getBooleanExtra("playing", false),
                intent.getBooleanExtra("canSkip", false)
            )
        } else if (action != null && action.startsWith(ACTION_PREFIX)) {
            emit(action.removePrefix(ACTION_PREFIX))
        } else if (!foreground) {
            // Started without a state (should not happen): stay legal.
            startForegroundCompat(buildNotification())
        }
        return START_NOT_STICKY
    }

    fun applyState(newTitle: String, newSubtitle: String, nowPlaying: Boolean, skip: Boolean) {
        title = newTitle
        subtitle = newSubtitle
        playing = nowPlaying
        canSkip = skip
        updateSession()
        val notification = buildNotification()
        if (!foreground) {
            startForegroundCompat(notification)
        } else {
            val manager = getSystemService(NOTIFICATION_SERVICE) as NotificationManager
            manager.notify(NOTIFICATION_ID, notification)
        }
        if (playing) {
            acquireLocks()
            requestFocus()
        } else {
            releaseLocks()
            abandonFocus()
        }
    }

    private fun startForegroundCompat(notification: Notification) {
        try {
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
                startForeground(
                    NOTIFICATION_ID,
                    notification,
                    ServiceInfo.FOREGROUND_SERVICE_TYPE_MEDIA_PLAYBACK
                )
            } else {
                startForeground(NOTIFICATION_ID, notification)
            }
            foreground = true
        } catch (e: Exception) {
            // Android refused a foreground start from the background; the
            // audio keeps playing for as long as the system allows.
        }
    }

    private fun emit(action: String) {
        listener?.invoke(action)
    }

    private fun updateSession() {
        val current = session ?: return
        current.setMetadata(
            MediaMetadata.Builder()
                .putString(MediaMetadata.METADATA_KEY_TITLE, title)
                .putString(MediaMetadata.METADATA_KEY_ARTIST, subtitle)
                .build()
        )
        var actions = PlaybackState.ACTION_PLAY or PlaybackState.ACTION_PAUSE or
            PlaybackState.ACTION_PLAY_PAUSE or PlaybackState.ACTION_STOP
        if (canSkip) {
            actions = actions or PlaybackState.ACTION_SKIP_TO_NEXT or
                PlaybackState.ACTION_SKIP_TO_PREVIOUS
        }
        current.setPlaybackState(
            PlaybackState.Builder()
                .setActions(actions)
                .setState(
                    if (playing) PlaybackState.STATE_PLAYING else PlaybackState.STATE_PAUSED,
                    PlaybackState.PLAYBACK_POSITION_UNKNOWN,
                    1f
                )
                .build()
        )
    }

    private fun command(name: String, code: Int): PendingIntent {
        val intent = Intent(this, RadioService::class.java).setAction(ACTION_PREFIX + name)
        return PendingIntent.getService(
            this, code, intent, PendingIntent.FLAG_IMMUTABLE or PendingIntent.FLAG_UPDATE_CURRENT
        )
    }

    private fun action(icon: Int, label: String, name: String, code: Int): Notification.Action {
        return Notification.Action.Builder(
            Icon.createWithResource(this, icon), label, command(name, code)
        ).build()
    }

    private fun buildNotification(): Notification {
        val builder = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            Notification.Builder(this, CHANNEL_ID)
        } else {
            Notification.Builder(this)
        }
        var compact = 0
        var index = 0
        if (canSkip) {
            builder.addAction(action(android.R.drawable.ic_media_previous, "Previous", "previous", 1))
            index++
        }
        builder.addAction(
            if (playing) action(android.R.drawable.ic_media_pause, "Pause", "pause", 2)
            else action(android.R.drawable.ic_media_play, "Play", "play", 3)
        )
        compact = index
        index++
        if (canSkip) {
            builder.addAction(action(android.R.drawable.ic_media_next, "Next", "next", 4))
            index++
        }
        builder.addAction(action(android.R.drawable.ic_menu_close_clear_cancel, "Stop", "stop", 5))

        val open = packageManager.getLaunchIntentForPackage(packageName)
        if (open != null) {
            builder.setContentIntent(
                PendingIntent.getActivity(this, 0, open, PendingIntent.FLAG_IMMUTABLE)
            )
        }
        val style = Notification.MediaStyle()
        val token = session?.sessionToken
        if (token != null) {
            style.setMediaSession(token)
        }
        style.setShowActionsInCompactView(compact)
        return builder
            .setContentTitle(if (title.isEmpty()) "MawjTVH" else title)
            .setContentText(subtitle)
            .setSmallIcon(applicationInfo.icon)
            .setOngoing(playing)
            .setShowWhen(false)
            .setDeleteIntent(command("stop", 6))
            .setStyle(style)
            .build()
    }

    @Suppress("DEPRECATION")
    private fun acquireLocks() {
        if (wakeLock == null) {
            val power = getSystemService(POWER_SERVICE) as PowerManager
            wakeLock = power.newWakeLock(PowerManager.PARTIAL_WAKE_LOCK, "mawjtvh:radio").apply {
                setReferenceCounted(false)
            }
        }
        if (wakeLock?.isHeld == false) wakeLock?.acquire()
        if (wifiLock == null) {
            val wifi = applicationContext.getSystemService(WIFI_SERVICE) as WifiManager
            wifiLock = wifi.createWifiLock(WifiManager.WIFI_MODE_FULL_HIGH_PERF, "mawjtvh:radio")
                .apply { setReferenceCounted(false) }
        }
        if (wifiLock?.isHeld == false) wifiLock?.acquire()
    }

    private fun releaseLocks() {
        if (wakeLock?.isHeld == true) wakeLock?.release()
        if (wifiLock?.isHeld == true) wifiLock?.release()
    }

    @Suppress("DEPRECATION")
    private fun requestFocus() {
        if (hasFocus) return
        val audio = getSystemService(AUDIO_SERVICE) as AudioManager
        val granted = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            val request = focusRequest ?: AudioFocusRequest.Builder(AudioManager.AUDIOFOCUS_GAIN)
                .setAudioAttributes(
                    AudioAttributes.Builder()
                        .setUsage(AudioAttributes.USAGE_MEDIA)
                        .setContentType(AudioAttributes.CONTENT_TYPE_MUSIC)
                        .build()
                )
                .setOnAudioFocusChangeListener(focusListener)
                .build()
            focusRequest = request
            audio.requestAudioFocus(request)
        } else {
            audio.requestAudioFocus(
                focusListener, AudioManager.STREAM_MUSIC, AudioManager.AUDIOFOCUS_GAIN
            )
        }
        hasFocus = granted == AudioManager.AUDIOFOCUS_REQUEST_GRANTED
    }

    @Suppress("DEPRECATION")
    private fun abandonFocus() {
        if (!hasFocus) return
        val audio = getSystemService(AUDIO_SERVICE) as AudioManager
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            focusRequest?.let { audio.abandonAudioFocusRequest(it) }
        } else {
            audio.abandonAudioFocus(focusListener)
        }
        hasFocus = false
    }

    override fun onDestroy() {
        releaseLocks()
        abandonFocus()
        try {
            unregisterReceiver(noisy)
        } catch (e: Exception) {
            // Already gone.
        }
        session?.isActive = false
        session?.release()
        session = null
        if (instance === this) instance = null
        super.onDestroy()
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
    write(kotlin / "RadioService.kt", RADIO_SERVICE)
    print("  wrote MainActivity.kt (picture-in-picture, external player, radio)")


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
