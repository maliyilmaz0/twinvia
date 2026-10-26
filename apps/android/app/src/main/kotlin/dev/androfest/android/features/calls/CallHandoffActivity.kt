package dev.androfest.android.features.calls

import android.os.Bundle
import androidx.activity.ComponentActivity
import androidx.activity.compose.setContent
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.verticalScroll
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.ui.Modifier
import androidx.compose.ui.unit.dp
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import dev.androfest.android.AndrofestApplication

/** Opened by a real notification tap; no overlay or background activity launch. */
class CallHandoffActivity : ComponentActivity() {
    override fun onNewIntent(intent: android.content.Intent) {
        super.onNewIntent(intent)
        setIntent(intent)
        recreate()
    }

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        val handoff = (application as AndrofestApplication).bridge.handoff
        val token = intent.getStringExtra("callToken")
        setContent {
            val call by handoff.state.collectAsStateWithLifecycle()
            var error by remember { mutableStateOf<String?>(null) }
            val current = call.token == token && token != null && call.state != "idle"
            val colors =
                if (androidx.compose.foundation.isSystemInDarkTheme()) darkColorScheme()
                else lightColorScheme()
            MaterialTheme(colorScheme = colors) {
                Surface(Modifier.fillMaxSize()) {
                    Column(
                        Modifier.safeDrawingPadding()
                            .verticalScroll(rememberScrollState())
                            .padding(24.dp),
                        verticalArrangement = Arrangement.spacedBy(20.dp),
                    ) {
                        Text("Twinvia · Call", style = MaterialTheme.typography.labelLarge)
                        Text(
                            if (current) "Continue call on Mac" else "This call has ended",
                            style = MaterialTheme.typography.headlineMedium,
                        )
                        if (current) {
                            Text(
                                if (call.state == "ringing")
                                    "After answering on the phone, audio handoff requires a supported Mac audio path."
                                else
                                    "Handoff requires a supported audio path. Calls are not recorded.",
                                style = MaterialTheme.typography.bodyLarge,
                            )
                            Button(
                                onClick = {
                                    runCatching {
                                            handoff.approve(token)
                                            finish()
                                        }
                                        .onFailure { error = it.message }
                                },
                                modifier = Modifier.fillMaxWidth().heightIn(min = 52.dp),
                            ) {
                                Text("Transfer to Mac")
                            }
                            OutlinedButton(
                                onClick = {
                                    runCatching {
                                            handoff.decline(token)
                                            finish()
                                        }
                                        .onFailure { error = it.message }
                                },
                                modifier = Modifier.fillMaxWidth().heightIn(min = 52.dp),
                            ) {
                                Text("Stay on phone")
                            }
                        } else Button(onClick = { finish() }) { Text("Close") }
                        error?.let { Text(it, color = MaterialTheme.colorScheme.error) }
                    }
                }
            }
        }
    }
}
