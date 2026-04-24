package ch.zhaw.init.digitalfootprintexplorer.digitalfootprintexplorer.ui.screen

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
import ch.zhaw.init.digitalfootprintexplorer.digitalfootprintexplorer.DFEApplication
import ch.zhaw.init.digitalfootprintexplorer.digitalfootprintexplorer.model.DailyFootprintEntry
import ch.zhaw.init.digitalfootprintexplorer.digitalfootprintexplorer.ui.component.EmissionPieChart
import ch.zhaw.init.digitalfootprintexplorer.digitalfootprintexplorer.ui.component.EmissionRow
import ch.zhaw.init.digitalfootprintexplorer.digitalfootprintexplorer.R
import ch.zhaw.init.digitalfootprintexplorer.digitalfootprintexplorer.ui.theme.pieChartAppUsageColor
import ch.zhaw.init.digitalfootprintexplorer.digitalfootprintexplorer.ui.theme.pieChartBackgroundColor
import ch.zhaw.init.digitalfootprintexplorer.digitalfootprintexplorer.ui.theme.pieChartDisplayColor

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
        horizontalAlignment = Alignment.CenterHorizontally,
    ) {

        if (latestEntry != null) {
            val entry = latestEntry!!
            val appUsage = entry.ghgAppUsage
            val display = entry.ghgDisplay
            val background = entry.ghgBackground
            val total = entry.kgCO2e

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
                        Modifier.padding(vertical = 8.dp),
                        DividerDefaults.Thickness,
                        DividerDefaults.color
                    )

                    Text(
                        "Total: ${"%.2f".format(total * 1000)}g",
                        style = MaterialTheme.typography.bodyLarge
                    )
                }
            }
        } else {
            Box(
                modifier = Modifier
                    .fillMaxSize()
                    .padding(32.dp),
                contentAlignment = Alignment.Center
            ) {
                Text(
                    stringResource(R.string.no_statistics),
                    textAlign = androidx.compose.ui.text.style.TextAlign.Center,
                    style = MaterialTheme.typography.bodyMedium,
                    color = MaterialTheme.colorScheme.onSurfaceVariant
                )
            }
        }
    }
}