package io.github.alone4869.m3u8downloader

import android.content.Context
import android.net.Uri
import android.provider.MediaStore
import java.io.FileInputStream
import java.net.URLEncoder
import java.util.Properties
import java.util.concurrent.Executors
import java.util.concurrent.Future
import java.util.concurrent.TimeUnit
import java.util.concurrent.atomic.AtomicLong
import jcifs.CIFSContext
import jcifs.DialectVersion
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
    private val context: CIFSContext by lazy { createContext(SMB_IO_WINDOW) }
    private val compatibilityContext: CIFSContext by lazy {
        createContext(SMB_COMPAT_TRANSACTION_WINDOW)
    }

    private fun createContext(transactionWindow: Int): CIFSContext {
        val properties = Properties().apply {
            setProperty("jcifs.smb.client.minVersion", "SMB202")
            setProperty("jcifs.smb.client.maxVersion", "SMB311")
            // Avoid the legacy SMB1 multi-protocol handshake. Some NAS devices
            // answer that handshake with SMB 2.0.2 and a one-credit 64 KiB cap.
            setProperty("jcifs.smb.client.useSMB2Negotiation", "true")
            setProperty("jcifs.smb.client.responseTimeout", "30000")
            setProperty("jcifs.smb.client.soTimeout", "60000")
            setProperty("jcifs.smb.client.useLargeReadWrite", "true")
            setProperty("jcifs.smb.client.tcpNoDelay", "true")
            setProperty("jcifs.smb.client.snd_buf_size", SMB_IO_WINDOW.toString())
            setProperty("jcifs.smb.client.rcv_buf_size", SMB_IO_WINDOW.toString())
            setProperty("jcifs.smb.client.transaction_buf_size", transactionWindow.toString())
            setProperty("jcifs.smb.client.maxMpxCount", "64")
        }
        return BaseContext(PropertyConfiguration(properties)).withCredentials(
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
                uploadFile(source, targetDirectory, fileName) { uploadedBytes, totalBytes, bytesPerSecond, protocol ->
                    onProgress(
                        mapOf(
                            "fileIndex" to index,
                            "fileCount" to fileNames.size,
                            "fileName" to fileName,
                            "uploadedBytes" to uploadedBytes,
                            "totalBytes" to totalBytes,
                            "bytesPerSecond" to bytesPerSecond,
                            "protocol" to protocol,
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
        onProgress: (Long, Long, Double, String) -> Unit,
    ) {
        val fileSize = localFileSize(source)
        val remotePath = SmbFile(targetDirectory, fileName).use { it.path }
        var activeContext = context
        try {
            if (supportsLargeMtu(remotePath, context) == false) {
                activeContext = compatibilityContext
                uploadAttempt(
                    source,
                    remotePath,
                    fileName,
                    fileSize,
                    compatibilityContext,
                    COMPAT_PARALLEL_UPLOAD_WORKERS,
                    COMPAT_PARALLEL_UPLOAD_MIN_RANGE,
                    COMPAT_PARALLEL_UPLOAD_BUFFER_SIZE,
                    true,
                    onProgress,
                )
            } else {
                try {
                    uploadAttempt(
                        source,
                        remotePath,
                        fileName,
                        fileSize,
                        context,
                        PARALLEL_UPLOAD_WORKERS,
                        PARALLEL_UPLOAD_MIN_RANGE,
                        PARALLEL_UPLOAD_BUFFER_SIZE,
                        false,
                        onProgress,
                    )
                } catch (error: Exception) {
                    if (!isOversizedRequest(error)) throw error
                    deleteRemoteFile(remotePath, context)
                    activeContext = compatibilityContext
                    uploadAttempt(
                        source,
                        remotePath,
                        fileName,
                        fileSize,
                        compatibilityContext,
                        COMPAT_PARALLEL_UPLOAD_WORKERS,
                        COMPAT_PARALLEL_UPLOAD_MIN_RANGE,
                        COMPAT_PARALLEL_UPLOAD_BUFFER_SIZE,
                        true,
                        onProgress,
                    )
                }
            }
            if (fileSize > 0L) {
                SmbFile(remotePath, activeContext).use { uploadedFile ->
                    if (uploadedFile.length() != fileSize) error("远端文件大小校验失败：$fileName")
                }
            }
        } catch (error: Exception) {
            deleteRemoteFile(remotePath, activeContext)
            throw error
        }
    }

    private fun uploadAttempt(
        source: Uri,
        remotePath: String,
        fileName: String,
        fileSize: Long,
        cifsContext: CIFSContext,
        maxWorkers: Int,
        minimumRange: Long,
        bufferSize: Int,
        compatibilityMode: Boolean,
        onProgress: (Long, Long, Double, String) -> Unit,
    ) {
        val protocol = negotiatedProtocol(remotePath, cifsContext, compatibilityMode)
        val reporter = UploadProgressReporter(fileSize, protocol, onProgress)
        reporter.start()
        if (fileSize >= PARALLEL_UPLOAD_MIN_SIZE && supportsRandomAccess(source, fileSize)) {
            uploadParallel(
                source,
                remotePath,
                fileName,
                fileSize,
                cifsContext,
                maxWorkers,
                minimumRange,
                bufferSize,
                compatibilityMode,
                reporter,
            )
        } else {
            SmbFile(remotePath, cifsContext).use { remoteFile ->
                uploadSequential(source, remoteFile, fileName, reporter)
            }
        }
        reporter.finish()
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
                    reporter.beginTransfer()
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
        cifsContext: CIFSContext,
        maxWorkers: Int,
        minimumRange: Long,
        bufferSize: Int,
        isolatedConnections: Boolean,
        reporter: UploadProgressReporter,
    ) {
        SmbFile(remotePath, cifsContext).use { remoteFile ->
            SmbRandomAccessFile(remoteFile, "rw").use { output ->
                output.setLength(fileSize)
            }
        }

        val workerCount = minOf(
            maxWorkers,
            ((fileSize + minimumRange - 1L) / minimumRange).toInt(),
        ).coerceAtLeast(1)
        val executor = Executors.newFixedThreadPool(workerCount)
        val workerContexts = if (isolatedConnections) {
            List(workerCount) { createContext(SMB_COMPAT_TRANSACTION_WINDOW) }
        } else {
            List(workerCount) { cifsContext }
        }
        try {
            if (isolatedConnections) {
                val connectionFutures = workerContexts.map { workerContext ->
                    executor.submit {
                        SmbFile(remotePath, workerContext).use { it.connect() }
                    }
                }
                awaitFutures(connectionFutures)
            }
            reporter.beginTransfer()
            val futures = mutableListOf<Future<*>>()
            repeat(workerCount) { workerIndex ->
                val start = fileSize / workerCount * workerIndex
                val end = if (workerIndex == workerCount - 1) {
                    fileSize
                } else {
                    fileSize / workerCount * (workerIndex + 1)
                }
                futures += executor.submit {
                    uploadRange(
                        source,
                        remotePath,
                        fileName,
                        start,
                        end,
                        workerContexts[workerIndex],
                        bufferSize,
                        reporter,
                    )
                }
            }
            awaitFutures(futures)
        } finally {
            executor.shutdownNow()
            executor.awaitTermination(5L, TimeUnit.SECONDS)
            if (isolatedConnections) {
                workerContexts.forEach { workerContext ->
                    runCatching { workerContext.close() }
                }
            }
        }
    }

    private fun awaitFutures(futures: List<Future<*>>) {
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
    }

    private fun uploadRange(
        source: Uri,
        remotePath: String,
        fileName: String,
        start: Long,
        end: Long,
        cifsContext: CIFSContext,
        bufferSize: Int,
        reporter: UploadProgressReporter,
    ) {
        val descriptor = androidContext.contentResolver.openFileDescriptor(source, "r")
            ?: error("无法读取本地文件：$fileName")
        descriptor.use {
            FileInputStream(it.fileDescriptor).use { input ->
                input.channel.position(start)
                SmbFile(remotePath, cifsContext).use { remoteFile ->
                    SmbRandomAccessFile(remoteFile, "rw").use { output ->
                        output.seek(start)
                        val buffer = ByteArray(bufferSize)
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

    private fun isOversizedRequest(error: Exception): Boolean {
        var current: Throwable? = error
        while (current != null) {
            if (current.message?.contains("exceeds allowable size", ignoreCase = true) == true) {
                return true
            }
            current = current.cause
        }
        return false
    }

    private fun supportsLargeMtu(remotePath: String, cifsContext: CIFSContext): Boolean? {
        return runCatching {
            SmbFile(remotePath, cifsContext).use { remoteFile ->
                remoteFile.connect()
                remoteFile.treeHandle.use { tree ->
                    val method = tree.javaClass.getMethod("hasCapability", Int::class.javaPrimitiveType)
                        .apply { isAccessible = true }
                    method.invoke(tree, SMB2_GLOBAL_CAP_LARGE_MTU) as Boolean
                }
            }
        }.getOrNull()
    }

    private fun deleteRemoteFile(remotePath: String, cifsContext: CIFSContext) {
        runCatching {
            SmbFile(remotePath, cifsContext).use { remoteFile ->
                if (remoteFile.exists()) remoteFile.delete()
            }
        }
    }

    private fun negotiatedProtocol(
        remotePath: String,
        cifsContext: CIFSContext,
        compatibilityMode: Boolean,
    ): String {
        val dialect = runCatching {
            SmbFile(remotePath, cifsContext).use { remoteFile ->
                remoteFile.connect()
                remoteFile.treeHandle.use { tree ->
                    val sessionMethod = tree.javaClass.getMethod("getSession").apply {
                        isAccessible = true
                    }
                    val session = sessionMethod.invoke(tree)
                    val transportMethod = session.javaClass.getMethod("getTransport").apply {
                        isAccessible = true
                    }
                    val transport = transportMethod.invoke(session)
                    val negotiateMethod = transport.javaClass
                        .getDeclaredMethod("getNegotiateResponse")
                        .apply { isAccessible = true }
                    val response = negotiateMethod.invoke(transport)
                    response.javaClass.getMethod("getSelectedDialect").invoke(response)
                        as? DialectVersion
                }
            }
        }.getOrNull()
        val version = when (dialect) {
            DialectVersion.SMB202 -> "SMB 2.0.2"
            DialectVersion.SMB210 -> "SMB 2.1"
            DialectVersion.SMB300 -> "SMB 3.0"
            DialectVersion.SMB302 -> "SMB 3.0.2"
            DialectVersion.SMB311 -> "SMB 3.1.1"
            DialectVersion.SMB1 -> "SMB 1"
            null -> "SMB 2/3"
        }
        return if (compatibilityMode) {
            "$version · $COMPAT_PARALLEL_UPLOAD_WORKERS 连接 × 64KB"
        } else {
            "$version · 高速模式"
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
        private const val SMB_COMPAT_TRANSACTION_WINDOW = 64 * 1024
        private const val COMPAT_PARALLEL_UPLOAD_WORKERS = 24
        private const val COMPAT_PARALLEL_UPLOAD_MIN_RANGE = 4L * 1024 * 1024
        private const val COMPAT_PARALLEL_UPLOAD_BUFFER_SIZE = 512 * 1024
        private const val PROGRESS_INTERVAL_NANOS = 200L * 1_000_000
        private const val SMB2_GLOBAL_CAP_LARGE_MTU = 0x00000004
    }

    private class UploadProgressReporter(
        private val totalBytes: Long,
        private val protocol: String,
        private val onProgress: (Long, Long, Double, String) -> Unit,
    ) {
        private val uploadedBytes = AtomicLong(0L)
        private val lastReportAt = AtomicLong(0L)
        private var speedSampleAt = System.nanoTime()
        private var speedSampleBytes = 0L
        private var smoothedBytesPerSecond = 0.0

        fun start() = onProgress(0L, totalBytes, 0.0, protocol)

        @Synchronized
        fun beginTransfer() {
            speedSampleAt = System.nanoTime()
            speedSampleBytes = uploadedBytes.get()
            smoothedBytesPerSecond = 0.0
            lastReportAt.set(speedSampleAt)
        }

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

        @Synchronized
        private fun emit(uploaded: Long, now: Long) {
            val elapsedNanos = (now - speedSampleAt).coerceAtLeast(1L)
            val transferred = uploaded - speedSampleBytes
            if (transferred > 0L) {
                val currentRate = transferred * 1_000_000_000.0 / elapsedNanos
                smoothedBytesPerSecond = if (smoothedBytesPerSecond <= 0.0) {
                    currentRate
                } else {
                    currentRate * 0.45 + smoothedBytesPerSecond * 0.55
                }
                speedSampleAt = now
                speedSampleBytes = uploaded
            }
            onProgress(uploaded, totalBytes, smoothedBytesPerSecond, protocol)
        }
    }
}
