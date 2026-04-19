package ch.zhaw.init.digitalfootprintexplorer.digitalfootprintexplorer

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
import androidx.compose.material3.HorizontalDivider
import androidx.compose.runtime.*
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.text.TextStyle
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
import ch.zhaw.init.digitalfootprintexplorer.digitalfootprintexplorer.ui.theme.DFETheme
import ch.zhaw.init.digitalfootprintexplorer.digitalfootprintexplorer.ui.theme.pieChartDisplayColor
import ch.zhaw.init.digitalfootprintexplorer.digitalfootprintexplorer.ui.theme.pieChartAppUsageColor
import ch.zhaw.init.digitalfootprintexplorer.digitalfootprintexplorer.ui.theme.pieChartBackgroundColor
import ch.zhaw.init.digitalfootprintexplorer.digitalfootprintexplorer.widget.GardenWidget
import ch.zhaw.init.digitalfootprintexplorer.digitalfootprintexplorer.widget.GardenWidgetReceiver
import ch.zhaw.init.digitalfootprintexplorer.digitalfootprintexplorer.widget.WidgetOnboardingSheet
import ch.zhaw.init.digitalfootprintexplorer.digitalfootprintexplorer.worker.DailyFootprintWorker
import ch.zhaw.init.digitalfootprintexplorer.digitalfootprintexplorer.worker.KEY_DEBUG_SUMMARY
import ch.zhaw.init.digitalfootprintexplorer.digitalfootprintexplorer.worker.KEY_GHG_APP_USAGE
import ch.zhaw.init.digitalfootprintexplorer.digitalfootprintexplorer.worker.KEY_GHG_BACKGROUND
import ch.zhaw.init.digitalfootprintexplorer.digitalfootprintexplorer.worker.KEY_GHG_DISPLAY
import ch.zhaw.init.digitalfootprintexplorer.digitalfootprintexplorer.worker.KEY_GHG_TOTAL
import ch.zhaw.init.digitalfootprintexplorer.digitalfootprintexplorer.worker.TAG_DEBUG_RUN
import com.patrykandpatrick.vico.compose.common.Fill
import com.patrykandpatrick.vico.compose.common.component.TextComponent
import com.patrykandpatrick.vico.compose.pie.PieChart
import com.patrykandpatrick.vico.compose.pie.PieChartHost
import com.patrykandpatrick.vico.compose.pie.data.PieChartModelProducer
import com.patrykandpatrick.vico.compose.pie.data.PieValueFormatter
import com.patrykandpatrick.vico.compose.pie.data.pieSeries
import com.patrykandpatrick.vico.compose.pie.rememberPieChart
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.flow.flowOf
import kotlinx.coroutines.launch
import java.util.UUID
import kotlin.math.roundToInt

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
            val installedIds = GlanceAppWidgetManager(context).getGlanceIds(GardenWidget::class.java)
            showWidgetOnboarding = installedIds.isEmpty()

            if (!hasUsageStatsPermission(context)) {
                showPermissionOnboarding = true
            }
        }

        if (showWidgetOnboarding) {
            WidgetOnboardingSheet(
                onDismiss = { showWidgetOnboarding = false },
                onPin = {
                    scope.launch {
                        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                            GlanceAppWidgetManager(context).requestPinGlanceAppWidget(
                                receiver = GardenWidgetReceiver::class.java,
                                preview = GardenWidget()
                            )
                        }
                        showWidgetOnboarding = false
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
                                        if (enabled) repo.activate() else repo.deactivate()
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
                    Column(
                        modifier = Modifier
                            .background(MaterialTheme.colorScheme.background)
                            .padding(innerPadding)
                            .fillMaxSize()
                            .verticalScroll(rememberScrollState()),
                        horizontalAlignment = Alignment.CenterHorizontally,
                    ) {
                        when (currentWorkInfo?.state) {
                            WorkInfo.State.RUNNING,
                            WorkInfo.State.ENQUEUED -> {
                                CircularProgressIndicator(modifier = Modifier.padding(16.dp))
                                Text("Worker running…", style = MaterialTheme.typography.bodySmall)
                            }

                            WorkInfo.State.SUCCEEDED -> {
                                val appUsage =
                                    currentWorkInfo?.outputData?.getDouble(KEY_GHG_APP_USAGE, 0.0) ?: 0.0
                                val display =
                                    currentWorkInfo?.outputData?.getDouble(KEY_GHG_DISPLAY, 0.0) ?: 0.0
                                val background =
                                    currentWorkInfo?.outputData?.getDouble(KEY_GHG_BACKGROUND, 0.0) ?: 0.0
                                val total =
                                    currentWorkInfo?.outputData?.getDouble(KEY_GHG_TOTAL, 0.0) ?: 0.0

                                if (total > 0) {
                                    EmissionPieChart(
                                        appUsage = appUsage,
                                        display = display,
                                        background = background,
                                        modifier = Modifier
                                            .height(240.dp)
                                            .fillMaxWidth()
                                            .padding(horizontal = 16.dp)
                                    )
                                } else {
                                    Text(
                                        stringResource(R.string.no_emissions),
                                        modifier = Modifier.padding(16.dp)
                                    )
                                }

                                Card(
                                    modifier = Modifier
                                        .fillMaxWidth()
                                        .padding(16.dp),
                                    colors = CardDefaults.cardColors(
                                        containerColor = MaterialTheme.colorScheme.surfaceVariant
                                    )
                                ) {
                                    Column(Modifier.padding(16.dp)) {
                                        Text("Details:", style = MaterialTheme.typography.titleSmall)
                                        Spacer(Modifier.height(8.dp))

                                        EmissionRow(
                                            label = stringResource(R.string.app_usage),
                                            valueGrams = appUsage * 1000,
                                            percentage = if (total > 0) (appUsage / total) * 100 else 0.0,
                                            color = pieChartAppUsageColor
                                        )
                                        EmissionRow(
                                            label = "Display",
                                            valueGrams = display * 1000,
                                            percentage = if (total > 0) (display / total) * 100 else 0.0,
                                            color = pieChartDisplayColor
                                        )
                                        EmissionRow(
                                            label = stringResource(R.string.background),
                                            valueGrams = background * 1000,
                                            percentage = if (total > 0) (background / total) * 100 else 0.0,
                                            color = pieChartBackgroundColor
                                        )

                                        HorizontalDivider(
                                            Modifier.padding(vertical = 8.dp),
                                            DividerDefaults.Thickness,
                                            DividerDefaults.color
                                        )

                                        Text(
                                            "Total: ${"%.2f".format(total * 1000)} gCO₂e",
                                            style = MaterialTheme.typography.bodyLarge
                                        )
                                    }
                                }
                            }

                            WorkInfo.State.FAILED -> {
                                DebugResultCard("❌ Worker failed — check Logcat tag: DFE_Worker")
                            }

                            else -> Unit
                        }
                    }
                }
            }
        }
    }
}

