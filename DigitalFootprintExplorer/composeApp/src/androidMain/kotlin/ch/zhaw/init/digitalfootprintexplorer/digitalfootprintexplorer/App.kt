package ch.zhaw.init.digitalfootprintexplorer.digitalfootprintexplorer

import android.os.Build
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
import ch.zhaw.init.digitalfootprintexplorer.digitalfootprintexplorer.model.GardenState
import ch.zhaw.init.digitalfootprintexplorer.digitalfootprintexplorer.model.output.EmissionResult
import ch.zhaw.init.digitalfootprintexplorer.digitalfootprintexplorer.ui.theme.DFETheme
import ch.zhaw.init.digitalfootprintexplorer.digitalfootprintexplorer.widget.GardenWidget
import ch.zhaw.init.digitalfootprintexplorer.digitalfootprintexplorer.widget.GardenWidgetReceiver
import ch.zhaw.init.digitalfootprintexplorer.digitalfootprintexplorer.widget.WidgetOnboardingSheet
import ch.zhaw.init.digitalfootprintexplorer.digitalfootprintexplorer.worker.DailyFootprintWorker
import ch.zhaw.init.digitalfootprintexplorer.digitalfootprintexplorer.worker.DemoCalculator
import ch.zhaw.init.digitalfootprintexplorer.digitalfootprintexplorer.worker.KEY_DEBUG_SUMMARY
import ch.zhaw.init.digitalfootprintexplorer.digitalfootprintexplorer.worker.TAG_DEBUG_RUN
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
        // Persisted in SharedPreferences so the state survives activity restarts
        // (e.g. when the app is opened via a widget click).
        val demoPrefs = remember { context.getSharedPreferences("demo_prefs", Context.MODE_PRIVATE) }
        var demoActive      by remember { mutableStateOf(demoPrefs.getBoolean("demo_active", false)) }
        var demoResult      by remember { mutableStateOf<EmissionResult?>(null) }
        var demoGardenState by remember { mutableStateOf<String?>(null) }
        var demoRefreshing  by remember { mutableStateOf(false) }

        // When demo is toggled ON: capture baseline and sync widget.
        // When toggled OFF: clear persisted flag.
        LaunchedEffect(demoActive) {
            demoPrefs.edit().putBoolean("demo_active", demoActive).apply()
            if (demoActive) {
                DemoCalculator.resetBaseline(context)
                demoResult      = null
                demoGardenState = null
                // Reset widget to STABLE so it matches the "no result yet" state
                // in the app and the two displays stay in sync from the start.
                GardenWidget.updateState(context, GardenState.STABLE)
            }
        }

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
                            else            "Echtzeit-Messung seit letztem Reset",
                            style = MaterialTheme.typography.bodySmall
                        )
                    }
                    Switch(checked = demoActive, onCheckedChange = { demoActive = it })
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
                                    val (result, state) = DemoCalculator.calculate(context)
                                    GardenWidget.updateState(context, state)
                                    demoResult      = result
                                    demoGardenState = state.name
                                } catch (_: Exception) { }
                                demoRefreshing = false
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

                    // Result summary
                    demoResult?.let { result ->
                        Text(
                            text       = buildDemoSummary(result, demoGardenState ?: ""),
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
                Text("[DEBUG] Run footprint worker now")
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

// ── Helpers ───────────────────────────────────────────────────────────────────

private fun buildDemoSummary(result: EmissionResult, state: String): String {
    fun f(v: Double) = "%.6f".format(v)
    return """
app    : ${f(result.ghgAppUsage   * 1000)} gCO₂e
display: ${f(result.ghgDisplay    * 1000)} gCO₂e
bg     : ${f(result.ghgBackground * 1000)} gCO₂e
total  : ${f(result.ghgTotal      * 1000)} gCO₂e
state  : $state
    """.trimIndent()
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
