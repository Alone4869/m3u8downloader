package io.github.alone4869.m3u8downloader

import android.content.ContentUris
import android.content.Context
import android.net.Uri
import android.provider.MediaStore
import java.text.Normalizer

data class LocalDownload(
    val uri: Uri,
    val displayName: String,
    val relativePath: String,
    val size: Long,
    val mimeType: String,
    val addedAt: Long,
)

object LocalDownloads {
    fun resolve(
        context: Context,
        contentUri: String,
        fileName: String,
        expectedSize: Long = 0L,
    ): Uri? {
        contentUri.takeIf { it.isNotBlank() }?.let(Uri::parse)?.let { uri ->
            if (isReadable(context, uri)) return uri
        }
        return find(context, fileName, expectedSize)?.uri
    }

    fun find(context: Context, fileName: String, expectedSize: Long = 0L): LocalDownload? {
        val normalizedName = normalize(fileName)
        return list(context)
            .asSequence()
            .filter { normalize(it.displayName) == normalizedName }
            .sortedWith(
                compareByDescending<LocalDownload> {
                    it.relativePath.contains(APP_FOLDER, ignoreCase = true)
                }.thenByDescending { expectedSize > 0L && it.size == expectedSize }
                    .thenByDescending { it.addedAt },
            )
            .firstOrNull { isReadable(context, it.uri) }
    }

    fun list(context: Context): List<LocalDownload> {
        val result = LinkedHashMap<String, LocalDownload>()
        collections().forEach { collection ->
            runCatching { queryCollection(context, collection) }
                .getOrDefault(emptyList())
                .forEach { item -> result.putIfAbsent(item.uri.toString(), item) }
        }
        return result.values.toList()
    }

    private fun queryCollection(context: Context, collection: Uri): List<LocalDownload> {
        val projection = arrayOf(
            MediaStore.MediaColumns._ID,
            MediaStore.MediaColumns.DISPLAY_NAME,
            MediaStore.MediaColumns.RELATIVE_PATH,
            MediaStore.MediaColumns.SIZE,
            MediaStore.MediaColumns.MIME_TYPE,
            MediaStore.MediaColumns.DATE_ADDED,
        )
        return context.contentResolver.query(
            collection,
            projection,
            null,
            null,
            "${MediaStore.MediaColumns.DATE_ADDED} DESC",
        )?.use { cursor ->
            val idIndex = cursor.getColumnIndexOrThrow(MediaStore.MediaColumns._ID)
            val nameIndex = cursor.getColumnIndexOrThrow(MediaStore.MediaColumns.DISPLAY_NAME)
            val pathIndex = cursor.getColumnIndex(MediaStore.MediaColumns.RELATIVE_PATH)
            val sizeIndex = cursor.getColumnIndex(MediaStore.MediaColumns.SIZE)
            val mimeIndex = cursor.getColumnIndex(MediaStore.MediaColumns.MIME_TYPE)
            val addedIndex = cursor.getColumnIndex(MediaStore.MediaColumns.DATE_ADDED)
            buildList {
                while (cursor.moveToNext()) {
                    val name = cursor.getString(nameIndex).orEmpty()
                    val path = if (pathIndex >= 0) cursor.getString(pathIndex).orEmpty() else ""
                    if (name.isBlank() || !path.contains(APP_FOLDER, ignoreCase = true)) continue
                    add(
                        LocalDownload(
                            uri = ContentUris.withAppendedId(collection, cursor.getLong(idIndex)),
                            displayName = name,
                            relativePath = path,
                            size = if (sizeIndex >= 0) cursor.getLong(sizeIndex) else 0L,
                            mimeType = if (mimeIndex >= 0) cursor.getString(mimeIndex).orEmpty() else "",
                            addedAt = if (addedIndex >= 0) cursor.getLong(addedIndex) else 0L,
                        ),
                    )
                }
            }
        } ?: emptyList()
    }

    private fun collections(): List<Uri> = listOf(
        MediaStore.Downloads.EXTERNAL_CONTENT_URI,
        MediaStore.Video.Media.EXTERNAL_CONTENT_URI,
        MediaStore.Files.getContentUri("external"),
    )

    private fun isReadable(context: Context, uri: Uri): Boolean = runCatching {
        context.contentResolver.openFileDescriptor(uri, "r")?.use { true } ?: false
    }.getOrDefault(false)

    private fun normalize(value: String): String =
        Normalizer.normalize(value.trim(), Normalizer.Form.NFC).lowercase()

    private const val APP_FOLDER = "M3U8 Downloader"
}
