package io.github.alone4869.m3u8downloader

import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.app.Service
import android.content.ContentValues
import android.content.Intent
import android.net.Uri
import android.os.Build
import android.os.Environment
import android.os.IBinder
import android.provider.MediaStore
import androidx.core.app.NotificationCompat
import java.io.File
import java.io.FileOutputStream
import java.io.IOException
import java.net.HttpURLConnection
import java.net.URL
import java.nio.ByteBuffer
import java.util.Locale
import java.util.concurrent.ConcurrentHashMap
import java.util.concurrent.Executors
import java.util.concurrent.Future
import java.util.concurrent.atomic.AtomicBoolean
import java.util.concurrent.atomic.AtomicInteger
import java.util.concurrent.atomic.AtomicLong
import javax.crypto.Cipher
import javax.crypto.spec.IvParameterSpec
import javax.crypto.spec.SecretKeySpec
import org.json.JSONObject

class DownloadService : Service() {
    private val taskExecutor = Executors.newCachedThreadPool()
    private val cancellationFlags = ConcurrentHashMap<String, AtomicBoolean>()
    private val activeTasks = AtomicInteger(0)

    override fun onCreate() {
        super.onCreate()
        createNotificationChannel()
    }

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        when (intent?.action) {
            ACTION_START -> {
                val url = intent.getStringExtra(EXTRA_URL).orEmpty()
                val fileName = sanitizeFileName(intent.getStringExtra(EXTRA_FILE_NAME).orEmpty())
                val cookie = intent.getStringExtra(EXTRA_COOKIE).orEmpty()
                val sourceUrl = intent.getStringExtra(EXTRA_SOURCE_URL).orEmpty()
                val requestedId = intent.getStringExtra(EXTRA_ID).orEmpty()
                val id = requestedId.takeIf(::isValidTaskId)
                    ?: "${System.currentTimeMillis()}-${url.hashCode().toUInt()}"
                startForeground(
                    FOREGROUND_NOTIFICATION_ID,
                    buildNotification("准备下载", fileName, 0, true),
                )
                activeTasks.incrementAndGet()
                val cancelled = AtomicBoolean(false)
                cancellationFlags[id] = cancelled
                emitTask(id, url, sourceUrl, fileName, "queued", 0.0, "", "")
                taskExecutor.execute { runDownload(id, url, sourceUrl, fileName, cookie, cancelled) }
            }

            ACTION_CANCEL -> intent.getStringExtra(EXTRA_ID)?.let { id ->
                cancellationFlags[id]?.set(true)
            }
        }
        if (intent?.action == ACTION_CANCEL && activeTasks.get() == 0) stopSelf()
        return START_NOT_STICKY
    }

    override fun onBind(intent: Intent?): IBinder? = null

    override fun onDestroy() {
        cancellationFlags.values.forEach { it.set(true) }
        taskExecutor.shutdownNow()
        super.onDestroy()
    }

    private fun runDownload(
        id: String,
        url: String,
        sourceUrl: String,
        fileName: String,
        cookie: String,
        cancelled: AtomicBoolean,
    ) {
        val taskDir = File(cacheDir, "downloads/$id").apply { mkdirs() }
        val output = File(taskDir, "result.part")
        val progress = ProgressReporter(id, url, sourceUrl, fileName)
        try {
            progress.update(0.0)
            if (url.lowercase(Locale.US).contains(".m3u8")) {
                downloadHls(url, output, cookie, cancelled, progress)
            } else {
                downloadDirect(url, output, cookie, cancelled, progress)
            }
            checkCancelled(cancelled)
            val savedDownload = saveToDownloads(output, fileName)
            emitTask(
                id,
                url,
                sourceUrl,
                fileName,
                "completed",
                1.0,
                "",
                savedDownload.displayPath,
                fileSize = output.length(),
                completedAt = System.currentTimeMillis(),
                contentUri = savedDownload.contentUri,
            )
            notificationManager().notify(
                id.hashCode(),
                buildNotification("下载完成", fileName, 100, false),
            )
        } catch (_: DownloadCancelledException) {
            emitTask(id, url, sourceUrl, fileName, "cancelled", progress.value, "", "")
            notificationManager().cancel(id.hashCode())
        } catch (error: Exception) {
            val message = error.message?.take(180) ?: "未知错误"
            emitTask(id, url, sourceUrl, fileName, "failed", progress.value, message, "")
            notificationManager().notify(
                id.hashCode(),
                buildNotification("下载失败", "$fileName：$message", 0, false),
            )
        } finally {
            taskDir.deleteRecursively()
            cancellationFlags.remove(id)
            if (activeTasks.decrementAndGet() <= 0) {
                stopForeground(STOP_FOREGROUND_REMOVE)
                stopSelf()
            }
        }
    }

    private fun downloadHls(
        initialUrl: String,
        output: File,
        cookie: String,
        cancelled: AtomicBoolean,
        progress: ProgressReporter,
    ) {
        val playlist = resolveMediaPlaylist(initialUrl, cookie, cancelled)
        if (playlist.segments.isEmpty()) throw IOException("播放列表中没有可下载的分片")

        val segmentDir = File(output.parentFile, "segments").apply { mkdirs() }
        val completed = AtomicInteger(0)
        val pool = Executors.newFixedThreadPool(minOf(CONNECTIONS, playlist.segments.size))
        val keyCache = ConcurrentHashMap<String, ByteArray>()
        val futures = mutableListOf<Future<*>>()
        try {
            playlist.segments.forEachIndexed { index, segment ->
                futures += pool.submit {
                    checkCancelled(cancelled)
                    var bytes = requestBytes(segment.url, cookie)
                    segment.keyUrl?.let { keyUrl ->
                        val key = keyCache.computeIfAbsent(keyUrl) { requestBytes(it, cookie) }
                        bytes = decryptSegment(bytes, key, segment.iv)
                    }
                    File(segmentDir, index.toString().padStart(8, '0')).writeBytes(bytes)
                    val done = completed.incrementAndGet()
                    progress.update(done.toDouble() / playlist.segments.size)
                }
            }
            waitForFutures(futures, cancelled)
        } finally {
            pool.shutdownNow()
        }

        FileOutputStream(output).buffered().use { sink ->
            playlist.initUrl?.let { sink.write(requestBytes(it, cookie)) }
            playlist.segments.indices.forEach { index ->
                checkCancelled(cancelled)
                File(segmentDir, index.toString().padStart(8, '0')).inputStream().buffered().use {
                    it.copyTo(sink)
                }
            }
        }
    }

    private fun resolveMediaPlaylist(
        url: String,
        cookie: String,
        cancelled: AtomicBoolean,
        depth: Int = 0,
    ): MediaPlaylist {
        if (depth > 4) throw IOException("M3U8 主播放列表嵌套过深")
        checkCancelled(cancelled)
        val text = requestBytes(url, cookie).toString(Charsets.UTF_8)
        if (!text.trimStart().startsWith("#EXTM3U")) throw IOException("链接返回的不是有效 M3U8")
        val lines = text.lineSequence().map { it.trim() }.filter { it.isNotEmpty() }.toList()

        val variants = mutableListOf<Pair<Long, String>>()
        lines.forEachIndexed { index, line ->
            if (line.startsWith("#EXT-X-STREAM-INF")) {
                val bandwidth = Regex("BANDWIDTH=(\\d+)").find(line)?.groupValues?.get(1)?.toLongOrNull() ?: 0
                val child = lines.drop(index + 1).firstOrNull { !it.startsWith("#") }
                if (child != null) variants += bandwidth to resolveUrl(url, child)
            }
        }
        if (variants.isNotEmpty()) {
            return resolveMediaPlaylist(variants.maxBy { it.first }.second, cookie, cancelled, depth + 1)
        }

        var keyUrl: String? = null
        var explicitIv: ByteArray? = null
        var initUrl: String? = null
        var sequence = lines.firstOrNull { it.startsWith("#EXT-X-MEDIA-SEQUENCE:") }
            ?.substringAfter(':')?.toLongOrNull() ?: 0L
        val segments = mutableListOf<HlsSegment>()
        for (line in lines) {
            when {
                line.startsWith("#EXT-X-KEY:") -> {
                    val method = attribute(line, "METHOD")
                    if (method == "NONE") {
                        keyUrl = null
                        explicitIv = null
                    } else if (method == "AES-128") {
                        val keyUri = attribute(line, "URI") ?: throw IOException("加密分片缺少密钥地址")
                        keyUrl = resolveUrl(url, keyUri)
                        explicitIv = attribute(line, "IV")?.let(::hexToBytes)
                    } else {
                        throw IOException("暂不支持的 HLS 加密方式：$method")
                    }
                }

                line.startsWith("#EXT-X-MAP:") -> {
                    attribute(line, "URI")?.let { initUrl = resolveUrl(url, it) }
                }

                !line.startsWith("#") -> {
                    val iv = explicitIv ?: sequenceIv(sequence)
                    segments += HlsSegment(resolveUrl(url, line), keyUrl, iv)
                    sequence++
                }
            }
        }
        return MediaPlaylist(segments, initUrl)
    }

    private fun downloadDirect(
        url: String,
        output: File,
        cookie: String,
        cancelled: AtomicBoolean,
        progress: ProgressReporter,
    ) {
        val length = probeContentLength(url, cookie)
        if (length <= CONNECTIONS * 1024L * 1024L) {
            streamToFile(url, output, cookie, cancelled, progress, length)
            return
        }

        val partDir = File(output.parentFile, "parts").apply { mkdirs() }
        val completedBytes = AtomicLong(0)
        val pool = Executors.newFixedThreadPool(CONNECTIONS)
        val futures = mutableListOf<Future<*>>()
        try {
            repeat(CONNECTIONS) { index ->
                val start = length * index / CONNECTIONS
                val end = if (index == CONNECTIONS - 1) length - 1 else length * (index + 1) / CONNECTIONS - 1
                futures += pool.submit {
                    downloadRange(
                        url,
                        File(partDir, index.toString()),
                        start,
                        end,
                        cookie,
                        cancelled,
                    ) { count ->
                        progress.update(completedBytes.addAndGet(count).toDouble() / length)
                    }
                }
            }
            waitForFutures(futures, cancelled)
        } finally {
            pool.shutdownNow()
        }
        FileOutputStream(output).buffered().use { sink ->
            repeat(CONNECTIONS) { index ->
                File(partDir, index.toString()).inputStream().buffered().use { it.copyTo(sink) }
            }
        }
    }

    private fun streamToFile(
        url: String,
        output: File,
        cookie: String,
        cancelled: AtomicBoolean,
        progress: ProgressReporter,
        expectedLength: Long,
    ) {
        val connection = openConnection(url, cookie)
        ensureSuccess(connection)
        val total = if (expectedLength > 0) expectedLength else connection.contentLengthLong
        var downloaded = 0L
        connection.inputStream.buffered().use { input ->
            FileOutputStream(output).buffered().use { sink ->
                val buffer = ByteArray(BUFFER_SIZE)
                while (true) {
                    checkCancelled(cancelled)
                    val count = input.read(buffer)
                    if (count < 0) break
                    sink.write(buffer, 0, count)
                    downloaded += count
                    if (total > 0) progress.update(downloaded.toDouble() / total)
                }
            }
        }
        connection.disconnect()
    }

    private fun downloadRange(
        url: String,
        output: File,
        start: Long,
        end: Long,
        cookie: String,
        cancelled: AtomicBoolean,
        onBytes: (Long) -> Unit,
    ) {
        val connection = openConnection(url, cookie, "bytes=$start-$end")
        if (connection.responseCode != HttpURLConnection.HTTP_PARTIAL) {
            connection.disconnect()
            throw IOException("服务器未接受分段下载请求")
        }
        connection.inputStream.buffered().use { input ->
            FileOutputStream(output).buffered().use { sink ->
                val buffer = ByteArray(BUFFER_SIZE)
                while (true) {
                    checkCancelled(cancelled)
                    val count = input.read(buffer)
                    if (count < 0) break
                    sink.write(buffer, 0, count)
                    onBytes(count.toLong())
                }
            }
        }
        connection.disconnect()
    }

    private fun probeContentLength(url: String, cookie: String): Long {
        val connection = openConnection(url, cookie, "bytes=0-0")
        return try {
            if (connection.responseCode != HttpURLConnection.HTTP_PARTIAL) return -1
            connection.getHeaderField("Content-Range")?.substringAfterLast('/')?.toLongOrNull() ?: -1
        } finally {
            connection.inputStream?.close()
            connection.disconnect()
        }
    }

    private fun requestBytes(url: String, cookie: String): ByteArray {
        val connection = openConnection(url, cookie)
        ensureSuccess(connection)
        return try {
            connection.inputStream.buffered().use { it.readBytes() }
        } finally {
            connection.disconnect()
        }
    }

    private fun openConnection(url: String, cookie: String, range: String? = null): HttpURLConnection {
        return (URL(url).openConnection() as HttpURLConnection).apply {
            connectTimeout = 20_000
            readTimeout = 30_000
            instanceFollowRedirects = true
            setRequestProperty("User-Agent", USER_AGENT)
            setRequestProperty("Accept", "*/*")
            if (cookie.isNotBlank()) setRequestProperty("Cookie", cookie)
            if (range != null) setRequestProperty("Range", range)
        }
    }

    private fun ensureSuccess(connection: HttpURLConnection) {
        if (connection.responseCode !in 200..299) {
            val message = connection.errorStream?.bufferedReader()?.use { it.readText().take(160) }.orEmpty()
            throw IOException("HTTP ${connection.responseCode}${if (message.isBlank()) "" else "：$message"}")
        }
    }

    private fun waitForFutures(futures: List<Future<*>>, cancelled: AtomicBoolean) {
        futures.forEach { future ->
            checkCancelled(cancelled)
            try {
                future.get()
            } catch (error: Exception) {
                val cause = error.cause
                if (cause is DownloadCancelledException) throw cause
                throw (cause as? Exception ?: error)
            }
        }
    }

    private fun decryptSegment(bytes: ByteArray, key: ByteArray, iv: ByteArray): ByteArray {
        if (key.size != 16) throw IOException("HLS AES-128 密钥长度无效")
        return try {
            Cipher.getInstance("AES/CBC/PKCS5Padding").run {
                init(Cipher.DECRYPT_MODE, SecretKeySpec(key, "AES"), IvParameterSpec(iv))
                doFinal(bytes)
            }
        } catch (_: Exception) {
            Cipher.getInstance("AES/CBC/NoPadding").run {
                init(Cipher.DECRYPT_MODE, SecretKeySpec(key, "AES"), IvParameterSpec(iv))
                doFinal(bytes)
            }
        }
    }

    private fun saveToDownloads(source: File, fileName: String): SavedDownload {
        val values = ContentValues().apply {
            put(MediaStore.Downloads.DISPLAY_NAME, fileName)
            put(MediaStore.Downloads.MIME_TYPE, if (fileName.endsWith(".mp4", true)) "video/mp4" else "video/mp2t")
            put(MediaStore.Downloads.RELATIVE_PATH, "${Environment.DIRECTORY_DOWNLOADS}/M3U8 Downloader")
            put(MediaStore.Downloads.IS_PENDING, 1)
        }
        val uri = contentResolver.insert(MediaStore.Downloads.EXTERNAL_CONTENT_URI, values)
            ?: throw IOException("无法在系统下载目录创建文件")
        try {
            contentResolver.openOutputStream(uri)?.buffered()?.use { sink ->
                source.inputStream().buffered().use { it.copyTo(sink) }
            } ?: throw IOException("无法写入系统下载目录")
            contentResolver.update(uri, ContentValues().apply {
                put(MediaStore.Downloads.IS_PENDING, 0)
            }, null, null)
            return SavedDownload(
                displayPath = "下载/M3U8 Downloader/$fileName",
                contentUri = uri.toString(),
            )
        } catch (error: Exception) {
            contentResolver.delete(uri, null, null)
            throw error
        }
    }

    private fun emitTask(
        id: String,
        url: String,
        sourceUrl: String,
        fileName: String,
        status: String,
        progress: Double,
        message: String,
        savedPath: String,
        fileSize: Long = 0L,
        completedAt: Long = 0L,
        contentUri: String = "",
    ) {
        val createdAt = id.substringBefore('-').toLongOrNull() ?: System.currentTimeMillis()
        val task = JSONObject().apply {
            put("id", id)
            put("url", url)
            put("sourceUrl", sourceUrl)
            put("fileName", fileName)
            put("status", status)
            put("progress", progress.coerceIn(0.0, 1.0))
            put("message", message)
            put("savedPath", savedPath)
            put("contentUri", contentUri)
            put("createdAt", createdAt)
            put("completedAt", completedAt)
            put("fileSize", fileSize)
            put("uploaded", false)
        }
        TaskStore.upsert(this, task)
        sendBroadcast(Intent(ACTION_TASK_UPDATE).apply {
            setPackage(packageName)
            putExtra(EXTRA_TASK, task.toString())
        })
    }

    private inner class ProgressReporter(
        private val id: String,
        private val url: String,
        private val sourceUrl: String,
        private val fileName: String,
    ) {
        var value: Double = 0.0
            private set
        private var lastReportAt = 0L
        private var lastPercent = -1

        fun update(newValue: Double) {
            value = newValue.coerceIn(0.0, 1.0)
            val now = System.currentTimeMillis()
            val percent = (value * 100).toInt()
            if (percent == lastPercent || (now - lastReportAt < 500 && percent < 100)) return
            lastPercent = percent
            lastReportAt = now
            emitTask(id, url, sourceUrl, fileName, "downloading", value, "", "")
            notificationManager().notify(
                FOREGROUND_NOTIFICATION_ID,
                buildNotification("正在下载", fileName, percent, true),
            )
        }
    }

    private fun buildNotification(title: String, text: String, progress: Int, ongoing: Boolean) =
        NotificationCompat.Builder(this, CHANNEL_ID)
            .setSmallIcon(android.R.drawable.stat_sys_download)
            .setContentTitle(title)
            .setContentText(text)
            .setOnlyAlertOnce(true)
            .setOngoing(ongoing)
            .setProgress(100, progress, ongoing && progress <= 0)
            .setContentIntent(
                PendingIntent.getActivity(
                    this,
                    0,
                    Intent(this, MainActivity::class.java),
                    PendingIntent.FLAG_IMMUTABLE or PendingIntent.FLAG_UPDATE_CURRENT,
                ),
            )
            .build()

    private fun createNotificationChannel() {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            notificationManager().createNotificationChannel(
                NotificationChannel(CHANNEL_ID, "视频下载", NotificationManager.IMPORTANCE_LOW),
            )
        }
    }

    private fun notificationManager() = getSystemService(NotificationManager::class.java)

    private fun checkCancelled(cancelled: AtomicBoolean) {
        if (cancelled.get() || Thread.currentThread().isInterrupted) throw DownloadCancelledException()
    }

    private fun sanitizeFileName(input: String): String {
        return input.replace(Regex("[\\\\/:*?\"<>|]"), "_").ifBlank { "video.ts" }.take(180)
    }

    private fun isValidTaskId(value: String): Boolean {
        return value.length in 1..180 && value.all { it.isLetterOrDigit() || it in "._-" }
    }

    private fun resolveUrl(base: String, child: String): String = URL(URL(base), child).toString()

    private fun attribute(line: String, name: String): String? {
        val quoted = Regex("(?:^|,)$name=\"([^\"]*)\"").find(line.substringAfter(':'))
        if (quoted != null) return quoted.groupValues[1]
        return Regex("(?:^|,)$name=([^,]*)").find(line.substringAfter(':'))?.groupValues?.get(1)
    }

    private fun sequenceIv(sequence: Long): ByteArray = ByteBuffer.allocate(16).apply {
        putLong(0L)
        putLong(sequence)
    }.array()

    private fun hexToBytes(value: String): ByteArray {
        val hex = value.removePrefix("0x").padStart(32, '0')
        if (hex.length != 32) throw IOException("HLS IV 长度无效")
        return ByteArray(16) { index -> hex.substring(index * 2, index * 2 + 2).toInt(16).toByte() }
    }

    data class HlsSegment(val url: String, val keyUrl: String?, val iv: ByteArray)
    data class MediaPlaylist(val segments: List<HlsSegment>, val initUrl: String?)
    data class SavedDownload(val displayPath: String, val contentUri: String)
    class DownloadCancelledException : IOException("下载已取消")

    companion object {
        const val ACTION_START = "io.github.alone4869.m3u8downloader.START"
        const val ACTION_CANCEL = "io.github.alone4869.m3u8downloader.CANCEL"
        const val ACTION_TASK_UPDATE = "io.github.alone4869.m3u8downloader.TASK_UPDATE"
        const val EXTRA_URL = "url"
        const val EXTRA_FILE_NAME = "fileName"
        const val EXTRA_COOKIE = "cookie"
        const val EXTRA_SOURCE_URL = "sourceUrl"
        const val EXTRA_ID = "id"
        const val EXTRA_TASK = "task"

        private const val CHANNEL_ID = "downloads"
        private const val FOREGROUND_NOTIFICATION_ID = 41
        private const val CONNECTIONS = 6
        private const val BUFFER_SIZE = 64 * 1024
        private const val USER_AGENT =
            "Mozilla/5.0 (Linux; Android 14) AppleWebKit/537.36 Chrome/126.0 Mobile Safari/537.36"
    }
}
