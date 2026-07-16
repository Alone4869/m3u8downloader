package io.github.alone4869.m3u8downloader

import android.Manifest
import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.content.IntentFilter
import android.net.Uri
import android.content.pm.PackageManager
import android.graphics.Bitmap
import android.media.MediaMetadataRetriever
import android.os.Build
import android.util.Size
import androidx.core.content.ContextCompat
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodChannel
import java.io.ByteArrayOutputStream
import java.util.concurrent.Executors

class MainActivity : FlutterActivity() {
    private var eventSink: EventChannel.EventSink? = null
    private var uploadEventSink: EventChannel.EventSink? = null
    private var receiverRegistered = false
    private val ioExecutor = Executors.newSingleThreadExecutor()
    private var pendingMediaPermissionResult: MethodChannel.Result? = null

    private val taskReceiver = object : BroadcastReceiver() {
        override fun onReceive(context: Context?, intent: Intent?) {
            val json = intent?.getStringExtra(DownloadService.EXTRA_TASK) ?: return
            eventSink?.success(TaskStore.jsonToMap(json))
        }
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, METHODS).setMethodCallHandler { call, result ->
            when (call.method) {
                "startDownload" -> {
                    val url = call.argument<String>("url")?.trim().orEmpty()
                    val fileName = call.argument<String>("fileName")?.trim().orEmpty()
                    val cookie = call.argument<String>("cookie").orEmpty()
                    val sourceUrl = call.argument<String>("sourceUrl")?.trim().orEmpty()
                    if (url.isBlank() || fileName.isBlank()) {
                        result.error("invalid_arguments", "下载链接和文件名不能为空", null)
                        return@setMethodCallHandler
                    }
                    requestNotificationPermissionIfNeeded()
                    val intent = Intent(this, DownloadService::class.java).apply {
                        action = DownloadService.ACTION_START
                        putExtra(DownloadService.EXTRA_URL, url)
                        putExtra(DownloadService.EXTRA_FILE_NAME, fileName)
                        putExtra(DownloadService.EXTRA_COOKIE, cookie)
                        putExtra(DownloadService.EXTRA_SOURCE_URL, sourceUrl)
                    }
                    ContextCompat.startForegroundService(this, intent)
                    result.success(null)
                }

                "cancelDownload" -> {
                    val id = call.argument<String>("id").orEmpty()
                    startService(Intent(this, DownloadService::class.java).apply {
                        action = DownloadService.ACTION_CANCEL
                        putExtra(DownloadService.EXTRA_ID, id)
                    })
                    result.success(null)
                }

                "getTasks" -> result.success(TaskStore.getTasks(this))
                "getAppInfo" -> {
                    val info = packageManager.getPackageInfo(packageName, 0)
                    val versionCode = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.P) {
                        info.longVersionCode
                    } else {
                        @Suppress("DEPRECATION")
                        info.versionCode.toLong()
                    }
                    result.success(
                        mapOf(
                            "versionName" to info.versionName.orEmpty(),
                            "versionCode" to versionCode,
                            "supportedAbis" to Build.SUPPORTED_ABIS.toList(),
                        ),
                    )
                }
                "openUrl" -> {
                    val url = call.argument<String>("url").orEmpty()
                    val uri = Uri.parse(url)
                    if (uri.scheme !in setOf("http", "https")) {
                        result.error("invalid_url", "仅支持 HTTP 或 HTTPS 地址", null)
                        return@setMethodCallHandler
                    }
                    try {
                        startActivity(Intent(Intent.ACTION_VIEW, uri))
                        result.success(null)
                    } catch (error: Exception) {
                        result.error("open_failed", error.message ?: "无法打开下载地址", null)
                    }
                }
                "ensureLocalMediaAccess" -> {
                    val fileNames = call.argument<List<String>>("fileNames").orEmpty()
                    val contentUris = call.argument<List<String>>("contentUris").orEmpty()
                    val fileSizes = call.argument<List<Number>>("fileSizes").orEmpty().map { it.toLong() }
                    runIo(result) {
                        val allReadable = fileNames.indices.all { index ->
                            LocalDownloads.resolve(
                                this,
                                contentUris.getOrNull(index).orEmpty(),
                                fileNames[index],
                                fileSizes.getOrNull(index) ?: 0L,
                            ) != null
                        }
                        if (allReadable) {
                            true
                        } else {
                            runOnUiThread { requestMediaPermission(result) }
                            ASYNC_RESULT
                        }
                    }
                }
                "openVideo" -> {
                    val fileName = call.argument<String>("fileName").orEmpty()
                    val contentUri = call.argument<String>("contentUri").orEmpty()
                    val fileSize = (call.argument<Number>("fileSize"))?.toLong() ?: 0L
                    try {
                        openDownloadedVideo(fileName, contentUri, fileSize)
                        result.success(null)
                    } catch (error: Exception) {
                        result.error("open_failed", error.message ?: "无法打开视频", null)
                    }
                }
                "getVideoThumbnail" -> {
                    val fileName = call.argument<String>("fileName").orEmpty()
                    val contentUri = call.argument<String>("contentUri").orEmpty()
                    val fileSize = (call.argument<Number>("fileSize"))?.toLong() ?: 0L
                    runIo(result) { createVideoThumbnail(fileName, contentUri, fileSize) }
                }
                "deleteTasks" -> {
                    val ids = call.argument<List<String>>("ids").orEmpty().toSet()
                    val fileNames = call.argument<List<String>>("fileNames").orEmpty()
                    val contentUris = call.argument<List<String>>("contentUris").orEmpty()
                    val fileSizes = call.argument<List<Number>>("fileSizes").orEmpty().map { it.toLong() }
                    val deleteFiles = call.argument<Boolean>("deleteFiles") == true
                    runIo(result) {
                        if (deleteFiles) {
                            fileNames.forEachIndexed { index, fileName ->
                                deleteDownloadedFile(
                                    fileName,
                                    contentUris.getOrNull(index).orEmpty(),
                                    fileSizes.getOrNull(index) ?: 0L,
                                )
                            }
                        }
                        TaskStore.delete(this, ids)
                        null
                    }
                }
                "testSmb" -> {
                    val config = SmbConfig.fromMap(call.argument<Map<*, *>>("config").orEmpty())
                    runIo(result) {
                        SmbClient(this, config).testConnection()
                        null
                    }
                }
                "listSmbFolders" -> {
                    val config = SmbConfig.fromMap(call.argument<Map<*, *>>("config").orEmpty())
                    val path = call.argument<String>("path").orEmpty()
                    runIo(result) { SmbClient(this, config).listFolders(path) }
                }
                "uploadToSmb" -> {
                    val config = SmbConfig.fromMap(call.argument<Map<*, *>>("config").orEmpty())
                    val path = call.argument<String>("path").orEmpty()
                    val ids = call.argument<List<String>>("ids").orEmpty()
                    val fileNames = call.argument<List<String>>("fileNames").orEmpty()
                    val contentUris = call.argument<List<String>>("contentUris").orEmpty()
                    val fileSizes = call.argument<List<Number>>("fileSizes").orEmpty().map { it.toLong() }
                    runIo(result) {
                        SmbClient(this, config).upload(
                            path = path,
                            fileNames = fileNames,
                            contentUris = contentUris,
                            fileSizes = fileSizes,
                            onProgress = { progress ->
                                runOnUiThread { uploadEventSink?.success(progress) }
                            },
                            onFileUploaded = { index ->
                                ids.getOrNull(index)?.let { id ->
                                    TaskStore.markUploaded(this, setOf(id)).forEach(::broadcastTask)
                                }
                            },
                        )
                        null
                    }
                }
                else -> result.notImplemented()
            }
        }

        EventChannel(flutterEngine.dartExecutor.binaryMessenger, EVENTS).setStreamHandler(
            object : EventChannel.StreamHandler {
                override fun onListen(arguments: Any?, events: EventChannel.EventSink?) {
                    eventSink = events
                    registerTaskReceiver()
                }

                override fun onCancel(arguments: Any?) {
                    eventSink = null
                    unregisterTaskReceiver()
                }
            },
        )

        EventChannel(flutterEngine.dartExecutor.binaryMessenger, UPLOAD_EVENTS).setStreamHandler(
            object : EventChannel.StreamHandler {
                override fun onListen(arguments: Any?, events: EventChannel.EventSink?) {
                    uploadEventSink = events
                }

                override fun onCancel(arguments: Any?) {
                    uploadEventSink = null
                }
            },
        )
    }

    private fun registerTaskReceiver() {
        if (receiverRegistered) return
        val filter = IntentFilter(DownloadService.ACTION_TASK_UPDATE)
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
            registerReceiver(taskReceiver, filter, RECEIVER_NOT_EXPORTED)
        } else {
            @Suppress("UnspecifiedRegisterReceiverFlag")
            registerReceiver(taskReceiver, filter)
        }
        receiverRegistered = true
    }

    private fun unregisterTaskReceiver() {
        if (!receiverRegistered) return
        unregisterReceiver(taskReceiver)
        receiverRegistered = false
    }

    private fun requestNotificationPermissionIfNeeded() {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU &&
            checkSelfPermission(Manifest.permission.POST_NOTIFICATIONS) != PackageManager.PERMISSION_GRANTED
        ) {
            requestPermissions(arrayOf(Manifest.permission.POST_NOTIFICATIONS), 1001)
        }
    }

    private fun requestMediaPermission(result: MethodChannel.Result) {
        val permissions = when {
            Build.VERSION.SDK_INT >= Build.VERSION_CODES.UPSIDE_DOWN_CAKE -> arrayOf(
                Manifest.permission.READ_MEDIA_VIDEO,
                Manifest.permission.READ_MEDIA_VISUAL_USER_SELECTED,
            )
            Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU ->
                arrayOf(Manifest.permission.READ_MEDIA_VIDEO)
            else -> arrayOf(Manifest.permission.READ_EXTERNAL_STORAGE)
        }
        if (permissions.any { checkSelfPermission(it) == PackageManager.PERMISSION_GRANTED }) {
            result.success(true)
            return
        }
        if (pendingMediaPermissionResult != null) {
            result.error("permission_pending", "正在等待视频访问授权", null)
            return
        }
        pendingMediaPermissionResult = result
        requestPermissions(permissions, MEDIA_PERMISSION_REQUEST)
    }

    override fun onRequestPermissionsResult(
        requestCode: Int,
        permissions: Array<out String>,
        grantResults: IntArray,
    ) {
        super.onRequestPermissionsResult(requestCode, permissions, grantResults)
        if (requestCode == MEDIA_PERMISSION_REQUEST) {
            pendingMediaPermissionResult?.success(
                grantResults.any { it == PackageManager.PERMISSION_GRANTED },
            )
            pendingMediaPermissionResult = null
        }
    }

    private fun openDownloadedVideo(fileName: String, contentUri: String, fileSize: Long) {
        val uri = LocalDownloads.resolve(this, contentUri, fileName, fileSize)
            ?: throw IllegalStateException("未找到或无法读取已下载的视频文件")

        val intent = Intent(Intent.ACTION_VIEW).apply {
            setDataAndType(uri, if (fileName.endsWith(".ts", true)) "video/mp2t" else "video/mp4")
            addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
        }
        if (intent.resolveActivity(packageManager) == null) {
            throw IllegalStateException("系统中没有可播放此视频的应用")
        }
        startActivity(intent)
    }

    private fun createVideoThumbnail(
        fileName: String,
        contentUri: String,
        fileSize: Long,
    ): ByteArray? {
        val uri = LocalDownloads.resolve(this, contentUri, fileName, fileSize) ?: return null
        val bitmap = runCatching {
            contentResolver.loadThumbnail(uri, Size(THUMBNAIL_WIDTH, THUMBNAIL_HEIGHT), null)
        }.getOrNull() ?: runCatching {
            MediaMetadataRetriever().use { retriever ->
                retriever.setDataSource(this, uri)
                retriever.getFrameAtTime(1_000_000L, MediaMetadataRetriever.OPTION_CLOSEST_SYNC)
            }
        }.getOrNull() ?: return null

        return ByteArrayOutputStream().use { output ->
            bitmap.compress(Bitmap.CompressFormat.JPEG, 82, output)
            output.toByteArray()
        }
    }

    private fun deleteDownloadedFile(fileName: String, contentUri: String, fileSize: Long) {
        LocalDownloads.resolve(this, contentUri, fileName, fileSize)?.let { uri ->
            contentResolver.delete(uri, null, null)
        }
    }

    private fun broadcastTask(task: org.json.JSONObject) {
        sendBroadcast(Intent(DownloadService.ACTION_TASK_UPDATE).apply {
            setPackage(packageName)
            putExtra(DownloadService.EXTRA_TASK, task.toString())
        })
    }

    private fun runIo(result: MethodChannel.Result, operation: () -> Any?) {
        ioExecutor.execute {
            try {
                val value = operation()
                if (value !== ASYNC_RESULT) runOnUiThread { result.success(value) }
            } catch (error: Exception) {
                runOnUiThread {
                    result.error("operation_failed", error.message ?: "操作失败", null)
                }
            }
        }
    }

    override fun onDestroy() {
        ioExecutor.shutdownNow()
        super.onDestroy()
    }

    companion object {
        private const val METHODS = "m3u8_downloader/methods"
        private const val EVENTS = "m3u8_downloader/events"
        private const val UPLOAD_EVENTS = "m3u8_downloader/upload_events"
        private const val MEDIA_PERMISSION_REQUEST = 1002
        private const val THUMBNAIL_WIDTH = 320
        private const val THUMBNAIL_HEIGHT = 180
        private val ASYNC_RESULT = Any()
    }
}
