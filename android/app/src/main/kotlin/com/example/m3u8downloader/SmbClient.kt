package com.example.m3u8downloader

import android.content.Context
import android.net.Uri
import android.provider.MediaStore
import java.io.FileInputStream
import java.net.URLEncoder
import java.util.Properties
import java.util.concurrent.Executors
import java.util.concurrent.Future
import java.util.concurrent.atomic.AtomicLong
import jcifs.CIFSContext
import jcifs.config.PropertyConfiguration
import jcifs.context.BaseContext
import jcifs.smb.NtlmPasswordAuthenticator
import jcifs.smb.SmbFile
import jcifs.smb.SmbFileOutputStream
import jcifs.smb.SmbRandomAccessFile

data class SmbConfig(
    val host: String,
    val port: Int,
    val share: String,
    val username: String,
    val password: String,
    val domain: String,
) {
    companion object {
        fun fromMap(map: Map<*, *>): SmbConfig = SmbConfig(
            host = map["host"]?.toString().orEmpty(),
            port = (map["port"] as? Number)?.toInt() ?: 445,
            share = map["share"]?.toString().orEmpty(),
            username = map["username"]?.toString().orEmpty(),
            password = map["password"]?.toString().orEmpty(),
            domain = map["domain"]?.toString().orEmpty(),
        )
    }
}

class SmbClient(private val androidContext: Context, private val config: SmbConfig) {
    private val context: CIFSContext by lazy {
        val properties = Properties().apply {
            setProperty("jcifs.smb.client.minVersion", "SMB202")
            setProperty("jcifs.smb.client.maxVersion", "SMB311")
            setProperty("jcifs.smb.client.responseTimeout", "30000")
            setProperty("jcifs.smb.client.soTimeout", "60000")
            setProperty("jcifs.smb.client.useLargeReadWrite", "true")
            setProperty("jcifs.smb.client.tcpNoDelay", "true")
            setProperty("jcifs.smb.client.snd_buf_size", SMB_IO_WINDOW.toString())
            setProperty("jcifs.smb.client.rcv_buf_size", SMB_IO_WINDOW.toString())
            // SMB2 negotiation also caps writes to transaction_buf_size. Its
            // jcifs-ng default is only about 64 KiB, regardless of snd_buf_size.
            setProperty("jcifs.smb.client.transaction_buf_size", SMB_IO_WINDOW.toString())
            setProperty("jcifs.smb.client.maxMpxCount", "64")
        }
        BaseContext(PropertyConfiguration(properties)).withCredentials(
            NtlmPasswordAuthenticator(config.domain, config.username, config.password),
        )
    }

    fun testConnection() {
        root("").use { directory ->
            if (!directory.exists() || !directory.isDirectory) {
                error("SMB 共享不存在或不可访问")
            }
            directory.list()
        }
    }

    fun listFolders(path: String): List<Map<String, String>> {
        return directory(path).use { directory ->
            if (!directory.exists() || !directory.isDirectory) error("远程目录不存在")
            directory.listFiles()
                .filter { it.isDirectory }
                .map { folder ->
                    mapOf(
                        "name" to folder.name.removeSuffix("/"),
                        "url" to folder.path,
                    )
                }
                .sortedBy { it["name"]?.lowercase() }
        }
    }

    fun upload(
        path: String,
        fileNames: List<String>,
        contentUris: List<String> = emptyList(),
        fileSizes: List<Long> = emptyList(),
        onProgress: (Map<String, Any>) -> Unit = {},
        onFileUploaded: (Int) -> Unit = {},
    ) {
        if (fileNames.isEmpty()) error("没有选择需要上传的文件")
        directory(path).use { targetDirectory ->
            fileNames.forEachIndexed { index, fileName ->
                val source = LocalDownloads.resolve(
                    androidContext,
                    contentUris.getOrNull(index).orEmpty(),
                    fileName,
                    fileSizes.getOrNull(index) ?: 0L,
                ) ?: error("未找到或无法读取本地文件：$fileName")
                uploadFile(source, targetDirectory, fileName) { uploadedBytes, totalBytes, bytesPerSecond ->
                    onProgress(
                        mapOf(
                            "fileIndex" to index,
                            "fileCount" to fileNames.size,
                            "fileName" to fileName,
                            "uploadedBytes" to uploadedBytes,
                            "totalBytes" to totalBytes,
                            "bytesPerSecond" to bytesPerSecond,
                        ),
                    )
                }
                onFileUploaded(index)
            }
        }
    }

