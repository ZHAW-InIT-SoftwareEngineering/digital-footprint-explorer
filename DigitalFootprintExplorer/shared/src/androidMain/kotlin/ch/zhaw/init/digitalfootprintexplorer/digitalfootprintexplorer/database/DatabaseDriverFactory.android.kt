package ch.zhaw.init.digitalfootprintexplorer.digitalfootprintexplorer.database

import android.content.Context
import app.cash.sqldelight.db.SqlDriver
import app.cash.sqldelight.driver.android.AndroidSqliteDriver

actual class DatabaseDriverFactory(private val context: Context) {
    actual fun createDriver(): SqlDriver =
        AndroidSqliteDriver(DFEDatabase.Schema, context, "dfe.db")
}
