package ch.zhaw.init.digitalfootprintexplorer.digitalfootprintexplorer

import android.content.Context
import android.os.Build
import android.util.Log
import androidx.compose.foundation.background
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.AutoGraph
import androidx.compose.material.icons.filled.Home
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.tooling.preview.Preview
import androidx.compose.ui.unit.dp
import androidx.glance.appwidget.GlanceAppWidgetManager
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import androidx.work.OneTimeWorkRequestBuilder
import androidx.work.WorkInfo
import androidx.work.WorkManager
import ch.zhaw.init.digitalfootprintexplorer.digitalfootprintexplorer.demo.DemoRepository
import ch.zhaw.init.digitalfootprintexplorer.digitalfootprintexplorer.permission.UsageStatsPermissionSheet
import ch.zhaw.init.digitalfootprintexplorer.digitalfootprintexplorer.permission.hasUsageStatsPermission
import ch.zhaw.init.digitalfootprintexplorer.digitalfootprintexplorer.permission.openUsageStatsSettings
import ch.zhaw.init.digitalfootprintexplorer.digitalfootprintexplorer.ui.screen.StatisticsScreen
import ch.zhaw.init.digitalfootprintexplorer.digitalfootprintexplorer.ui.theme.DFETheme
import ch.zhaw.init.digitalfootprintexplorer.digitalfootprintexplorer.widget.GardenWidget
import ch.zhaw.init.digitalfootprintexplorer.digitalfootprintexplorer.widget.GardenWidgetReceiver
import ch.zhaw.init.digitalfootprintexplorer.digitalfootprintexplorer.widget.WidgetOnboardingSheet
import ch.zhaw.init.digitalfootprintexplorer.digitalfootprintexplorer.worker.DailyFootprintWorker
import ch.zhaw.init.digitalfootprintexplorer.digitalfootprintexplorer.worker.KEY_DEBUG_SUMMARY
import ch.zhaw.init.digitalfootprintexplorer.digitalfootprintexplorer.worker.TAG_DEBUG_RUN
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.flow.flowOf
import kotlinx.coroutines.launch
import java.util.UUID
import androidx.core.content.edit

@OptIn(ExperimentalMaterial3Api::class)
@Composable
@Preview
fun App() {
    DFETheme {
        val context = LocalContext.current
        val scope = rememberCoroutineScope()
        var showWidgetOnboarding by remember { mutableStateOf(false) }
        var showPermissionOnboarding by remember { mutableStateOf(false) }

        LaunchedEffect(Unit) {
            val prefs = context.getSharedPreferences("dfe_onboarding", Context.MODE_PRIVATE)
            val widgetOnboardingDone = prefs.getBoolean("widget_onboarding_done", false)
            showWidgetOnboarding = !widgetOnboardingDone

            if (!hasUsageStatsPermission(context)) {
                showPermissionOnboarding = true
            }
        }

        if (showWidgetOnboarding && !showPermissionOnboarding) {
            val markOnboardingDone = {
                context.getSharedPreferences("dfe_onboarding", Context.MODE_PRIVATE)
                    .edit { putBoolean("widget_onboarding_done", true) }
                showWidgetOnboarding = false
            }
            WidgetOnboardingSheet(
                onDismiss = { markOnboardingDone() },
                onPin = {
                    scope.launch {
                        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                            GlanceAppWidgetManager(context).requestPinGlanceAppWidget(
                                receiver = GardenWidgetReceiver::class.java,
                                preview = GardenWidget()
                            )
                        }
                        markOnboardingDone()
                    }
                }
            )
        }

        if (showPermissionOnboarding) {
            UsageStatsPermissionSheet(
                onDismiss = { showPermissionOnboarding = false },
                onOpenSettings = {
                    openUsageStatsSettings(context)
                    showPermissionOnboarding = false
                }
            )
        }

        val repo = remember { DemoRepository(context) }
        var demoActive by remember { mutableStateOf(repo.wasActiveOnStart) }
        var demoSummaryText by remember { mutableStateOf(repo.loadSummary()) }
        var demoRefreshing by remember { mutableStateOf(false) }

        var currentJobId by remember { mutableStateOf<UUID?>(null) }
        val currentWorkInfo by remember(currentJobId) {
            currentJobId?.let { id ->
                WorkManager.getInstance(context).getWorkInfoByIdFlow(id)
            } ?: flowOf(null)
        }.collectAsStateWithLifecycle(null)

        var selectedTab by remember { mutableIntStateOf(0) }

        Scaffold(
            topBar = {
                TopAppBar(
                    title = { Text("Digital Footprint Explorer") }
                )
            },
            bottomBar = {
                NavigationBar {
                    NavigationBarItem(
                        selected = selectedTab == 0,
                        onClick = { selectedTab = 0 },
                        icon = {
                            Icon(
                                Icons.Default.Home,
                                contentDescription = stringResource(R.string.home)
                            )
                        },
                        label = { Text(stringResource(R.string.home)) }
                    )
                    NavigationBarItem(
                        selected = selectedTab == 1,
                        onClick = { selectedTab = 1 },
                        icon = {
                            Icon(
                                Icons.Default.AutoGraph,
                                contentDescription = stringResource(R.string.statistics)
                            )
                        },
                        label = { Text(stringResource(R.string.statistics)) }
                    )
                }
            }
        ) { innerPadding ->
            when (selectedTab) {
                0 -> {
                    Column(
                        modifier = Modifier
                            .background(MaterialTheme.colorScheme.background)
                            .padding(innerPadding)
                            .fillMaxSize()
                            .verticalScroll(rememberScrollState()),
                        horizontalAlignment = Alignment.CenterHorizontally,
                    ) {
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
                                }
                                Switch(
                                    checked = demoActive,
                                    onCheckedChange = { enabled ->
                                        demoActive = enabled
                                        demoSummaryText = null
                                        if (enabled) {
                                            repo.activate()
                                        } else {
                                            scope.launch { repo.deactivate() }
                                        }
                                    }
                                )
                            }

                            if (demoActive) {
                                Button(
                                    modifier = Modifier.padding(start = 16.dp, bottom = 8.dp),
                                    enabled = !demoRefreshing,
                                    onClick = {
                                        scope.launch {
                                            demoRefreshing = true
                                            try {
                                                val (result, state) = repo.refresh()
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
                                            modifier = Modifier.padding(end = 8.dp),
                                            strokeWidth = 2.dp,
                                            color = MaterialTheme.colorScheme.onPrimary
                                        )
                                    }
                                    Text("Gartenzustand aktualisieren")
                                }

                                demoSummaryText?.let { summary ->
                                    Text(
                                        text = summary,
                                        modifier = Modifier.padding(
                                            start = 16.dp,
                                            end = 16.dp,
                                            bottom = 12.dp
                                        ),
                                        style = MaterialTheme.typography.bodySmall,
                                        fontFamily = androidx.compose.ui.text.font.FontFamily.Monospace
                                    )
                                }
                            }
                        }

                        Button(
                            modifier = Modifier.padding(top = 8.dp),
                            colors = ButtonDefaults.buttonColors(
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

                            else -> Unit
                        }
                    }
                }

                1 -> {
                    StatisticsScreen(
                        workInfo = currentWorkInfo,
                        innerPadding = innerPadding
                    )
                }
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
            text = text,
            modifier = Modifier.padding(12.dp),
            style = MaterialTheme.typography.bodySmall,
            fontFamily = androidx.compose.ui.text.font.FontFamily.Monospace
        )
    }
}