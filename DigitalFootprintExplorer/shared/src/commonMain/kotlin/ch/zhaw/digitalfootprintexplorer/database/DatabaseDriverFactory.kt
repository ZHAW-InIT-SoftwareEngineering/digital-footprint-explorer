package ch.zhaw.digitalfootprintexplorer.database

import app.cash.sqldelight.db.SqlDriver

expect class DatabaseDriverFactory {
    fun createDriver(): SqlDriver
}

fun createDatabase(factory: DatabaseDriverFactory): DFEDatabase =
    DFEDatabase(factory.createDriver())
