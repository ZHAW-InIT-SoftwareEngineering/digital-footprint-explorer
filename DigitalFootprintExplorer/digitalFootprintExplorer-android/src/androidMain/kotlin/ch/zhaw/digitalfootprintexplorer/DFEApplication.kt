package ch.zhaw.digitalfootprintexplorer

import android.app.Application
import android.util.Log
import androidx.work.WorkManager
import ch.zhaw.digitalfootprintexplorer.database.DatabaseDriverFactory
import ch.zhaw.digitalfootprintexplorer.database.createDatabase
import ch.zhaw.digitalfootprintexplorer.model.GardenStateCalculator
import ch.zhaw.digitalfootprintexplorer.servicelayerplatform.service.BackgroundProcessTracker
import ch.zhaw.digitalfootprintexplorer.servicelayerplatform.service.DisplayBrightnessObserver
import ch.zhaw.digitalfootprintexplorer.servicelayerplatform.service.TrackingService
import ch.zhaw.digitalfootprintexplorer.util.WORKER_NAME
import ch.zhaw.digitalfootprintexplorer.widget.GardenWidget
import ch.zhaw.digitalfootprintexplorer.worker.DailyFootprintWorker
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.launch

/**
 * Application entry point.
 *
 * Initialises:
 *  - SQLDelight database and [GardenStateCalculator]
 *  - [DisplayBrightnessObserver] and [BackgroundProcessTracker] (registration is handled
 *    by [TrackingService] so that tracking continues even when the app is not in the foreground)
 *  - [TrackingService] as a foreground service for continuous brightness / GPS / Bluetooth tracking
 *  - [DailyFootprintWorker] scheduled via WorkManager (runs once per 24 h)
 */
class DFEApplication : Application() {

    lateinit var gardenStateCalculator: GardenStateCalculator
        private set

    lateinit var displayBrightnessObserver: DisplayBrightnessObserver
        private set

    lateinit var backgroundProcessTracker: BackgroundProcessTracker
        private set

    override fun onCreate() {
        super.onCreate()

        val db = createDatabase(DatabaseDriverFactory(this))
        gardenStateCalculator = GardenStateCalculator(db)

        displayBrightnessObserver = DisplayBrightnessObserver(this)
        backgroundProcessTracker = BackgroundProcessTracker(this)
        
        restoreWidgetIfUpdated()

        TrackingService.start(this)

        WorkManager.getInstance(this).cancelUniqueWork(WORKER_NAME)
        DailyFootprintWorker.scheduleNext(this)
    }

    private fun restoreWidgetIfUpdated() {
        val prefs = getSharedPreferences("dfe_prefs", MODE_PRIVATE)
        val lastVersion = prefs.getLong("last_known_version", 0L)
        val currentVersion = BuildConfig.VERSION_CODE.toLong()

        if (currentVersion > lastVersion) {
            Log.d(TAG, "Version from changed $lastVersion to $currentVersion, restoring widget")
            prefs.edit().putLong("last_known_version", currentVersion).apply()

            CoroutineScope(Dispatchers.Default).launch {
                try {
                    val latestState = gardenStateCalculator.getLatestGardenState()
                    if (latestState != null) {
                        GardenWidget.updateState(this@DFEApplication, latestState)
                        Log.d(TAG, "Widget restored after update")
                    }
                } catch (e: Exception) {
                    Log.e(TAG, "Error restoring widget after update", e)
                }
            }
        }
    }

    companion object {
        private const val TAG = "DFEApplication"
    }
}
