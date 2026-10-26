package dev.androfest.android.features.device

import android.Manifest
import android.content.Context
import android.content.pm.PackageManager
import android.net.Uri
import android.os.Environment
import android.provider.CallLog
import android.provider.ContactsContract.CommonDataKinds.Phone
import android.webkit.MimeTypeMap
import dev.androfest.android.features.files.FileTransferManager
import dev.androfest.android.features.files.SelectedFile
import dev.twinvia.protocol.*

/** Called on the connection's IO dispatcher. Nothing is logged or persisted. */
class PhoneDataProvider(private val context: Context, private val files: FileTransferManager) {
    companion object {
        val actions =
            setOf(
                DeviceAction.CONTACTS_LIST,
                DeviceAction.CALLS_LIST,
                DeviceAction.FILES_LIST,
                DeviceAction.FILES_DOWNLOAD,
            )
    }

    private fun permission(name: String, message: String) {
        check(context.checkSelfPermission(name) == PackageManager.PERMISSION_GRANTED) { message }
    }

    private fun clip(value: String?, limit: Int): String {
        val text = (value ?: "").take(limit)
        return if (text.lastOrNull()?.isHighSurrogate() == true) text.dropLast(1) else text
    }

    private fun pattern(query: String) =
        "%" + query.replace("\\", "\\\\").replace("%", "\\%").replace("_", "\\_") + "%"

    fun execute(id: String, command: DeviceCommand): CommandResult {
        command.validate()
        val query = requireNotNull(command.browse)
        val page =
            when (command.action) {
                DeviceAction.CONTACTS_LIST -> contacts(query)
                DeviceAction.CALLS_LIST -> calls(query)
                DeviceAction.FILES_LIST -> storage().list(query)
                DeviceAction.FILES_DOWNLOAD -> {
                    val file = storage().resolve(requireNotNull(query.path))
                    require(file.isFile && file.canRead()) { "The file cannot be read." }
                    require(file.length() <= FileChunk.MAX_FILE_BYTES) {
                        "The file exceeds 2 GiB."
                    }
                    check(!files.status.value.busy) { "Finish the current file transfer first." }
                    val mime =
                        MimeTypeMap.getSingleton()
                            .getMimeTypeFromExtension(file.extension.lowercase())
                            ?: "application/octet-stream"
                    // A file URI stays in this app; only the existing encrypted byte stream leaves
                    // the phone.
                    files.sendFile(SelectedFile(Uri.fromFile(file), file.name, file.length(), mime))
                    return CommandResult(
                        id,
                        true,
                        "Preparing the file; accept the incoming transfer on your Mac.",
                    )
                }
                else -> error("Unsupported phone query.")
            }
        page.validate()
        return CommandResult(
            id,
            true,
            "${page.total} records · ${when (page.kind) { PhoneDataset.CONTACTS -> "Contacts"
 PhoneDataset.CALLS -> "Call history"
 PhoneDataset.FILES -> "Folder" }}",
            page,
        )
    }

    private fun storage(): SharedStorage {
        check(Environment.isExternalStorageManager()) {
            "Allow All files access in phone Settings → Phone data."
        }
        return SharedStorage(Environment.getExternalStorageDirectory())
    }

    private fun contacts(query: PhoneQuery): PhonePage {
        permission(
            Manifest.permission.READ_CONTACTS,
            "Allow contacts in phone Settings → Phone data.",
        )
        val selection =
            if (query.query.isEmpty()) null
            else "(${Phone.DISPLAY_NAME} LIKE ? ESCAPE '\\' OR ${Phone.NUMBER} LIKE ? ESCAPE '\\')"
        val args = selection?.let { arrayOf(pattern(query.query), pattern(query.query)) }
        val list = mutableListOf<PhoneContact>()
        val total =
            context.contentResolver
                .query(
                    Phone.CONTENT_URI,
                    arrayOf(Phone._ID, Phone.DISPLAY_NAME, Phone.NUMBER),
                    selection,
                    args,
                    "${Phone.DISPLAY_NAME} COLLATE LOCALIZED ASC, ${Phone._ID} ASC",
                )
                ?.use { cursor ->
                    cursor.moveToPosition(query.offset - 1)
                    while (list.size < 50 && cursor.moveToNext()) {
                        list +=
                            PhoneContact(
                                cursor.getLong(0).toString(),
                                clip(cursor.getString(1), 256),
                                clip(cursor.getString(2), 128),
                            )
                    }
                    cursor.count.coerceAtMost(1_000_000)
                } ?: error("The contacts provider did not respond.")
        return PhonePage(
            PhoneDataset.CONTACTS,
            contacts = list,
            total = total,
            nextOffset = (query.offset + list.size).takeIf { list.isNotEmpty() && it < total },
        )
    }

    private fun calls(query: PhoneQuery): PhonePage {
        permission(
            Manifest.permission.READ_CALL_LOG,
            "Allow call history in phone Settings → Phone data.",
        )
        val selection =
            if (query.query.isEmpty()) null
            else
                "(${CallLog.Calls.CACHED_NAME} LIKE ? ESCAPE '\\' OR ${CallLog.Calls.NUMBER} LIKE ? ESCAPE '\\')"
        val args = selection?.let { arrayOf(pattern(query.query), pattern(query.query)) }
        val list = mutableListOf<PhoneCall>()
        val total =
            context.contentResolver
                .query(
                    CallLog.Calls.CONTENT_URI,
                    arrayOf(
                        CallLog.Calls._ID,
                        CallLog.Calls.CACHED_NAME,
                        CallLog.Calls.NUMBER,
                        CallLog.Calls.DATE,
                        CallLog.Calls.DURATION,
                        CallLog.Calls.TYPE,
                    ),
                    selection,
                    args,
                    "${CallLog.Calls.DATE} DESC, ${CallLog.Calls._ID} DESC",
                )
                ?.use { cursor ->
                    cursor.moveToPosition(query.offset - 1)
                    while (list.size < 50 && cursor.moveToNext()) {
                        list +=
                            PhoneCall(
                                cursor.getLong(0).toString(),
                                clip(cursor.getString(1), 256),
                                clip(cursor.getString(2), 128),
                                cursor.getLong(3).coerceAtLeast(1),
                                cursor.getLong(4).coerceAtLeast(0),
                                cursor.getInt(5).coerceIn(0, 20),
                            )
                    }
                    cursor.count.coerceAtMost(1_000_000)
                } ?: error("The call history provider did not respond.")
        return PhonePage(
            PhoneDataset.CALLS,
            calls = list,
            total = total,
            nextOffset = (query.offset + list.size).takeIf { list.isNotEmpty() && it < total },
        )
    }
}
