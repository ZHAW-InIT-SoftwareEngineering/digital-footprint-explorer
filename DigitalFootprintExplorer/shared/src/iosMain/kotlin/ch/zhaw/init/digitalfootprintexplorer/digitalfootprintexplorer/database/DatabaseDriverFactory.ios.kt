package ch.zhaw.init.digitalfootprintexplorer.digitalfootprintexplorer.database

import app.cash.sqldelight.db.SqlDriver
import app.cash.sqldelight.driver.native.NativeSqliteDriver

actual class DatabaseDriverFactory {
    actual fun createDriver(): SqlDriver =
        NativeSqliteDriver(DFEDatabase.Schema, "dfe.db")
}
