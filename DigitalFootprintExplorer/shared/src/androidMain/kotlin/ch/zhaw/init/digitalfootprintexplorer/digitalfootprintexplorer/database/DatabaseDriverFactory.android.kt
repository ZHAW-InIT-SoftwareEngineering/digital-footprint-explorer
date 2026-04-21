package ch.zhaw.init.digitalfootprintexplorer.digitalfootprintexplorer.database

import android.content.Context
import androidx.sqlite.db.SupportSQLiteDatabase
import app.cash.sqldelight.db.SqlDriver
import app.cash.sqldelight.driver.android.AndroidSqliteDriver

actual class DatabaseDriverFactory(private val context: Context) {
    actual fun createDriver(): SqlDriver =
        AndroidSqliteDriver(
            schema = DFEDatabase.Schema,
            context = context,
            name = "dfe.db",
            callback = object : AndroidSqliteDriver.Callback(DFEDatabase.Schema) {
                override fun onOpen(db: SupportSQLiteDatabase) {
                    db.execSQL("PRAGMA foreign_keys = ON")
                }
            }
        )
}
