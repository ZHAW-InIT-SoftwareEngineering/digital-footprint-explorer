package ch.zhaw.init.digitalfootprintexplorer.digitalfootprintexplorer

import android.app.Application
import androidx.work.WorkManager
import ch.zhaw.init.digitalfootprintexplorer.digitalfootprintexplorer.database.DatabaseDriverFactory
import ch.zhaw.init.digitalfootprintexplorer.digitalfootprintexplorer.database.createDatabase
import ch.zhaw.init.digitalfootprintexplorer.digitalfootprintexplorer.model.GardenStateCalculator
import ch.zhaw.init.digitalfootprintexplorer.digitalfootprintexplorer.servicelayerplatform.service.BackgroundProcessTracker
import ch.zhaw.init.digitalfootprintexplorer.digitalfootprintexplorer.servicelayerplatform.service.DisplayBrightnessObserver
import ch.zhaw.init.digitalfootprintexplorer.digitalfootprintexplorer.servicelayerplatform.service.TrackingService
import ch.zhaw.init.digitalfootprintexplorer.digitalfootprintexplorer.util.NEW_WORKER_NAME
import ch.zhaw.init.digitalfootprintexplorer.digitalfootprintexplorer.util.WORKER_NAME
import ch.zhaw.init.digitalfootprintexplorer.digitalfootprintexplorer.worker.DailyFootprintWorker

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

        // Create observers — TrackingService calls register() on both
        displayBrightnessObserver = DisplayBrightnessObserver(this)
        backgroundProcessTracker  = BackgroundProcessTracker(this)

        TrackingService.start(this)

        //cancel old worker in case it was scheduled with a previous version of the app that used WORKER_NAME
        WorkManager.getInstance(this).cancelUniqueWork(WORKER_NAME)

        DailyFootprintWorker.scheduleNext(this)
    }
}
