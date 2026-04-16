package ch.zhaw.init.digitalfootprintexplorer.digitalfootprintexplorer

import android.content.Context
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
        // All values are persisted in SharedPreferences so they survive activity restarts
        // (e.g. when the user opens the app via a widget click while demo is active).
        val demoPrefs = remember { context.getSharedPreferences("demo_prefs", Context.MODE_PRIVATE) }

        // Remember whether demo was already active when this composable first ran.
        // Used to distinguish "app opened while demo was on" from "user toggled demo on".
        val wasActiveOnStart = remember { demoPrefs.getBoolean("demo_active", false) }
        var demoActive      by remember { mutableStateOf(wasActiveOnStart) }
        var demoGardenState by remember { mutableStateOf(demoPrefs.getString("demo_garden_state", null)) }
        var demoSummaryText by remember { mutableStateOf(demoPrefs.getString("demo_summary", null)) }
        var demoRefreshing  by remember { mutableStateOf(false) }

        // On first composition, restore the persisted baseline so traffic accumulated
        // while the app was in the background (between last button press and now)
        // is not lost when the user opens the app.
        LaunchedEffect(Unit) {
            if (wasActiveOnStart) DemoCalculator.restoreBaseline(context)
        }

        // Reacts to explicit user toggles only (not the initial state from SharedPreferences,
        // since that is handled by the LaunchedEffect(Unit) above).
        // demoActive changes AFTER the first composition, so LaunchedEffect(demoActive)
        // fires exactly once on start (with the initial value) and then on each toggle.
        // We skip the first firing by checking against wasActiveOnStart:
        //   - same value as start → no change, already handled above
        //   - different value     → user toggled
        var demoInitialized by remember { mutableStateOf(false) }
        LaunchedEffect(demoActive) {
            if (!demoInitialized) {
                demoInitialized = true
                return@LaunchedEffect   // initial fire — already handled by LaunchedEffect(Unit)
            }
            // User explicitly toggled demo
            demoPrefs.edit().putBoolean("demo_active", demoActive).apply()
            if (demoActive) {
                // Toggled ON → fresh start: new baseline, clear old result
                DemoCalculator.resetBaseline(context)
                demoGardenState = null
                demoSummaryText = null
                demoPrefs.edit().remove("demo_garden_state").remove("demo_summary").apply()
            } else {
                // Toggled OFF → clear everything so the next activation starts clean
                DemoCalculator.clearBaseline(context)
                demoGardenState = null
                demoSummaryText = null
                demoPrefs.edit().remove("demo_garden_state").remove("demo_summary").apply()
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
                                    val (result, state, summary) = DemoCalculator.calculate(context)
                                    GardenWidget.updateState(context, state)
                                    demoGardenState = state.name
                                    demoSummaryText = summary
                                    // Persist so the result survives activity restarts
                                    demoPrefs.edit()
                                        .putString("demo_garden_state", state.name)
                                        .putString("demo_summary", summary)
                                        .apply()
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
