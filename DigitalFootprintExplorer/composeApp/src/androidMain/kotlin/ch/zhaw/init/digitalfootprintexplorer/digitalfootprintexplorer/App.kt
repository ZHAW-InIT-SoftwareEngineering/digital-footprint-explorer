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
import ch.zhaw.init.digitalfootprintexplorer.digitalfootprintexplorer.ui.theme.DFETheme
import ch.zhaw.init.digitalfootprintexplorer.digitalfootprintexplorer.widget.GardenWidget
import ch.zhaw.init.digitalfootprintexplorer.digitalfootprintexplorer.widget.GardenWidgetReceiver
import ch.zhaw.init.digitalfootprintexplorer.digitalfootprintexplorer.widget.WidgetOnboardingSheet
import ch.zhaw.init.digitalfootprintexplorer.digitalfootprintexplorer.worker.DailyFootprintWorker
import ch.zhaw.init.digitalfootprintexplorer.digitalfootprintexplorer.worker.DemoCalculator
import ch.zhaw.init.digitalfootprintexplorer.digitalfootprintexplorer.worker.KEY_DEBUG_SUMMARY
import ch.zhaw.init.digitalfootprintexplorer.digitalfootprintexplorer.worker.TAG_DEBUG_RUN
import kotlinx.coroutines.delay
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
        var demoActive      by remember { mutableStateOf(false) }
        var demoSummary     by remember { mutableStateOf<String?>(null) }
        var demoGardenState by remember { mutableStateOf<String?>(null) }
        var demoRefreshing  by remember { mutableStateOf(false) }

        // Helper: runs one demo calculation and updates state
        suspend fun runDemoCalculation() {
            demoRefreshing = true
            try {
                val (result, state) = DemoCalculator.calculate(context)
                GardenWidget.updateState(context, state)
                demoGardenState = state.name
                demoSummary     = buildDemoSummary(result, state.name)
            } catch (_: Exception) { /* ignore transient errors */ }
            demoRefreshing = false
        }

        // Coroutine loop: runs every POLL_MS while demo is active
        LaunchedEffect(demoActive) {
            if (!demoActive) {
                demoSummary     = null
                demoGardenState = null
                return@LaunchedEffect
            }
            while (true) {
                runDemoCalculation()
                delay(DemoCalculator.POLL_MS)
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

            // ── Demo mode toggle ──────────────────────────────────────────────
            Card(
                modifier = Modifier
                    .fillMaxWidth()
                    .padding(horizontal = 16.dp, vertical = 12.dp)
            ) {
                Row(
                    modifier = Modifier
                        .fillMaxWidth()
                        .padding(horizontal = 16.dp, vertical = 12.dp),
                    verticalAlignment = Alignment.CenterVertically
                ) {
                    Column(modifier = Modifier.weight(1f)) {
                        Text("Demo-Modus", style = MaterialTheme.typography.titleMedium)
                        Text(
                            if (demoActive)
                                "Aktiv — aktualisiert alle ${DemoCalculator.POLL_MS / 1000}s"
                            else
                                "30-Sekunden-Fenster, kalibrierte Schwellenwerte",
                            style = MaterialTheme.typography.bodySmall
                        )
                    }
                    Switch(checked = demoActive, onCheckedChange = { demoActive = it })
                }

                if (demoActive) {
                    demoGardenState?.let { state ->
                        Text(
                            text     = "🌱 Gartenzustand: $state",
                            modifier = Modifier.padding(start = 16.dp, bottom = 4.dp),
                            style    = MaterialTheme.typography.bodyMedium
                        )
                    }

                    Button(
                        modifier = Modifier.padding(start = 16.dp, bottom = 8.dp),
                        enabled  = !demoRefreshing,
                        onClick  = { scope.launch { runDemoCalculation() } }
                    ) {
                        if (demoRefreshing) {
                            CircularProgressIndicator(
                                modifier  = Modifier.padding(end = 8.dp),
                                strokeWidth = 2.dp,
                                color     = MaterialTheme.colorScheme.onPrimary
                            )
                        }
                        Text("Gartenzustand aktualisieren")
                    }

                    demoSummary?.let { summary ->
                        Text(
                            text     = summary,
                            modifier = Modifier.padding(start = 16.dp, end = 16.dp, bottom = 12.dp),
                            style    = MaterialTheme.typography.bodySmall,
                            fontFamily = androidx.compose.ui.text.font.FontFamily.Monospace
                        )
                    } ?: CircularProgressIndicator(
                        modifier = Modifier
                            .padding(16.dp)
                            .align(Alignment.CenterHorizontally)
                    )
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

private fun buildDemoSummary(
    result: ch.zhaw.init.digitalfootprintexplorer.digitalfootprintexplorer.model.output.EmissionResult,
    state: String
): String {
    fun f(v: Double) = when {
        v == 0.0 -> "0.000000"
        else     -> "%.6f".format(v)
    }
    return """
window: 30 s
app    : ${f(result.ghgAppUsage  * 1000)} gCO₂e
display: ${f(result.ghgDisplay   * 1000)} gCO₂e
bg     : ${f(result.ghgBackground * 1000)} gCO₂e
total  : ${f(result.ghgTotal     * 1000)} gCO₂e
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
