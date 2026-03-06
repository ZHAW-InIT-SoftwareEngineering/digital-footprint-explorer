package ch.zhaw.init.digitalfootprintexplorer.digitalfootprintexplorer

interface Platform {
    val name: String
}

expect fun getPlatform(): Platform