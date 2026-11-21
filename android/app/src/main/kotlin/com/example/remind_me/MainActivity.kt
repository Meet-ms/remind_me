package com.example.remind_me

import android.app.Activity
import android.content.ContentValues
import android.content.Intent
import android.media.RingtoneManager
import android.net.Uri
import android.os.Build
import android.provider.MediaStore
import android.webkit.MimeTypeMap
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import java.io.File

class MainActivity : FlutterActivity() {
    private var pendingPick: MethodChannel.Result? = null

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL)
            .setMethodCallHandler { call, result -> handle(call, result) }
    }

    private fun handle(call: MethodCall, result: MethodChannel.Result) {
        try {
            when (call.method) {
                "pickRingtone" -> pickRingtone(
                    call.argument<String>("type") ?: "notification",
                    call.argument<String>("existing"),
                    result,
                )
                "copyUriToFile" -> {
                    copyUriToFile(call.argument<String>("uri")!!, call.argument<String>("dest")!!)
                    result.success(true)
                }
                "registerNotificationSound" -> result.success(
                    registerNotificationSound(
                        call.argument<String>("path")!!,
                        call.argument<String>("name") ?: "sound",
                    )
                )
                else -> result.notImplemented()
            }
        } catch (e: Exception) {
            result.error("sound_error", e.message, null)
        }
    }

    private fun pickRingtone(type: String, existing: String?, result: MethodChannel.Result) {
        if (pendingPick != null) {
            result.error("busy", "A picker is already open", null)
            return
        }
        val intent = Intent(RingtoneManager.ACTION_RINGTONE_PICKER).apply {
            putExtra(
                RingtoneManager.EXTRA_RINGTONE_TYPE,
                if (type == "alarm") RingtoneManager.TYPE_ALARM else RingtoneManager.TYPE_NOTIFICATION,
            )
            putExtra(RingtoneManager.EXTRA_RINGTONE_SHOW_DEFAULT, false)
            putExtra(RingtoneManager.EXTRA_RINGTONE_SHOW_SILENT, false)
            if (existing != null) {
                putExtra(RingtoneManager.EXTRA_RINGTONE_EXISTING_URI, Uri.parse(existing))
            }
        }
        pendingPick = result
        startActivityForResult(intent, PICK_RINGTONE)
    }

    @Deprecated("Deprecated in Java")
    override fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?) {
        if (requestCode != PICK_RINGTONE) {
            super.onActivityResult(requestCode, resultCode, data)
            return
        }
        val result = pendingPick
        pendingPick = null
        if (resultCode != Activity.RESULT_OK || data == null) {
            result?.success(null)
            return
        }
        @Suppress("DEPRECATION")
        val uri: Uri? = data.getParcelableExtra(RingtoneManager.EXTRA_RINGTONE_PICKED_URI)
        if (uri == null) {
            result?.success(null)
            return
        }
        val title = RingtoneManager.getRingtone(this, uri)?.getTitle(this) ?: "Ringtone"
        result?.success(mapOf("uri" to uri.toString(), "name" to title))
    }

    private fun copyUriToFile(uri: String, dest: String) {
        val input = contentResolver.openInputStream(Uri.parse(uri))
            ?: throw IllegalStateException("Cannot open $uri")
        input.use { src -> File(dest).outputStream().use { src.copyTo(it) } }
    }

    // Notification channels need a URI the system can read; app-private files
    // are not, so the sound is published to the shared Notifications folder.
    private fun registerNotificationSound(path: String, name: String): String {
        val file = File(path)
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.Q) {
            return Uri.fromFile(file).toString()
        }
        val ext = file.extension.lowercase()
        val mime = MimeTypeMap.getSingleton().getMimeTypeFromExtension(ext) ?: "audio/mpeg"
        val values = ContentValues().apply {
            put(MediaStore.Audio.Media.DISPLAY_NAME, "remindme_${System.currentTimeMillis()}_${file.name}")
            put(MediaStore.Audio.Media.TITLE, name)
            put(MediaStore.Audio.Media.MIME_TYPE, mime)
            put(MediaStore.Audio.Media.RELATIVE_PATH, "Notifications/RemindMe")
            put(MediaStore.Audio.Media.IS_NOTIFICATION, 1)
            put(MediaStore.Audio.Media.IS_PENDING, 1)
        }
        val collection = MediaStore.Audio.Media.getContentUri(MediaStore.VOLUME_EXTERNAL_PRIMARY)
        val uri = contentResolver.insert(collection, values)
            ?: throw IllegalStateException("MediaStore insert failed")
        contentResolver.openOutputStream(uri)!!.use { out -> file.inputStream().use { it.copyTo(out) } }
        values.clear()
        values.put(MediaStore.Audio.Media.IS_PENDING, 0)
        contentResolver.update(uri, values, null, null)
        return uri.toString()
    }

    companion object {
        private const val CHANNEL = "remind_me/sound"
        private const val PICK_RINGTONE = 4711
    }
}