@Composable
private fun EmissionPieChart(
    appUsage: Double,
    display: Double,
    background: Double,
    modifier: Modifier = Modifier
) {
    val total = (appUsage + display + background).toFloat()
    val modelProducer = remember { PieChartModelProducer() }

    LaunchedEffect(appUsage, display, background) {
        modelProducer.runTransaction {
            pieSeries {
                series(
                    appUsage.toFloat(),
                    display.toFloat(),
                    background.toFloat()
                )
            }
        }
    }

    val labelComponent = remember {
        TextComponent(
            textStyle = TextStyle(color = Color.White)
        )
    }

    val pieChart = rememberPieChart(
        sliceProvider = PieChart.SliceProvider.series(
            listOf(
                PieChart.Slice(
                    fill = Fill(pieChartAppUsageColor),
                    label = PieChart.SliceLabel.Inside(labelComponent)
                ),
                PieChart.Slice(
                    fill = Fill(pieChartDisplayColor),
                    label = PieChart.SliceLabel.Inside(labelComponent)
                ),
                PieChart.Slice(
                    fill = Fill(pieChartBackgroundColor),
                    label = PieChart.SliceLabel.Inside(labelComponent)
                )
            )
        ),
        valueFormatter = PieValueFormatter { _, value, _ ->
            if (total <= 0f) {
                ""
            } else {
                "${((value / total) * 100f).roundToInt()}%"
            }
        }
    )

    PieChartHost(
        chart = pieChart,
        modelProducer = modelProducer,
        modifier = modifier
    )
}

@Composable
private fun EmissionRow(
    label: String,
    valueGrams: Double,
    percentage: Double,
    color: Color
) {
    Row(
        modifier = Modifier
            .fillMaxWidth()
            .padding(vertical = 4.dp),
        verticalAlignment = Alignment.CenterVertically
    ) {
        Box(
            Modifier
                .size(12.dp)
                .background(color)
        )
        Spacer(Modifier.width(8.dp))
        Text(
            label,
            style = MaterialTheme.typography.bodyMedium,
            modifier = Modifier.weight(1f)
        )
        Text(
            "${"%.2f".format(valueGrams)}g (${"%.1f".format(percentage)}%)",
            style = MaterialTheme.typography.bodyMedium
        )
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