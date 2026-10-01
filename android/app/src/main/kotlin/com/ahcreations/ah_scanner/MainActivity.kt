package com.ahcreations.ah_scanner

import android.Manifest
import android.content.ContentValues
import android.content.pm.PackageManager
import android.media.MediaScannerConnection
import android.content.Intent
import android.net.Uri
import android.os.Build
import android.os.Bundle
import android.os.Environment
import android.provider.MediaStore
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.io.File

class MainActivity : FlutterActivity() {
    companion object {
        private const val CHANNEL = "ah_scanner/media_store"
        private const val MIME_JPEG = "image/jpeg"
        private const val FOLDER_NAME = "AH Scanner"
    }

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        createSharedFolders()
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
            splashScreen.setOnExitAnimationListener { splashScreenView ->
                splashScreenView.remove()
            }
        }
    }

    /**
     * Creates the shared `AH Scanner` folder as soon as the app is opened after
     * installation, so every scan has one obvious home no matter which save
     * button the user picks.
     *
     * Best effort by design: on devices that refuse a direct folder creation, the
     * MediaStore save path creates the very same directory on the first scan.
     */
    private fun createSharedFolders() {
        runCatching {
            for (type in listOf(
                Environment.DIRECTORY_PICTURES,
                Environment.DIRECTORY_DOWNLOADS,
            )) {
                val folder = File(
                    Environment.getExternalStoragePublicDirectory(type),
                    FOLDER_NAME,
                )
                if (!folder.exists()) folder.mkdirs()
            }
        }
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL)
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "getSdkInt" -> result.success(Build.VERSION.SDK_INT)

                    // Opens an external link (release / download page) without
                    // pulling in another plugin dependency.
                    "openUrl" -> {
                        val url = call.argument<String>("url")
                        if (url.isNullOrBlank()) {
                            result.success(false)
                        } else {
                            try {
                                val intent = Intent(Intent.ACTION_VIEW, Uri.parse(url))
                                intent.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                                startActivity(intent)
                                result.success(true)
                            } catch (e: Exception) {
                                result.success(false)
                            }
                        }
                    }

                    // Single source of truth for the About screen: name comes from
                    // values/strings.xml and the version from the built package.
                    "getAppInfo" -> {
                        val pkg = packageManager.getPackageInfo(packageName, 0)
                        val code = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.P) {
                            pkg.longVersionCode.toInt()
                        } else {
                            @Suppress("DEPRECATION") pkg.versionCode
                        }
                        result.success(
                            mapOf(
                                "appName" to getString(R.string.app_name),
                                "versionName" to pkg.versionName,
                                "versionCode" to code
                            )
                        )
                    }

                    "saveImage" -> {
                        val bytes = call.argument<ByteArray>("bytes")
                        val fileName = call.argument<String>("fileName")
                        val folder = call.argument<String>("folder") ?: FOLDER_NAME
                        val toDownloads = call.argument<Boolean>("toDownloads") ?: false

                        if (bytes == null || fileName == null) {
                            result.error("BAD_ARGS", "bytes and fileName are required", null)
                            return@setMethodCallHandler
                        }

                        try {
                            val path = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
                                saveViaMediaStore(bytes, folder, fileName, toDownloads)
                            } else {
                                saveToPublicDir(bytes, folder, fileName, toDownloads)
                            }
                            result.success(path)
                        } catch (e: SecurityException) {
                            result.error("NEEDS_PERMISSION", e.message, null)
                        } catch (e: Exception) {
                            result.error("SAVE_FAILED", e.message, null)
                        }
                    }

                    else -> result.notImplemented()
                }
            }
    }

    /**
     * Android 10+ path: hand the bytes to MediaStore inside the public
     * Pictures/AH Scanner (or Download/AH Scanner) collection.
     *
     * MediaStore resolves duplicate display names by itself, so saving a file
     * whose name already exists silently produces "name (1).jpg" — the app
     * never has to rename anything and no "same name" error can surface.
     */
    private fun saveViaMediaStore(
        bytes: ByteArray,
        folder: String,
        fileName: String,
        toDownloads: Boolean,
    ): String {
        val collection = if (toDownloads) {
            MediaStore.Downloads.EXTERNAL_CONTENT_URI
        } else {
            MediaStore.Images.Media.EXTERNAL_CONTENT_URI
        }
        val relativePath = if (toDownloads) {
            "${Environment.DIRECTORY_DOWNLOADS}/$folder"
        } else {
            "${Environment.DIRECTORY_PICTURES}/$folder"
        }

        val values = ContentValues().apply {
            put(MediaStore.MediaColumns.DISPLAY_NAME, fileName)
            put(MediaStore.MediaColumns.MIME_TYPE, MIME_JPEG)
            put(MediaStore.MediaColumns.RELATIVE_PATH, relativePath)
            // DATE_ADDED is the timestamp the Gallery sorts the timeline by;
            // leaving it unset can push fresh scans to the very bottom.
            put(MediaStore.MediaColumns.DATE_ADDED, System.currentTimeMillis() / 1000)
            put(MediaStore.MediaColumns.IS_PENDING, 1)
        }

        val resolver = contentResolver
        val uri = resolver.insert(collection, values)
            ?: throw IllegalStateException("MediaStore refused to create the file")

        try {
            resolver.openOutputStream(uri)?.use { out ->
                out.write(bytes)
                out.flush()
            } ?: throw IllegalStateException("Could not open an output stream")
        } catch (e: Exception) {
            // Never leave a half-written, permanently pending entry behind.
            runCatching { resolver.delete(uri, null, null) }
            throw e
        }

        values.clear()
        values.put(MediaStore.MediaColumns.IS_PENDING, 0)
        resolver.update(uri, values, null, null)

        // MediaStore may have de-duplicated the name; report what actually landed
        // and prove the row is really visible. Reporting success for a row the
        // Gallery cannot see is worse than an honest failure.
        var storedName = fileName
        var isVisible = false
        resolver.query(
            uri,
            arrayOf(
                MediaStore.MediaColumns.DISPLAY_NAME,
                MediaStore.MediaColumns.IS_PENDING,
            ),
            null,
            null,
            null,
        )?.use { cursor ->
            if (cursor.moveToFirst()) {
                storedName = cursor.getString(0)
                isVisible = cursor.getInt(1) == 0
            }
        }

        if (!isVisible) {
            runCatching { resolver.delete(uri, null, null) }
            throw IllegalStateException(
                "Saved file did not become visible in the Gallery index",
            )
        }

        return "$relativePath/$storedName"
    }

    /**
     * Android 7-9 path: MediaStore inserts into the public collections are not
     * available, so write the file directly and let the media scanner publish
     * it to the Gallery. Requires WRITE_EXTERNAL_STORAGE at runtime.
     */
    private fun saveToPublicDir(
        bytes: ByteArray,
        folder: String,
        fileName: String,
        toDownloads: Boolean,
    ): String {
        if (checkSelfPermission(Manifest.permission.WRITE_EXTERNAL_STORAGE) !=
            PackageManager.PERMISSION_GRANTED
        ) {
            throw SecurityException("WRITE_EXTERNAL_STORAGE has not been granted")
        }

        val baseDir = if (toDownloads) {
            Environment.getExternalStoragePublicDirectory(Environment.DIRECTORY_DOWNLOADS)
        } else {
            Environment.getExternalStoragePublicDirectory(Environment.DIRECTORY_PICTURES)
        }
        val targetDir = File(baseDir, folder)
        if (!targetDir.exists() && !targetDir.mkdirs()) {
            throw IllegalStateException("Could not create ${targetDir.absolutePath}")
        }

        val target = uniqueFile(targetDir, fileName)
        target.writeBytes(bytes)

        MediaScannerConnection.scanFile(
            applicationContext,
            arrayOf(target.absolutePath),
            arrayOf(MIME_JPEG),
            null,
        )

        return target.absolutePath
    }

    /** Mirrors MediaStore's behaviour by appending " (n)" until the name is free. */
    private fun uniqueFile(dir: File, fileName: String): File {
        val candidate = File(dir, fileName)
        if (!candidate.exists()) return candidate

        val dot = fileName.lastIndexOf('.')
        val stem = if (dot > 0) fileName.substring(0, dot) else fileName
        val extension = if (dot > 0) fileName.substring(dot) else ""

        var index = 1
        while (true) {
            val next = File(dir, "$stem ($index)$extension")
            if (!next.exists()) return next
            index++
        }
    }
}
