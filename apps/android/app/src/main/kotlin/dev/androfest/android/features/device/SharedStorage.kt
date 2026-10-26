package dev.androfest.android.features.device

import dev.twinvia.protocol.*
import java.io.File

/** All remote paths are relative to one shared-storage root. Never expose arbitrary paths. */
class SharedStorage(root: File) {
    private val root = root.canonicalFile

    fun resolve(path: String): File {
        require(validPhonePath(path)) { "Invalid file path." }
        val result = File(root, path).canonicalFile
        require(result == root || result.path.startsWith(root.path + File.separator)) {
            "Access outside shared storage is not allowed."
        }
        return result
    }

    fun list(query: PhoneQuery): PhonePage {
        query.validate()
        val folder = resolve(query.path ?: "")
        require(folder.isDirectory && folder.canRead()) {
            "Android does not allow access to this folder."
        }
        val entries =
            (folder.listFiles() ?: error("Could not read the folder."))
                .asSequence()
                .filter { it.name.contains(query.query, ignoreCase = true) }
                .filter { it.isDirectory || it.isFile }
                .filter {
                    runCatching { resolve(it.relativeTo(root).invariantSeparatorsPath) }.isSuccess
                }
                .sortedWith(
                    compareBy<File> { !it.isDirectory }
                        .thenBy(String.CASE_INSENSITIVE_ORDER) { it.name }
                        .thenBy { it.name }
                )
                .toList()
        require(entries.size <= 1_000_000)
        val page =
            entries.drop(query.offset).take(50).map {
                PhoneFile(
                    it.relativeTo(root).invariantSeparatorsPath,
                    it.name,
                    it.isDirectory,
                    if (it.isDirectory) 0 else it.length().coerceAtLeast(0),
                    it.lastModified().coerceAtLeast(0),
                )
            }
        return PhonePage(
                PhoneDataset.FILES,
                files = page,
                total = entries.size,
                path = folder.relativeTo(root).invariantSeparatorsPath,
                nextOffset =
                    (query.offset + page.size).takeIf { page.isNotEmpty() && it < entries.size },
            )
            .also { it.validate() }
    }
}
