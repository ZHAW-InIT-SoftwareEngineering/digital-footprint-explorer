/*
 * Copyright (C) 2026 Zurich University of Applied Sciences, Switzerland
 *
 * This program is free software: you can redistribute it and/or modify
 * it under the terms of the GNU Affero General Public License as published by
 * the Free Software Foundation, either version 3 of the License, or
 * (at your option) any later version.
 *
 * This program is distributed in the hope that it will be useful,
 * but WITHOUT ANY WARRANTY; without even the implied warranty of
 * MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
 * GNU Affero General Public License for more details.
 *
 * You should have received a copy of the GNU Affero General Public License
 * along with this program.  If not, see <https://www.gnu.org/licenses/>.
 */

package ch.zhaw.digitalfootprintexplorer

import android.os.Bundle
import androidx.activity.ComponentActivity
import androidx.activity.compose.setContent
import androidx.activity.enableEdgeToEdge
import androidx.compose.runtime.Composable
import androidx.compose.ui.tooling.preview.Preview
import androidx.lifecycle.lifecycleScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext
import android.content.Context
import ch.zhaw.digitalfootprintexplorer.demo.DemoPreferences
import ch.zhaw.digitalfootprintexplorer.permission.hasUsageStatsPermission
import ch.zhaw.digitalfootprintexplorer.servicelayerplatform.service.TrackingService
import ch.zhaw.digitalfootprintexplorer.widget.GardenWidget
import ch.zhaw.digitalfootprintexplorer.worker.DailyFootprintWorker

class MainActivity : ComponentActivity() {
    override fun onCreate(savedInstanceState: Bundle?) {
        enableEdgeToEdge()
        super.onCreate(savedInstanceState)

        //ensure that the permissions are granted before starting the worker, otherwise data will be missing
        if (hasUsageStatsPermission(this)) {
            DailyFootprintWorker.runNow(applicationContext)
        }

        setContent {
            App()
        }
    }

    override fun onResume() {
        super.onResume()
        TrackingService.start(this)

        syncWidgetWithLatestGardenState()

        // Statistics only: the current day (midnight → now) is recalculated whenever the app is opened.
        if (hasUsageStatsPermission(this)) {
            val app = application as DFEApplication
            lifecycleScope.launch { app.todayFootprint.refresh() }
        }
    }

    /**
     * The home tab reads the garden state from the database, the widget keeps its own copy.
     * Pushing the latest stored state on every start keeps both identical, no matter how the
     * database was changed (worker, restored backup, ...). Demo mode manages the widget itself.
     */
    private fun syncWidgetWithLatestGardenState() {
        val demoActive = getSharedPreferences(DemoPreferences.PREFS_STATE_FILE, Context.MODE_PRIVATE)
            .getBoolean(DemoPreferences.KEY_ACTIVE, false)
        if (demoActive) return

        val app = application as DFEApplication
        lifecycleScope.launch {
            val latest = withContext(Dispatchers.Default) {
                app.gardenStateCalculator.getLatestGardenState()
            } ?: return@launch
            GardenWidget.updateState(applicationContext, latest)
        }
    }
}

@Preview
@Composable
fun AppAndroidPreview() {
    App()
}