    private fun uploadFile(
        source: Uri,
        targetDirectory: SmbFile,
        fileName: String,
        onProgress: (Long, Long, Double) -> Unit,
    ) {
        val fileSize = localFileSize(source)
        val target = SmbFile(targetDirectory, fileName)
        try {
            target.use { remoteFile ->
                val reporter = UploadProgressReporter(fileSize, onProgress)
                reporter.start()
                if (fileSize >= PARALLEL_UPLOAD_MIN_SIZE && supportsRandomAccess(source, fileSize)) {
                    uploadParallel(source, remoteFile.path, fileName, fileSize, reporter)
                } else {
                    uploadSequential(source, remoteFile, fileName, reporter)
                }
                reporter.finish()
            }
            if (fileSize > 0L) {
                SmbFile(targetDirectory, fileName).use { uploadedFile ->
                    if (uploadedFile.length() != fileSize) error("远端文件大小校验失败：$fileName")
                }
            }
        } catch (error: Exception) {
            runCatching { SmbFile(targetDirectory, fileName).use { it.delete() } }
            throw error
        }
    }

    private fun uploadSequential(
        source: Uri,
        remoteFile: SmbFile,
        fileName: String,
        reporter: UploadProgressReporter,
    ) {
        val descriptor = androidContext.contentResolver.openFileDescriptor(source, "r")
            ?: error("无法读取本地文件：$fileName")
        descriptor.use {
            FileInputStream(it.fileDescriptor).use { input ->
                SmbFileOutputStream(remoteFile, false).use { output ->
                    val buffer = ByteArray(SEQUENTIAL_UPLOAD_BUFFER_SIZE)
                    while (true) {
                        val count = input.read(buffer)
                        if (count < 0) break
                        output.write(buffer, 0, count)
                        reporter.add(count)
                    }
                }
            }
        }
    }

    private fun uploadParallel(
        source: Uri,
        remotePath: String,
        fileName: String,
        fileSize: Long,
        reporter: UploadProgressReporter,
    ) {
        SmbFile(remotePath, context).use { remoteFile ->
            SmbRandomAccessFile(remoteFile, "rw").use { output ->
                output.setLength(fileSize)
            }
        }

        val workerCount = minOf(
            PARALLEL_UPLOAD_WORKERS,
            ((fileSize + PARALLEL_UPLOAD_MIN_RANGE - 1L) / PARALLEL_UPLOAD_MIN_RANGE).toInt(),
        ).coerceAtLeast(1)
        val executor = Executors.newFixedThreadPool(workerCount)
        val futures = mutableListOf<Future<*>>()
        try {
            repeat(workerCount) { workerIndex ->
                val start = fileSize / workerCount * workerIndex
                val end = if (workerIndex == workerCount - 1) {
                    fileSize
                } else {
                    fileSize / workerCount * (workerIndex + 1)
                }
                futures += executor.submit {
                    uploadRange(source, remotePath, fileName, start, end, reporter)
                }
            }
            futures.forEach { future ->
                try {
                    future.get()
                } catch (error: Exception) {
                    futures.forEach { it.cancel(true) }
                    val cause = error.cause
                    if (cause is Exception) throw cause
                    throw error
                }
            }
        } finally {
            executor.shutdownNow()
        }
    }

    private fun uploadRange(
        source: Uri,
        remotePath: String,
        fileName: String,
        start: Long,
        end: Long,
        reporter: UploadProgressReporter,
    ) {
        val descriptor = androidContext.contentResolver.openFileDescriptor(source, "r")
            ?: error("无法读取本地文件：$fileName")
        descriptor.use {
            FileInputStream(it.fileDescriptor).use { input ->
                input.channel.position(start)
                SmbFile(remotePath, context).use { remoteFile ->
                    SmbRandomAccessFile(remoteFile, "rw").use { output ->
                        output.seek(start)
                        val buffer = ByteArray(PARALLEL_UPLOAD_BUFFER_SIZE)
                        var remaining = end - start
                        while (remaining > 0L) {
                            if (Thread.currentThread().isInterrupted) error("上传已取消")
                            val count = input.read(buffer, 0, minOf(buffer.size.toLong(), remaining).toInt())
                            if (count < 0) error("读取本地文件时意外结束：$fileName")
                            output.write(buffer, 0, count)
                            remaining -= count
                            reporter.add(count)
                        }
                    }
                }
            }
        }
    }

