package dev.androfest.protocol

import kotlinx.serialization.Serializable

@Serializable
enum class PhoneDataset {
    @kotlinx.serialization.SerialName("contacts") CONTACTS,
    @kotlinx.serialization.SerialName("calls") CALLS,
    @kotlinx.serialization.SerialName("files") FILES,
}

@Serializable
data class PhoneQuery(val query: String = "", val offset: Int = 0, val path: String? = null) {
    fun validate() {
        require(query.length <= 100 && offset in 0..1_000_000)
        require(path == null || validPhonePath(path))
    }
}

fun validPhonePath(path: String): Boolean =
    path.length <= 1024 &&
        !path.startsWith('/') &&
        !path.contains('\u0000') &&
        path.split('/').none { it == ".." || it == "." }

@Serializable data class PhoneContact(val id: String, val name: String, val number: String)

@Serializable
data class PhoneCall(
    val id: String,
    val name: String,
    val number: String,
    val timestamp: Long,
    val duration: Long,
    val type: Int,
)

@Serializable
data class PhoneFile(
    val path: String,
    val name: String,
    val directory: Boolean,
    val size: Long,
    val modified: Long,
)

@Serializable
data class PhonePage(
    val kind: PhoneDataset,
    val contacts: List<PhoneContact> = emptyList(),
    val calls: List<PhoneCall> = emptyList(),
    val files: List<PhoneFile> = emptyList(),
    val nextOffset: Int? = null,
    val total: Int = 0,
    val path: String? = null,
) {
    fun validate() {
        require(total in 0..1_000_000 && (nextOffset == null || nextOffset in 1..1_000_000))
        require(contacts.size <= 50 && calls.size <= 50 && files.size <= 50)
        require(kind == PhoneDataset.CONTACTS || contacts.isEmpty())
        require(kind == PhoneDataset.CALLS || calls.isEmpty())
        require(kind == PhoneDataset.FILES || (files.isEmpty() && path == null))
        require(path == null || validPhonePath(path))
        contacts.forEach {
            require(it.id.length in 1..128 && it.name.length <= 256 && it.number.length <= 128)
        }
        calls.forEach {
            require(
                it.id.length in 1..128 &&
                    it.name.length <= 256 &&
                    it.number.length <= 128 &&
                    it.timestamp in 1..9_007_199_254_740_991L &&
                    it.duration in 0..9_007_199_254_740_991L &&
                    it.type in 0..20
            )
        }
        files.forEach {
            require(
                it.path.isNotEmpty() &&
                    validPhonePath(it.path) &&
                    it.name.isNotEmpty() &&
                    it.name.length <= 256 &&
                    it.size in 0..9_007_199_254_740_991L &&
                    it.modified in 0..9_007_199_254_740_991L
            )
        }
        require(
            contacts.map { it.id }.distinct().size == contacts.size &&
                calls.map { it.id }.distinct().size == calls.size &&
                files.map { it.path }.distinct().size == files.size
        )
    }
}
