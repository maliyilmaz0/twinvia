package dev.androfest.android.features.dashboard

import android.content.Intent
import android.os.Build
import android.provider.Settings
import android.text.format.Formatter
import androidx.activity.compose.rememberLauncherForActivityResult
import androidx.activity.result.contract.ActivityResultContracts
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.lazy.rememberLazyListState
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.platform.LocalDensity
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.heading
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.text.font.FontFamily
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.core.app.NotificationManagerCompat
import androidx.lifecycle.Lifecycle
import androidx.lifecycle.LifecycleEventObserver
import androidx.lifecycle.compose.LocalLifecycleOwner
import androidx.lifecycle.compose.collectAsStateWithLifecycle

@Composable
fun DashboardScreen(model: DashboardViewModel, testNotification: () -> Unit, scanMac: () -> Unit) {
    var section by rememberSaveable { mutableIntStateOf(0) }
    var confirmForget by remember { mutableStateOf(false) }
    var showApplications by rememberSaveable { mutableStateOf(false) }
    val deviceScroll = rememberLazyListState()
    val sharingScroll = rememberLazyListState()
    val settingsScroll = rememberLazyListState()
    val context = LocalContext.current
    val lifecycle = LocalLifecycleOwner.current
    var hasAccess by remember { mutableStateOf(false) }
    DisposableEffect(lifecycle) {
        val observer = LifecycleEventObserver { _, event ->
            if (event == Lifecycle.Event.ON_RESUME) {
                hasAccess =
                    context.packageName in
                        NotificationManagerCompat.getEnabledListenerPackages(context)
            }
        }
        lifecycle.lifecycle.addObserver(observer)
        hasAccess =
            context.packageName in NotificationManagerCompat.getEnabledListenerPackages(context)
        onDispose { lifecycle.lifecycle.removeObserver(observer) }
    }
    val events by model.notifications.events.collectAsStateWithLifecycle()
    val capture by model.notifications.captureEnabled.collectAsStateWithLifecycle()
    val hidePersistent by model.notifications.hidePersistent.collectAsStateWithLifecycle()
    val applications by model.notifications.applications.collectAsStateWithLifecycle()
    val excludedPackages by model.notifications.excludedPackages.collectAsStateWithLifecycle()
    val listening by model.notifications.listenerConnected.collectAsStateWithLifecycle()
    val files by model.files.collectAsStateWithLifecycle()
    val notice by model.notice.collectAsStateWithLifecycle()
    val connectionStatus by model.bridge.status.collectAsStateWithLifecycle()
    val connected by model.bridge.connected.collectAsStateWithLifecycle()
    val transportStatus by model.bridge.transportStatus.collectAsStateWithLifecycle()
    val transfer by model.bridge.files.status.collectAsStateWithLifecycle()
    val incomingFile by model.bridge.files.incoming.collectAsStateWithLifecycle()
    val peerName by model.bridge.peerName.collectAsStateWithLifecycle()
    val ringing by model.bridge.features.ringing.collectAsStateWithLifecycle()
    val sharedText by model.sharedText.collectAsStateWithLifecycle()
    val clipboardEnabled by model.bridge.features.clipboard.enabled.collectAsStateWithLifecycle()
    val clipboardStatus by model.bridge.features.clipboard.status.collectAsStateWithLifecycle()
    val hideLocked by model.notifications.hideLocked.collectAsStateWithLifecycle()
    val testReply by model.notifications.testReply.collectAsStateWithLifecycle()
    val picker =
        rememberLauncherForActivityResult(ActivityResultContracts.OpenMultipleDocuments()) {
            model.selectFiles(it, persist = true)
        }

    // Shares and selected files open the sharing tab without changing the connection.
    LaunchedEffect(sharedText, files.size) {
        if (sharedText.isNotEmpty() || files.isNotEmpty()) section = 1
    }
    AndrofestTheme {
        if (confirmForget)
            AlertDialog(
                onDismissRequest = { confirmForget = false },
                title = { Text("Remove pairing?") },
                text = {
                    Text("This removes the Mac pairing. Scan a new QR code to connect again.")
                },
                confirmButton = {
                    TextButton(
                        onClick = {
                            model.bridge.forget()
                            confirmForget = false
                        }
                    ) {
                        Text("Remove pairing")
                    }
                },
                dismissButton = {
                    TextButton(onClick = { confirmForget = false }) { Text("Cancel") }
                },
            )
        incomingFile?.let { offer ->
            AlertDialog(
                onDismissRequest = { model.bridge.files.cancel() },
                title = { Text("Incoming file") },
                text = {
                    Text(
                        "${offer.fileName} · ${Formatter.formatFileSize(context, offer.size)}\nWill be saved in Downloads/Twinvia."
                    )
                },
                confirmButton = {
                    TextButton(onClick = { model.bridge.files.accept() }) { Text("Accept") }
                },
                dismissButton = {
                    TextButton(onClick = { model.bridge.files.cancel() }) { Text("Decline") }
                },
            )
        }
        Scaffold(
            containerColor = MaterialTheme.colorScheme.background,
            bottomBar = {
                NavigationBar(containerColor = MaterialTheme.colorScheme.surface) {
                    listOf("Device", "Sharing", "Settings").forEachIndexed { index, title ->
                        NavigationBarItem(
                            selected = section == index,
                            onClick = { section = index },
                            icon = { NavGlyph(index) },
                            label = { Text(title) },
                        )
                    }
                }
            },
        ) { insets ->
            LazyColumn(
                modifier =
                    Modifier.fillMaxSize()
                        .padding(insets)
                        .wrapContentWidth(Alignment.CenterHorizontally)
                        .widthIn(max = 680.dp)
                        .imePadding(),
                state =
                    when (section) {
                        1 -> sharingScroll
                        2 -> settingsScroll
                        else -> deviceScroll
                    },
                contentPadding = PaddingValues(horizontal = 20.dp, vertical = 24.dp),
                verticalArrangement = Arrangement.spacedBy(16.dp),
            ) {
                item {
                    Row(Modifier.fillMaxWidth(), verticalAlignment = Alignment.CenterVertically) {
                        Text(
                            "androfest",
                            style = MaterialTheme.typography.headlineSmall,
                            fontWeight = FontWeight.Bold,
                            modifier = Modifier.weight(1f),
                        )
                        if (LocalDensity.current.fontScale < 1.3f)
                            Text(
                                "${Build.VERSION.RELEASE} / ANDROID",
                                style = MaterialTheme.typography.labelSmall,
                                fontFamily = FontFamily.Monospace,
                                color = MaterialTheme.colorScheme.onSurfaceVariant,
                            )
                    }
                }
                if (section == 0) {
                    item {
                        ConnectionHero(peerName ?: "Connect your Mac", connected, connectionStatus)
                    }
                    if (peerName == null)
                        item {
                            Button(
                                onClick = scanMac,
                                modifier = Modifier.fillMaxWidth().heightIn(min = 52.dp),
                            ) {
                                Text("Scan Mac QR code")
                            }
                            Text(
                                "Keep Bluetooth enabled and devices nearby. No shared network or internet is needed.",
                                color = MaterialTheme.colorScheme.onSurfaceVariant,
                                style = MaterialTheme.typography.bodyMedium,
                                modifier = Modifier.padding(top = 8.dp),
                            )
                        }
                    item {
                        Panel("Everything together") {
                            StatusLine("This phone", model.identity.name)
                            StatusLine(
                                "Clipboard",
                                if (clipboardEnabled) clipboardStatus else "Sync disabled",
                            )
                            StatusLine(
                                "Notifications",
                                if (hasAccess && listening && capture) "Mac handoff enabled"
                                else "Check setup",
                            )
                            if (!hasAccess || !listening || !capture) {
                                TextButton(onClick = { section = 2 }) {
                                    Text("Configure notifications")
                                }
                            }
                            FilledTonalButton(
                                onClick = { section = 1 },
                                modifier = Modifier.fillMaxWidth(),
                            ) {
                                Text("Enable sharing")
                            }
                        }
                    }
                    if (peerName != null)
                        item {
                            Panel("Connection") {
                                Text(
                                    "Paired Mac: $peerName",
                                    style = MaterialTheme.typography.bodyLarge,
                                )
                                Text(
                                    transportStatus,
                                    color = MaterialTheme.colorScheme.onSurfaceVariant,
                                )
                                if (connected)
                                    TextButton(onClick = model.bridge::sendTest) {
                                        Text("Send test message to Mac")
                                    }
                            }
                        }
                }
                if (section == 2) {
                    item {
                        SectionHeading(
                            "Make it yours.",
                            "Permissions, privacy, and notification preferences.",
                        )
                    }
                    item {
                        Panel("Notifications") {
                            Text(
                                if (hasAccess) "Notification access enabled"
                                else "Notification access required"
                            )
                            Text(
                                if (listening) "Notification listener connected"
                                else "Notification listener disconnected"
                            )
                            OutlinedButton(
                                onClick = {
                                    context.startActivity(
                                        Intent(Settings.ACTION_NOTIFICATION_LISTENER_SETTINGS)
                                    )
                                }
                            ) {
                                Text("Configure notification access")
                            }
                            Row(
                                modifier = Modifier.fillMaxWidth(),
                                horizontalArrangement = Arrangement.SpaceBetween,
                            ) {
                                Text(
                                    "Share notifications with Mac",
                                    modifier = Modifier.weight(1f).padding(end = 12.dp),
                                )
                                Switch(
                                    modifier =
                                        Modifier.semantics {
                                            contentDescription = "Share notifications with Mac"
                                        },
                                    checked = capture,
                                    onCheckedChange = model.notifications::setCaptureEnabled,
                                )
                            }
                            Text(
                                "When enabled, notifications are sent to your paired Mac. The latest 30 events remain in memory and are cleared when disabled.",
                                style = MaterialTheme.typography.bodySmall,
                            )
                            Row(
                                modifier = Modifier.fillMaxWidth(),
                                horizontalArrangement = Arrangement.SpaceBetween,
                            ) {
                                Text(
                                    "Hide persistent and status notifications",
                                    modifier = Modifier.weight(1f).padding(end = 12.dp),
                                )
                                Switch(
                                    modifier =
                                        Modifier.semantics {
                                            contentDescription =
                                                "Hide persistent and status notifications"
                                        },
                                    checked = hidePersistent,
                                    onCheckedChange = model.notifications::setHidePersistent,
                                )
                            }
                            Text(
                                "Charging, step counts, background services, and progress notifications are not sent to Mac.",
                                style = MaterialTheme.typography.bodySmall,
                            )
                            Row(
                                modifier = Modifier.fillMaxWidth(),
                                horizontalArrangement = Arrangement.SpaceBetween,
                            ) {
                                Text(
                                    "Hide content while phone is locked",
                                    modifier = Modifier.weight(1f).padding(end = 12.dp),
                                )
                                Switch(
                                    modifier =
                                        Modifier.semantics {
                                            contentDescription =
                                                "Hide content while phone is locked"
                                        },
                                    checked = hideLocked,
                                    onCheckedChange = model.notifications::setHideLocked,
                                )
                            }
                            Button(onClick = testNotification) { Text("Create test notification") }
                            testReply?.let { Text("Last local test reply: $it") }
                            Text("Captured events: ${events.size}")
                            if (events.isNotEmpty())
                                TextButton(onClick = model.notifications::clear) {
                                    Text("Clear events")
                                }
                        }
                    }
                }
                if (section == 1) {
                    item {
                        SectionHeading(
                            "Copy here.\nContinue there.",
                            "Your clipboard and files, across devices.",
                        )
                    }
                    item {
                        Panel("Universal clipboard") {
                            Row(
                                modifier = Modifier.fillMaxWidth(),
                                horizontalArrangement = Arrangement.SpaceBetween,
                            ) {
                                Text(
                                    "Automatic clipboard sync",
                                    modifier = Modifier.weight(1f).padding(end = 12.dp),
                                )
                                Switch(
                                    modifier =
                                        Modifier.semantics {
                                            contentDescription = "Automatic clipboard sync"
                                        },
                                    checked = clipboardEnabled,
                                    onCheckedChange = model.bridge.features.clipboard::setEnabled,
                                )
                            }
                            Text(clipboardStatus)
                            Text(
                                "Text and links copied on your phone or Mac sync automatically to the other clipboard.",
                                style = MaterialTheme.typography.bodySmall,
                            )
                            if (sharedText.isNotEmpty()) {
                                Button(
                                    onClick = {
                                        model.sendText(sharedText)
                                        model.editSharedText("")
                                    },
                                    enabled = connected,
                                ) {
                                    Text("Send shared text to Mac")
                                }
                            }
                            if (ringing)
                                Button(onClick = { model.bridge.features.stopRinging() }) {
                                    Text("Stop phone ringer")
                                }
                            notice?.let { Text(it) }
                        }
                    }
                }
                if (section == 2 && applications.isNotEmpty())
                    item {
                        Panel("App filter") {
                            TextButton(onClick = { showApplications = !showApplications }) {
                                Text(
                                    if (showApplications) "Hide apps"
                                    else "${applications.size} manage apps"
                                )
                            }
                            if (showApplications) {
                                applications.entries
                                    .sortedBy { it.value }
                                    .forEach { (packageName, name) ->
                                        Row(
                                            modifier = Modifier.fillMaxWidth(),
                                            horizontalArrangement = Arrangement.SpaceBetween,
                                        ) {
                                            Text(
                                                name,
                                                modifier = Modifier.weight(1f).padding(end = 12.dp),
                                            )
                                            Switch(
                                                modifier =
                                                    Modifier.semantics {
                                                        contentDescription =
                                                            "$name share notifications"
                                                    },
                                                checked = packageName !in excludedPackages,
                                                onCheckedChange = {
                                                    model.notifications.setApplicationEnabled(
                                                        packageName,
                                                        it,
                                                    )
                                                },
                                            )
                                        }
                                    }
                            }
                        }
                    }
                if (section == 1) {
                    item {
                        Panel("Files") {
                            Text("Select a file or open Twinvia from another app's share menu.")
                            Button(onClick = { picker.launch(arrayOf("*/*")) }) {
                                Text("Choose file")
                            }
                            if (files.isNotEmpty()) {
                                Text(
                                    "${files.size} files selected · Up to 2 GiB · Recipient approval required"
                                )
                                TextButton(onClick = model::clearFiles) { Text("Clear selection") }
                            }
                            if (transfer.message.isNotEmpty()) {
                                Text(transfer.fileName, style = MaterialTheme.typography.titleSmall)
                                Text(transfer.message)
                                if (transfer.busy) {
                                    LinearProgressIndicator(
                                        progress = {
                                            (transfer.bytes.toDouble() / maxOf(transfer.total, 1))
                                                .toFloat()
                                        },
                                        modifier = Modifier.fillMaxWidth(),
                                    )
                                    Text(
                                        "${Formatter.formatFileSize(context, transfer.bytes)} / ${Formatter.formatFileSize(context, transfer.total)}"
                                    )
                                    TextButton(onClick = { model.bridge.files.cancel() }) {
                                        Text("Cancel transfer")
                                    }
                                }
                                transfer.receivedUri?.let { uri ->
                                    TextButton(
                                        onClick = {
                                            runCatching {
                                                    context.startActivity(
                                                        Intent(Intent.ACTION_VIEW)
                                                            .setDataAndType(
                                                                uri,
                                                                context.contentResolver.getType(uri)
                                                                    ?: "*/*",
                                                            )
                                                            .addFlags(
                                                                Intent
                                                                    .FLAG_GRANT_READ_URI_PERMISSION
                                                            )
                                                    )
                                                }
                                                .onFailure {
                                                    model.showNotice(
                                                        "No application can open this file."
                                                    )
                                                }
                                        }
                                    ) {
                                        Text("Open received file")
                                    }
                                }
                            }
                        }
                    }
                    items(files, key = { it.uri.toString() }) { file ->
                        ListItem(
                            headlineContent = { Text(file.name) },
                            supportingContent = {
                                Text(
                                    file.size?.let { Formatter.formatFileSize(context, it) }
                                        ?: "Size unknown"
                                )
                            },
                            trailingContent = {
                                Button(
                                    onClick = { model.bridge.files.sendFile(file) },
                                    enabled = connected && !transfer.busy,
                                ) {
                                    Text("Send to Mac")
                                }
                            },
                        )
                    }
                }
                if (section == 2) {
                    item { PhoneAccessCard() }
                    item {
                        Panel("Pairing") {
                            Text(peerName ?: "No Mac is paired yet.")
                            Text(
                                transportStatus,
                                color = MaterialTheme.colorScheme.onSurfaceVariant,
                            )
                            if (peerName == null)
                                Button(onClick = scanMac) { Text("Scan Mac QR code") }
                            else
                                TextButton(onClick = { confirmForget = true }) {
                                    Text("Remove pairing")
                                }
                        }
                    }
                    item {
                        Panel("Local controls") {
                            OutlinedButton(onClick = model::checkProtocol) {
                                Text("Validate protocol")
                            }
                            notice?.let { Text(it) }
                        }
                    }
                }
                if (section == 0)
                    notice?.let { message ->
                        item {
                            Panel("Info") { Text(message) }
                        }
                    }
            }
        }
    }
}

@Composable
private fun Panel(title: String, content: @Composable ColumnScope.() -> Unit) {
    Card(
        modifier = Modifier.fillMaxWidth(),
        shape = RoundedCornerShape(24.dp),
        colors = CardDefaults.cardColors(containerColor = MaterialTheme.colorScheme.surface),
    ) {
        Column(Modifier.padding(20.dp), verticalArrangement = Arrangement.spacedBy(10.dp)) {
            Text(
                title,
                style = MaterialTheme.typography.titleMedium,
                fontWeight = FontWeight.Bold,
                color = MaterialTheme.colorScheme.primary,
                modifier = Modifier.semantics { heading() },
            )
            content()
        }
    }
}

@Composable
private fun StatusLine(title: String, value: String) {
    Column(
        verticalArrangement = Arrangement.spacedBy(4.dp),
        modifier = Modifier.padding(vertical = 4.dp),
    ) {
        Text(
            title,
            style = MaterialTheme.typography.labelMedium,
            color = MaterialTheme.colorScheme.onSurfaceVariant,
        )
        Text(value, style = MaterialTheme.typography.bodyLarge)
    }
}
