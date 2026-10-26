package dev.androfest.android.features.device

import dev.twinvia.protocol.PhoneQuery
import java.nio.file.Files
import org.junit.Assert.*
import org.junit.Test

class SharedStorageTest {
    @Test
    fun `cannot escape root with traversal absolute paths or symlinks`() {
        val root = Files.createTempDirectory("androfest-storage-test").toFile()
        val outside = Files.createTempDirectory("androfest-outside-test").toFile()
        try {
            val storage = SharedStorage(root)
            listOf("../secret", "/etc/passwd", "a/../../secret", "a/./file", "bad\u0000path")
                .forEach {
                    assertThrows(IllegalArgumentException::class.java) { storage.resolve(it) }
                }
            Files.createSymbolicLink(root.resolve("escape").toPath(), outside.toPath())
            assertThrows(IllegalArgumentException::class.java) { storage.resolve("escape") }
            assertTrue(storage.list(PhoneQuery()).files.isEmpty())
        } finally {
            root.deleteRecursively()
            outside.deleteRecursively()
        }
    }

    @Test
    fun `list paginates and searches with directories first`() {
        val root = Files.createTempDirectory("androfest-storage-test").toFile()
        try {
            root.resolve("Fotoğraflar").mkdir()
            repeat(61) { root.resolve("file-%03d.txt".format(it)).writeText("fixture") }
            val storage = SharedStorage(root)
            val first = storage.list(PhoneQuery())
            assertEquals("Fotoğraflar", first.files.first().name)
            assertEquals("", first.path)
            assertEquals(62, first.total)
            assertEquals(50, first.nextOffset)
            val second = storage.list(PhoneQuery(offset = first.nextOffset!!))
            assertEquals(12, second.files.size)
            assertNull(second.nextOffset)
            assertTrue(
                first.files
                    .map { it.path }
                    .intersect(second.files.map { it.path }.toSet())
                    .isEmpty()
            )
            assertEquals(1, storage.list(PhoneQuery(query = "FILE-060")).total)
        } finally {
            root.deleteRecursively()
        }
    }
}
