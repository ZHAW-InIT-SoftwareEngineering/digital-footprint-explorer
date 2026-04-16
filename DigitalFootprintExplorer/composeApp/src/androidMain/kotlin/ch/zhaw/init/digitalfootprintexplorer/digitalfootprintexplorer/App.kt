package ch.zhaw.init.digitalfootprintexplorer.digitalfootprintexplorer

import android.os.Build
import android.util.Log
import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.safeContentPadding
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.verticalScroll
import androidx.compose.material3.Button
import androidx.compose.material3.ButtonDefaults
import androidx.compose.material3.Card
import androidx.compose.material3.CardDefaults
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Switch
import androidx.compose.material3.Text
import androidx.compose.runtime.*
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.tooling.preview.Preview
import androidx.compose.ui.unit.DpSize
import androidx.compose.ui.unit.dp
import androidx.glance.appwidget.GlanceAppWidgetManager
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import androidx.work.OneTimeWorkRequestBuilder
import androidx.work.WorkInfo
import androidx.work.WorkManager
import ch.zhaw.init.digitalfootprintexplorer.digitalfootprintexplorer.ui.theme.DFETheme
import ch.zhaw.init.digitalfootprintexplorer.digitalfootprintexplorer.widget.GardenWidget
import ch.zhaw.init.digitalfootprintexplorer.digitalfootprintexplorer.widget.GardenWidgetReceiver
import ch.zhaw.init.digitalfootprintexplorer.digitalfootprintexplorer.widget.WidgetOnboardingSheet
import ch.zhaw.init.digitalfootprintexplorer.digitalfootprintexplorer.worker.DailyFootprintWorker
import ch.zhaw.init.digitalfootprintexplorer.digitalfootprintexplorer.worker.DemoRepository
import ch.zhaw.init.digitalfootprintexplorer.digitalfootprintexplorer.worker.KEY_DEBUG_SUMMARY
import ch.zhaw.init.digitalfootprintexplorer.digitalfootprintexplorer.worker.TAG_DEBUG_RUN
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.flow.flowOf
import kotlinx.coroutines.launch
import java.util.UUID

