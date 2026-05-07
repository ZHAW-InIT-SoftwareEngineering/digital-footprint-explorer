package ch.zhaw.digitalfootprintexplorer

interface Platform {
    val name: String
}

expect fun getPlatform(): Platform