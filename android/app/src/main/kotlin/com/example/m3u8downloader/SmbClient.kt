package com.example.m3u8downloader

import android.content.Context
import android.net.Uri
import android.provider.MediaStore
import java.io.FileInputStream
import java.net.URLEncoder
import java.util.Properties
import jcifs.CIFSContext
import jcifs.config.PropertyConfiguration
import jcifs.context.BaseContext
import jcifs.smb.NtlmPasswordAuthenticator
import jcifs.smb.SmbFile
import jcifs.smb.SmbFileOutputStream

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
            setProperty("jcifs.smb.client.snd_buf_size", SMB_TRANSPORT_BUFFER.toString())
            setProperty("jcifs.smb.client.rcv_buf_size", SMB_TRANSPORT_BUFFER.toString())
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
                val descriptor = androidContext.contentResolver.openFileDescriptor(source, "r")
                    ?: error("无法读取本地文件：$fileName")
                descriptor.use {
                    FileInputStream(it.fileDescriptor).use { input ->
                        SmbFileOutputStream(remoteFile, false).use { output ->
                            val buffer = ByteArray(UPLOAD_BUFFER_SIZE)
                            var uploadedBytes = 0L
                            val startedAt = System.nanoTime()
                            onProgress(0L, fileSize, 0.0)
                            while (true) {
                                val count = input.read(buffer)
                                if (count < 0) break
                                output.write(buffer, 0, count)
                                uploadedBytes += count
                                val elapsedSeconds =
                                    (System.nanoTime() - startedAt).coerceAtLeast(1L) / 1_000_000_000.0
                                onProgress(uploadedBytes, fileSize, uploadedBytes / elapsedSeconds)
                            }
                        }
                    }
                }
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
        // jcifs-ng otherwise caps SMB2 writes at roughly 64 KiB. A 1 MiB
        // negotiated write keeps a LAN link busy without excessive Android GC.
        private const val SMB_TRANSPORT_BUFFER = 1024 * 1024
        private const val UPLOAD_BUFFER_SIZE = 8 * 1024 * 1024
    }
}
