package dev.androfest.android.features.dashboard

import android.app.Application
import android.content.Intent
import android.net.Uri
import androidx.lifecycle.AndroidViewModel
import androidx.lifecycle.viewModelScope
import dev.androfest.android.AndrofestApplication
import dev.androfest.android.features.files.FileSelection
import dev.androfest.android.features.files.SelectedFile
import dev.androfest.protocol.MessageType
import dev.androfest.protocol.WireCodec
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext

class DashboardViewModel(application: Application) : AndroidViewModel(application) {
    private val app = application as AndrofestApplication
    val identity = app.deviceIdentity
    val notifications = app.notifications
    val bridge = app.bridge
    private val _sharedText = MutableStateFlow("")
    val sharedText = _sharedText.asStateFlow()

    fun receiveSharedText(text: String) {
        if (text.length <= 16_384) _sharedText.value = text
        else showNotice("Text limit: 16,384 UTF-16 units.")
    }

    fun editSharedText(text: String) {
        receiveSharedText(text)
    }

    private val _files = MutableStateFlow<List<SelectedFile>>(emptyList())
    val files = _files.asStateFlow()
    private val _notice = MutableStateFlow<String?>(null)
    val notice = _notice.asStateFlow()

    fun selectFiles(uris: List<Uri>, persist: Boolean) {
        viewModelScope.launch {
            val results =
                withContext(Dispatchers.IO) {
                    uris.take(30).map { uri ->
                        runCatching {
                            if (persist)
                                runCatching {
                                    app.contentResolver.takePersistableUriPermission(
                                        uri,
                                        Intent.FLAG_GRANT_READ_URI_PERMISSION,
                                    )
                                }
                            FileSelection.inspect(app, uri)
                        }
                    }
                }
            _files.value =
                (_files.value + results.mapNotNull { it.getOrNull() })
                    .distinctBy { it.uri }
                    .take(30)
            if (results.any { it.isFailure })
                _notice.value =
                    "Some files could not be read. Select them again using the file picker."
        }
    }

    fun clearFiles() {
        _files.value = emptyList()
    }

    fun sendText(text: String) {
        _notice.value =
            runCatching {
                    bridge.sendText(text)
                    "Text queued for Mac."
                }
                .getOrElse { it.message ?: "Could not send text." }
    }

    fun pair(link: String) {
        viewModelScope.launch {
            runCatching { withContext(Dispatchers.IO) { bridge.pair(link) } }
                .onFailure { _notice.value = it.message ?: "Could not read the pairing code." }
        }
    }

    fun showNotice(message: String) {
        _notice.value = message
    }

    fun checkProtocol() {
        _notice.value =
            runCatching {
                    val envelope =
                        WireCodec.message(MessageType.DEVICE_HELLO, identity.id, identity.hello())
                    check(WireCodec.decode(WireCodec.encode(envelope)) == envelope)
                    "Local protocol validation passed."
                }
                .getOrElse { "Protocol validation failed." }
    }
}
