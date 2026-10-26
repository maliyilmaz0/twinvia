package dev.androfest.android.features.files

import android.content.Context
import android.net.Uri
import android.provider.OpenableColumns

data class SelectedFile(val uri: Uri, val name: String, val size: Long?, val mimeType: String)

object FileSelection {
    fun inspect(context: Context, uri: Uri): SelectedFile {
        require(uri.scheme == "content") { "Only selected content files can be used." }
        val resolver = context.contentResolver
        var name = "File"
        var size: Long? = null
        resolver
            .query(
                uri,
                arrayOf(OpenableColumns.DISPLAY_NAME, OpenableColumns.SIZE),
                null,
                null,
                null,
            )
            ?.use {
                if (it.moveToFirst()) {
                    val nameIndex = it.getColumnIndex(OpenableColumns.DISPLAY_NAME)
                    val sizeIndex = it.getColumnIndex(OpenableColumns.SIZE)
                    if (nameIndex >= 0 && !it.isNull(nameIndex)) name = it.getString(nameIndex)
                    if (sizeIndex >= 0 && !it.isNull(sizeIndex))
                        size = it.getLong(sizeIndex).takeIf { value -> value >= 0 }
                }
            }
        return SelectedFile(uri, name, size, resolver.getType(uri) ?: "application/octet-stream")
    }
}
