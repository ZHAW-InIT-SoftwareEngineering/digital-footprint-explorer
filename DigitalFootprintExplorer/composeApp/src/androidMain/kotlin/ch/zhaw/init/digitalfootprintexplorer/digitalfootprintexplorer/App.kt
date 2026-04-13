package ch.zhaw.init.digitalfootprintexplorer.digitalfootprintexplorer

import android.os.Build
import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.safeContentPadding
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.verticalScroll
import androidx.compose.material3.Button
import androidx.compose.material3.Card
import androidx.compose.material3.CardDefaults
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.MaterialTheme
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
import java.util.UUID
import ch.zhaw.init.digitalfootprintexplorer.digitalfootprintexplorer.ui.theme.DFETheme
import ch.zhaw.init.digitalfootprintexplorer.digitalfootprintexplorer.widget.GardenWidget
import ch.zhaw.init.digitalfootprintexplorer.digitalfootprintexplorer.widget.GardenWidgetReceiver
import ch.zhaw.init.digitalfootprintexplorer.digitalfootprintexplorer.widget.WidgetOnboardingSheet
import ch.zhaw.init.digitalfootprintexplorer.digitalfootprintexplorer.worker.DailyFootprintWorker
import ch.zhaw.init.digitalfootprintexplorer.digitalfootprintexplorer.worker.KEY_DEBUG_SUMMARY
import ch.zhaw.init.digitalfootprintexplorer.digitalfootprintexplorer.worker.TAG_DEBUG_RUN
import kotlinx.coroutines.flow.flowOf
import kotlinx.coroutines.launch

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

        // Track the ID of the most recently triggered debug job
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
            Button(
                modifier = Modifier.padding(top = 16.dp),
                onClick  = {
                    val request = OneTimeWorkRequestBuilder<DailyFootprintWorker>()
                        .addTag(TAG_DEBUG_RUN)
                        .build()
                    WorkManager.getInstance(context).enqueue(request)
                    currentJobId = request.id  // always track the newest job
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
                    if (summary != null) {
                        DebugResultCard(summary)
                    }
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
            text     = text,
            modifier = Modifier.padding(12.dp),
            style    = MaterialTheme.typography.bodySmall,
            fontFamily = androidx.compose.ui.text.font.FontFamily.Monospace
        )
    }
}
