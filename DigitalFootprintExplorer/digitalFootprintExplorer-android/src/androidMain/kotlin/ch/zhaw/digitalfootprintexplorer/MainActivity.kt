package ch.zhaw.digitalfootprintexplorer

import android.os.Bundle
import androidx.activity.ComponentActivity
import androidx.activity.compose.setContent
import androidx.activity.enableEdgeToEdge
import androidx.compose.runtime.Composable
import androidx.compose.ui.tooling.preview.Preview
import ch.zhaw.digitalfootprintexplorer.permission.hasUsageStatsPermission
import ch.zhaw.digitalfootprintexplorer.servicelayerplatform.service.TrackingService
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
    }
}

@Preview
@Composable
fun AppAndroidPreview() {
    App()
}