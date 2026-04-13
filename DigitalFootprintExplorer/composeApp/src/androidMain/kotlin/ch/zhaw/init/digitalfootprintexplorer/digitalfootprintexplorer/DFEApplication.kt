package ch.zhaw.init.digitalfootprintexplorer.digitalfootprintexplorer

import android.app.Application
import ch.zhaw.init.digitalfootprintexplorer.digitalfootprintexplorer.database.DatabaseDriverFactory
import ch.zhaw.init.digitalfootprintexplorer.digitalfootprintexplorer.database.createDatabase
import ch.zhaw.init.digitalfootprintexplorer.digitalfootprintexplorer.model.GardenStateCalculator
import ch.zhaw.init.digitalfootprintexplorer.digitalfootprintexplorer.servicelayerplatform.service.BackgroundProcessTracker
import ch.zhaw.init.digitalfootprintexplorer.digitalfootprintexplorer.servicelayerplatform.service.DisplayBrightnessObserver
import ch.zhaw.init.digitalfootprintexplorer.digitalfootprintexplorer.worker.DailyFootprintWorker

/**
 * Application entry point.
 *
 * Initialises:
 *  - SQLDelight database and [GardenStateCalculator]
 *  - [DisplayBrightnessObserver] to track screen-brightness intervals across the day
 *  - [BackgroundProcessTracker] to track GPS/Bluetooth active durations
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

        displayBrightnessObserver = DisplayBrightnessObserver(this).also { it.register() }
        backgroundProcessTracker  = BackgroundProcessTracker(this).also  { it.register() }

        DailyFootprintWorker.schedule(this)
    }
}
