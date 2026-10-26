package dev.androfest.android.features.dashboard

import android.Manifest
import android.content.Intent
import android.content.pm.PackageManager
import android.net.Uri
import android.os.Environment
import android.provider.Settings
import androidx.activity.compose.rememberLauncherForActivityResult
import androidx.activity.result.contract.ActivityResultContracts
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.unit.dp
import androidx.lifecycle.Lifecycle
import androidx.lifecycle.LifecycleEventObserver
import androidx.lifecycle.compose.LocalLifecycleOwner

@Composable
fun PhoneAccessCard() {
    val context = LocalContext.current
    val lifecycle = LocalLifecycleOwner.current.lifecycle
    var revision by remember { mutableIntStateOf(0) }
    val permissions =
        rememberLauncherForActivityResult(ActivityResultContracts.RequestMultiplePermissions()) {
            revision++
        }
    DisposableEffect(lifecycle) {
        val observer = LifecycleEventObserver { _, event ->
            if (event == Lifecycle.Event.ON_RESUME) revision++
        }
        lifecycle.addObserver(observer)
        onDispose { lifecycle.removeObserver(observer) }
    }
    val contacts =
        remember(revision) {
            context.checkSelfPermission(Manifest.permission.READ_CONTACTS) ==
                PackageManager.PERMISSION_GRANTED
        }
    val calls =
        remember(revision) {
            context.checkSelfPermission(Manifest.permission.READ_CALL_LOG) ==
                PackageManager.PERMISSION_GRANTED
        }
    val callAccess =
        remember(revision) {
            listOf(Manifest.permission.READ_PHONE_STATE, Manifest.permission.ANSWER_PHONE_CALLS)
                .all {
                    context.checkSelfPermission(it) == PackageManager.PERMISSION_GRANTED
                }
        }
    val files = remember(revision) { Environment.isExternalStorageManager() }
    Card(
        shape = RoundedCornerShape(24.dp),
        colors = CardDefaults.cardColors(containerColor = MaterialTheme.colorScheme.surface),
    ) {
        Column(
            Modifier.fillMaxWidth().padding(20.dp),
            verticalArrangement = Arrangement.spacedBy(12.dp),
        ) {
            Text(
                "Phone data",
                style = MaterialTheme.typography.titleMedium,
                color = MaterialTheme.colorScheme.primary,
            )
            Text("View contacts, call history, and shared-storage folders on your paired Mac.")
            Text(
                "Contacts: ${if (contacts) "Allowed" else "Permission required"} · Call history: ${if (calls) "Allowed" else "Permission required"}"
            )
            OutlinedButton(
                onClick = {
                    permissions.launch(
                        arrayOf(
                            Manifest.permission.READ_CONTACTS,
                            Manifest.permission.READ_CALL_LOG,
                        )
                    )
                },
                enabled = !contacts || !calls,
            ) {
                Text("Contacts and call history permission")
            }
            Text(
                "Call notifications and answer on Mac: ${if (callAccess) "Allowed" else "Permission required"}"
            )
            OutlinedButton(
                onClick = {
                    permissions.launch(
                        arrayOf(
                            Manifest.permission.READ_PHONE_STATE,
                            Manifest.permission.ANSWER_PHONE_CALLS,
                        )
                    )
                },
                enabled = !callAccess,
            ) {
                Text("Call handoff permissions")
            }
            Text("Files: ${if (files) "All files access enabled" else "All files access required"}")
            OutlinedButton(
                onClick = {
                    context.startActivity(
                        Intent(
                            Settings.ACTION_MANAGE_APP_ALL_FILES_ACCESS_PERMISSION,
                            Uri.parse("package:${context.packageName}"),
                        )
                    )
                }
            ) {
                Text("Configure All files access")
            }
            Text(
                "Private app data is inaccessible. This feature does not edit contacts or call history.",
                style = MaterialTheme.typography.bodySmall,
                color = MaterialTheme.colorScheme.onSurfaceVariant,
            )
        }
    }
}