@Composable
@Preview
fun App() {
    DFETheme {
        val context = LocalContext.current
        val scope   = rememberCoroutineScope()
        var showOnboarding by remember { mutableStateOf(false) }

        LaunchedEffect(Unit) {
            val installedIds = GlanceAppWidgetManager(context).getGlanceIds(GardenWidget::class.java)
            showOnboarding = installedIds.isEmpty()
        }

        if (showOnboarding) {
            WidgetOnboardingSheet(
                onDismiss = { showOnboarding = false },
                onPin = {
                    scope.launch {
                        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                            GlanceAppWidgetManager(context).requestPinGlanceAppWidget(
                                receiver     = GardenWidgetReceiver::class.java,
                                preview      = GardenWidget(),
                                previewState = DpSize(245.dp, 115.dp)
                            )
                        }
                        showOnboarding = false
                    }
                }
            )
        }

        // ── Demo mode state ───────────────────────────────────────────────────
        // DemoRepository owns all SharedPreferences access and DemoCalculator calls.
        // State is persisted so it survives activity restarts (e.g. widget click → app open).
        val repo            = remember { DemoRepository(context) }
        var demoActive      by remember { mutableStateOf(repo.wasActiveOnStart) }
        var demoGardenState by remember { mutableStateOf(repo.loadGardenState()) }
        var demoSummaryText by remember { mutableStateOf(repo.loadSummary()) }
        var demoRefreshing  by remember { mutableStateOf(false) }

        // ── Daily debug job state ─────────────────────────────────────────────
        var currentJobId by remember { mutableStateOf<UUID?>(null) }
        val currentWorkInfo by remember(currentJobId) {
            currentJobId?.let { id ->
                WorkManager.getInstance(context).getWorkInfoByIdFlow(id)
            } ?: flowOf(null)
        }.collectAsStateWithLifecycle(null)

        Column(
            modifier = Modifier
                .background(MaterialTheme.colorScheme.background)
                .safeContentPadding()
                .fillMaxSize()
                .verticalScroll(rememberScrollState()),
            horizontalAlignment = Alignment.CenterHorizontally,
        ) {

            // ── Demo mode card ────────────────────────────────────────────────
            Card(
                modifier = Modifier
                    .fillMaxWidth()
                    .padding(horizontal = 16.dp, vertical = 12.dp)
            ) {
                // Toggle row
                Row(
                    modifier = Modifier
                        .fillMaxWidth()
                        .padding(horizontal = 16.dp, vertical = 12.dp),
                    verticalAlignment = Alignment.CenterVertically
                ) {
                    Column(modifier = Modifier.weight(1f)) {
                        Text("Demo-Modus", style = MaterialTheme.typography.titleMedium)
                        Text(
                            if (demoActive) "Aktiv — Baseline gesetzt"
                            else            "Demo-Modus inaktiv",
                            style = MaterialTheme.typography.bodySmall
                        )
                    }
                    Switch(
                        checked = demoActive,
                        onCheckedChange = { enabled ->
                            demoActive = enabled
                            demoGardenState = null
                            demoSummaryText = null
                            if (enabled) repo.activate() else repo.deactivate()
                        }
                    )
                }

                if (demoActive) {
                    // Garden state label
                    demoGardenState?.let { state ->
                        Text(
                            text     = "🌱 Gartenzustand: $state",
                            modifier = Modifier.padding(start = 16.dp, bottom = 8.dp),
                            style    = MaterialTheme.typography.bodyMedium
                        )
                    }

                    // Refresh button
                    Button(
                        modifier = Modifier.padding(start = 16.dp, bottom = 8.dp),
                        enabled  = !demoRefreshing,
                        onClick  = {
                            scope.launch {
                                demoRefreshing = true
                                try {
                                    val (result, state) = repo.refresh()
                                    demoGardenState = state.name
                                    demoSummaryText = repo.buildSummary(result, state.name)
                                } catch (e: CancellationException) {
                                    throw e
                                } catch (e: Exception) {
                                    Log.e("DFE_Demo", "Refresh failed", e)
                                } finally {
                                    demoRefreshing = false
                                }
                            }
                        }
                    ) {
                        if (demoRefreshing) {
                            CircularProgressIndicator(
                                modifier    = Modifier.padding(end = 8.dp),
                                strokeWidth = 2.dp,
                                color       = MaterialTheme.colorScheme.onPrimary
                            )
                        }
                        Text("Gartenzustand aktualisieren")
                    }

                    // Result summary (persisted — visible even after app restart)
                    demoSummaryText?.let { summary ->
                        Text(
                            text       = summary,
                            modifier   = Modifier.padding(start = 16.dp, end = 16.dp, bottom = 12.dp),
                            style      = MaterialTheme.typography.bodySmall,
                            fontFamily = androidx.compose.ui.text.font.FontFamily.Monospace
                        )
                    }
                }
            }

            // ── Daily worker debug button ─────────────────────────────────────
            Button(
                modifier = Modifier.padding(top = 8.dp),
                colors   = ButtonDefaults.buttonColors(
                    containerColor = MaterialTheme.colorScheme.secondary
                ),
                onClick = {
                    val request = OneTimeWorkRequestBuilder<DailyFootprintWorker>()
                        .addTag(TAG_DEBUG_RUN)
                        .build()
                    WorkManager.getInstance(context).enqueue(request)
                    currentJobId = request.id
                }
            ) {
                Text("[DEBUG] footprint vergangener Tag")
            }

            when (currentWorkInfo?.state) {
                WorkInfo.State.RUNNING,
                WorkInfo.State.ENQUEUED -> {
                    CircularProgressIndicator(modifier = Modifier.padding(16.dp))
                    Text("Worker running…", style = MaterialTheme.typography.bodySmall)
                }
                WorkInfo.State.SUCCEEDED -> {
                    val summary = currentWorkInfo?.outputData?.getString(KEY_DEBUG_SUMMARY)
                    if (summary != null) DebugResultCard(summary)
                }
                WorkInfo.State.FAILED -> {
                    DebugResultCard("❌ Worker failed — check Logcat tag: DFE_Worker")
                }
                else -> {}
            }
        }
    }
}

@Composable
private fun DebugResultCard(text: String) {
    Card(
        modifier = Modifier
            .fillMaxWidth()
            .padding(16.dp),
        colors = CardDefaults.cardColors(
            containerColor = MaterialTheme.colorScheme.surfaceVariant
        )
    ) {
        Text(
            text       = text,
            modifier   = Modifier.padding(12.dp),
            style      = MaterialTheme.typography.bodySmall,
            fontFamily = androidx.compose.ui.text.font.FontFamily.Monospace
        )
    }
}
