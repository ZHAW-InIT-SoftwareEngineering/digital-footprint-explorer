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
import ch.zhaw.init.digitalfootprintexplorer.digitalfootprintexplorer.model.GardenState
import androidx.compose.runtime.*
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.tooling.preview.Preview
import androidx.compose.ui.unit.dp
import androidx.glance.appwidget.GlanceAppWidgetManager
import ch.zhaw.init.digitalfootprintexplorer.digitalfootprintexplorer.demo.DemoRepository
import ch.zhaw.init.digitalfootprintexplorer.digitalfootprintexplorer.permission.hasUsageStatsPermission
import ch.zhaw.init.digitalfootprintexplorer.digitalfootprintexplorer.permission.openUsageStatsSettings
import ch.zhaw.init.digitalfootprintexplorer.digitalfootprintexplorer.ui.screen.StatisticsScreen
import ch.zhaw.init.digitalfootprintexplorer.digitalfootprintexplorer.ui.theme.DFETheme
import ch.zhaw.init.digitalfootprintexplorer.digitalfootprintexplorer.widget.GardenWidget
import ch.zhaw.init.digitalfootprintexplorer.digitalfootprintexplorer.widget.GardenWidgetReceiver
import ch.zhaw.init.digitalfootprintexplorer.digitalfootprintexplorer.widget.WidgetOnboardingSheet
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.launch
import androidx.core.content.edit
import androidx.lifecycle.Lifecycle
import androidx.lifecycle.LifecycleEventObserver
import androidx.lifecycle.compose.LocalLifecycleOwner
import ch.zhaw.init.digitalfootprintexplorer.digitalfootprintexplorer.demo.DemoPreferences.KEY_GARDEN_STATE
import ch.zhaw.init.digitalfootprintexplorer.digitalfootprintexplorer.demo.DemoPreferences.PREFS_STATE_FILE
import ch.zhaw.init.digitalfootprintexplorer.digitalfootprintexplorer.ui.component.GardenStateCard
import ch.zhaw.init.digitalfootprintexplorer.digitalfootprintexplorer.ui.screen.UsageStatsPermissionRequiredScreen

@OptIn(ExperimentalMaterial3Api::class)
@Composable
@Preview
fun App() {
    DFETheme {
        val context = LocalContext.current
        val scope = rememberCoroutineScope()
        val lifecycleOwner = LocalLifecycleOwner.current

        var hasUsagePermission by remember {
            mutableStateOf(hasUsageStatsPermission(context))
        }
        var showWidgetOnboarding by remember {
            mutableStateOf(false)
        }

        LaunchedEffect(Unit) {
            val prefs = context.getSharedPreferences("dfe_onboarding", Context.MODE_PRIVATE)
            val widgetOnboardingDone = prefs.getBoolean("widget_onboarding_done", false)

            showWidgetOnboarding = !widgetOnboardingDone
            hasUsagePermission = hasUsageStatsPermission(context)
        }

        // Recheck if permission was granted when user returns into app
        DisposableEffect(lifecycleOwner) {
            val observer = LifecycleEventObserver { _, event ->

                if (event == Lifecycle.Event.ON_RESUME) {
                    hasUsagePermission = hasUsageStatsPermission(context)
                }
            }

            lifecycleOwner.lifecycle.addObserver(observer)

            onDispose {
                lifecycleOwner.lifecycle.removeObserver(observer)
            }
        }

        if (!hasUsagePermission) {
            UsageStatsPermissionRequiredScreen(
                onOpenSettings = {
                    openUsageStatsSettings(context)
                }
            )
        } else {
            val markOnboardingDone = {
                context.getSharedPreferences("dfe_onboarding", Context.MODE_PRIVATE)
                    .edit {
                        putBoolean("widget_onboarding_done", true)
                    }
                showWidgetOnboarding = false
            }

            if (showWidgetOnboarding) {
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


            val repo = remember { DemoRepository(context) }
            var demoActive by remember { mutableStateOf(repo.wasActiveOnStart) }
            var demoSummaryText by remember { mutableStateOf(repo.loadSummary()) }
            var demoRefreshing by remember { mutableStateOf(false) }

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
                            val gardenState by produceState<GardenState?>(initialValue = null, demoActive, demoRefreshing) {
                                value = if (demoActive) {
                                    val prefs = context.getSharedPreferences(PREFS_STATE_FILE, Context.MODE_PRIVATE)
                                    val stateStr = prefs.getString(KEY_GARDEN_STATE, null)
                                    stateStr?.let { runCatching { GardenState.valueOf(it) }.getOrNull() }
                                } else {
                                    val app = context.applicationContext as DFEApplication
                                    app.gardenStateCalculator.getLatestGardenState()
                                }
                            }

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
                            GardenStateCard(gardenState)
                        }
                    }

                    1 -> {
                        StatisticsScreen(
                            innerPadding = innerPadding
                        )
                    }
                }
            }
        }
    }
}

