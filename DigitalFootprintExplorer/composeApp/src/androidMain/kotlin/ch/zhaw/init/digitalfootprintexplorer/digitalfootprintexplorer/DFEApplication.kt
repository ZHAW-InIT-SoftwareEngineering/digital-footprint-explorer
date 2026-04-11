package ch.zhaw.init.digitalfootprintexplorer.digitalfootprintexplorer

import android.app.Application
import ch.zhaw.init.digitalfootprintexplorer.digitalfootprintexplorer.database.DatabaseDriverFactory
import ch.zhaw.init.digitalfootprintexplorer.digitalfootprintexplorer.database.createDatabase
import ch.zhaw.init.digitalfootprintexplorer.digitalfootprintexplorer.model.GardenStateCalculator

/**
 * Application entry point.
 * Initializes the SQLDelight database and the [GardenStateCalculator],
 * which serves as the app-wide instance for calculating the garden state.
 */
class DFEApplication : Application() {

    lateinit var gardenStateCalculator: GardenStateCalculator
        private set

    override fun onCreate() {
        super.onCreate()
        val db = createDatabase(DatabaseDriverFactory(this))
        gardenStateCalculator = GardenStateCalculator(db)
    }
}
