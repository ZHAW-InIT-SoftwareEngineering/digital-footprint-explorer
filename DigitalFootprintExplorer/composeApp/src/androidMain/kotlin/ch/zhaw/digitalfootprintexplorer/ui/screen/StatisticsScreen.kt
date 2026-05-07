package ch.zhaw.digitalfootprintexplorer.ui.screen

import androidx.compose.foundation.background
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.verticalScroll
import androidx.compose.material3.*
import androidx.compose.material3.HorizontalDivider
import androidx.compose.runtime.Composable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.unit.dp
import androidx.compose.ui.platform.LocalContext
import androidx.compose.runtime.getValue
import androidx.compose.runtime.produceState
import ch.zhaw.digitalfootprintexplorer.DFEApplication
import ch.zhaw.digitalfootprintexplorer.model.DailyFootprintEntry
import ch.zhaw.digitalfootprintexplorer.ui.component.EmissionPieChart
import ch.zhaw.digitalfootprintexplorer.ui.component.EmissionRow
import ch.zhaw.digitalfootprintexplorer.R
import ch.zhaw.digitalfootprintexplorer.ui.theme.Spacing
import ch.zhaw.digitalfootprintexplorer.ui.theme.pieChartAppUsageColor
import ch.zhaw.digitalfootprintexplorer.ui.theme.pieChartBackgroundColor
import ch.zhaw.digitalfootprintexplorer.ui.theme.pieChartDisplayColor

@Composable
fun StatisticsScreen(
    innerPadding: PaddingValues
) {
    val context = LocalContext.current
    val app = context.applicationContext as DFEApplication

    val latestEntry by produceState<DailyFootprintEntry?>(initialValue = null) {
        value = app.gardenStateCalculator.getLatestEntry()
    }

    Column(
        modifier = Modifier
            .background(MaterialTheme.colorScheme.background)
            .padding(innerPadding)
            .fillMaxSize()
            .verticalScroll(rememberScrollState()),
        horizontalAlignment = Alignment.CenterHorizontally
    ) {
        if (latestEntry != null) {
            val entry = latestEntry!!
            val appUsage = entry.ghgAppUsage
            val display = entry.ghgDisplay
            val background = entry.ghgBackground
            val total = entry.kgCO2e

            Card(
                modifier = Modifier.fillMaxWidth(),
                colors = CardDefaults.cardColors(
                    containerColor = MaterialTheme.colorScheme.surfaceContainer
                ),
                shape = MaterialTheme.shapes.medium
            ) {
                Column(
                    modifier = Modifier
                        .fillMaxWidth()
                        .padding(20.dp),
                    horizontalAlignment = Alignment.CenterHorizontally
                ) {
                    Text(
                        text = stringResource(R.string.statistics_screen_title),
                        style = MaterialTheme.typography.titleLarge,
                        color = MaterialTheme.colorScheme.onBackground
                    )

                    Spacer(Modifier.height(Spacing.gutter))

                    if (total > 0) {
                        EmissionPieChart(
                            appUsage = appUsage,
                            display = display,
                            background = background,
                            modifier = Modifier
                                .height(240.dp)
                                .fillMaxWidth()
                        )
                    } else {
                        Text(
                            text = stringResource(R.string.no_emissions),
                            modifier = Modifier.padding(vertical = 16.dp),
                            color = MaterialTheme.colorScheme.onBackground
                        )
                    }

                    Spacer(Modifier.height(Spacing.gutter))

                    Column(
                        modifier = Modifier.fillMaxWidth()
                    ) {
                        Text(
                            text = "Details:",
                            style = MaterialTheme.typography.titleSmall
                        )

                        Spacer(Modifier.height(8.dp))

                        EmissionRow(
                            label = stringResource(R.string.app_usage),
                            valueGrams = appUsage * 1000,
                            percentage = if (total > 0) (appUsage / total) else 0.0,
                            color = pieChartAppUsageColor
                        )

                        EmissionRow(
                            label = "Display",
                            valueGrams = display * 1000,
                            percentage = if (total > 0) (display / total) else 0.0,
                            color = pieChartDisplayColor
                        )

                        EmissionRow(
                            label = stringResource(R.string.background),
                            valueGrams = background * 1000,
                            percentage = if (total > 0) (background / total) else 0.0,
                            color = pieChartBackgroundColor
                        )

                        HorizontalDivider(
                            modifier = Modifier.padding(vertical = 8.dp),
                            thickness = DividerDefaults.Thickness,
                            color = DividerDefaults.color
                        )

                        Text(
                            text = "Total: ${"%.2f".format(total * 1000)} g CO₂e",
                            style = MaterialTheme.typography.bodyLarge
                        )
                    }
                }
            }
        } else {
            Card(
                modifier = Modifier.fillMaxWidth(),
                colors = CardDefaults.cardColors(
                    containerColor = MaterialTheme.colorScheme.surfaceContainer
                ),
                shape = MaterialTheme.shapes.medium
            ) {
                Box(
                    modifier = Modifier
                        .fillMaxWidth()
                        .padding(32.dp),
                    contentAlignment = Alignment.Center
                ) {
                    Text(
                        text = stringResource(R.string.no_statistics),
                        textAlign = androidx.compose.ui.text.style.TextAlign.Center,
                        style = MaterialTheme.typography.bodyMedium,
                        color = MaterialTheme.colorScheme.onSurfaceVariant
                    )
                }
            }
        }
    }
}