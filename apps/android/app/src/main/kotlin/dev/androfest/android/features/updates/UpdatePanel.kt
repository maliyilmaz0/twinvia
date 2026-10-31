package dev.androfest.android.features.updates

import androidx.compose.foundation.layout.*
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.unit.dp
import androidx.lifecycle.compose.collectAsStateWithLifecycle

@Composable
fun UpdatePanel(updater: AppUpdater) {
    val state by updater.state.collectAsStateWithLifecycle()
    val context = LocalContext.current
    var automatic by remember { mutableStateOf(updater.checkOnLaunch) }
    Column(verticalArrangement = Arrangement.spacedBy(10.dp)) {
        Text("Software updates", style = MaterialTheme.typography.titleMedium)
        Text(state.message)
        if (state.busy) LinearProgressIndicator(modifier = Modifier.fillMaxWidth())
        Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
            OutlinedButton(onClick = updater::check, enabled = !state.busy && !state.installing) {
                Text("Check for updates")
            }
            if (state.version != null && (!state.installing || state.ready))
                Button(
                    onClick = { if (state.ready) updater.install(context) else updater.download() },
                    enabled = !state.busy,
                ) {
                    Text(if (state.ready) "Continue installation" else "Download ${state.version}")
                }
        }
        if (state.installing) {
            OutlinedButton(onClick = updater::cancelInstallation, enabled = !state.busy) {
                Text("Cancel installation")
            }
        }
        Row {
            Checkbox(
                checked = automatic,
                onCheckedChange = {
                    automatic = it
                    updater.checkOnLaunch = it
                },
            )
            Text("Check on app launch")
        }
    }
}
