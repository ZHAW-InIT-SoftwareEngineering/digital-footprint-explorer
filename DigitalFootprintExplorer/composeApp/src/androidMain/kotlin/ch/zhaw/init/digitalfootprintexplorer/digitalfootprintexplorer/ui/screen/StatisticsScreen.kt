package ch.zhaw.init.digitalfootprintexplorer.digitalfootprintexplorer.ui.screen

import android.util.Log
import androidx.compose.foundation.background
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.verticalScroll
import androidx.compose.material3.*
import androidx.compose.material3.HorizontalDivider
import androidx.compose.runtime.Composable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.unit.dp
import androidx.work.WorkInfo
import ch.zhaw.init.digitalfootprintexplorer.digitalfootprintexplorer.worker.KEY_GHG_APP_USAGE
import ch.zhaw.init.digitalfootprintexplorer.digitalfootprintexplorer.worker.KEY_GHG_BACKGROUND
import ch.zhaw.init.digitalfootprintexplorer.digitalfootprintexplorer.worker.KEY_GHG_DISPLAY
import ch.zhaw.init.digitalfootprintexplorer.digitalfootprintexplorer.worker.KEY_GHG_TOTAL
import ch.zhaw.init.digitalfootprintexplorer.digitalfootprintexplorer.ui.component.EmissionPieChart
import ch.zhaw.init.digitalfootprintexplorer.digitalfootprintexplorer.ui.component.EmissionRow
import ch.zhaw.init.digitalfootprintexplorer.digitalfootprintexplorer.R

@Composable
fun StatisticsScreen(
    workInfo: WorkInfo?,
    innerPadding: PaddingValues,
) {
    Column(
        modifier = Modifier
            .background(MaterialTheme.colorScheme.background)
            .padding(innerPadding)
            .fillMaxSize()
            .verticalScroll(rememberScrollState()),
        horizontalAlignment = Alignment.CenterHorizontally,
    ) {

        when (workInfo?.state) {

            WorkInfo.State.RUNNING,
            WorkInfo.State.ENQUEUED -> {
                CircularProgressIndicator(modifier = Modifier.padding(16.dp))
                Text("Worker running…", style = MaterialTheme.typography.bodySmall)
            }

            WorkInfo.State.SUCCEEDED -> {
                val appUsage = workInfo.outputData.getDouble(KEY_GHG_APP_USAGE, 0.0)
                val display = workInfo.outputData.getDouble(KEY_GHG_DISPLAY, 0.0)
                val background = workInfo.outputData.getDouble(KEY_GHG_BACKGROUND, 0.0)
                val total = workInfo.outputData.getDouble(KEY_GHG_TOTAL, 0.0)

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
                            color = Color(0xFF6200EE)
                        )

                        EmissionRow(
                            label = "Display",
                            valueGrams = display * 1000,
                            percentage = if (total > 0) (display / total) else 0.0,
                            color = Color(0xFF03DAC6)
                        )

                        EmissionRow(
                            label = stringResource(R.string.background),
                            valueGrams = background * 1000,
                            percentage = if (total > 0) (background / total) else 0.0,
                            color = Color(0xFFBB86FC)
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
            }

            WorkInfo.State.FAILED -> {
                Log.e("StatisticsScreen", "Worker failed — check Logcat tag: DFE_Worker")
            }

            else -> Unit
        }
    }
}