    private fun supportsRandomAccess(uri: Uri, fileSize: Long): Boolean {
        if (fileSize <= 1L) return false
        return runCatching {
            val descriptor = androidContext.contentResolver.openFileDescriptor(uri, "r")
                ?: return@runCatching false
            descriptor.use {
                FileInputStream(it.fileDescriptor).use { input ->
                    input.channel.position(1L)
                    input.channel.position(0L)
                }
            }
            true
        }.getOrDefault(false)
    }

    private fun localFileSize(uri: Uri): Long {
        androidContext.contentResolver.openFileDescriptor(uri, "r")?.use { descriptor ->
            if (descriptor.statSize > 0L) return descriptor.statSize
        }
        return androidContext.contentResolver.query(
            uri,
            arrayOf(MediaStore.MediaColumns.SIZE),
            null,
            null,
            null,
        )?.use { cursor ->
            if (cursor.moveToFirst()) cursor.getLong(0) else -1L
        } ?: -1L
    }

    private fun root(path: String) = SmbFile(rootUrl(path), context)

    private fun directory(path: String): SmbFile =
        if (path.startsWith("smb://")) SmbFile(path, context) else root(path)

    private fun rootUrl(path: String): String {
        val host = config.host.removePrefix("smb://").trim().trimEnd('/')
        if (host.isEmpty() || config.share.trim().isEmpty()) error("SMB 配置不完整")
        val authority = if (config.port == 445) host else "$host:${config.port}"
        val suffix = path.split('/').filter { it.isNotBlank() }.joinToString("/") { encode(it) }
        return buildString {
            append("smb://")
            append(authority)
            append('/')
            append(encode(config.share.trim()))
            append('/')
            if (suffix.isNotEmpty()) append(suffix).append('/')
        }
    }

    private fun encode(value: String): String =
        URLEncoder.encode(value, Charsets.UTF_8.name()).replace("+", "%20")

    companion object {
        // Match the desktop uploader's 16 MiB buffering. jcifs-ng takes the
        // minimum of this transaction window, its socket buffer and the NAS's
        // negotiated SMB2/3 maximum, so all three must be raised together.
        private const val SMB_IO_WINDOW = 16 * 1024 * 1024
        private const val SEQUENTIAL_UPLOAD_BUFFER_SIZE = SMB_IO_WINDOW
        private const val PARALLEL_UPLOAD_BUFFER_SIZE = 8 * 1024 * 1024
        private const val PARALLEL_UPLOAD_WORKERS = 4
        private const val PARALLEL_UPLOAD_MIN_SIZE = 32L * 1024 * 1024
        private const val PARALLEL_UPLOAD_MIN_RANGE = 16L * 1024 * 1024
        private const val PROGRESS_INTERVAL_NANOS = 200L * 1_000_000
    }

    private class UploadProgressReporter(
        private val totalBytes: Long,
        private val onProgress: (Long, Long, Double) -> Unit,
    ) {
        private val uploadedBytes = AtomicLong(0L)
        private val lastReportAt = AtomicLong(0L)
        private val startedAt = System.nanoTime()

        fun start() = onProgress(0L, totalBytes, 0.0)

        fun add(count: Int) {
            val uploaded = uploadedBytes.addAndGet(count.toLong())
            val now = System.nanoTime()
            val previous = lastReportAt.get()
            if (
                now - previous >= PROGRESS_INTERVAL_NANOS &&
                lastReportAt.compareAndSet(previous, now)
            ) {
                emit(uploaded, now)
            }
        }

        fun finish() = emit(uploadedBytes.get(), System.nanoTime())

        private fun emit(uploaded: Long, now: Long) {
            val elapsedSeconds = (now - startedAt).coerceAtLeast(1L) / 1_000_000_000.0
            onProgress(uploaded, totalBytes, uploaded / elapsedSeconds)
        }
    }
}
