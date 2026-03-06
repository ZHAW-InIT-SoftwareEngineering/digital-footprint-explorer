package ch.zhaw.init.digitalfootprintexplorer.digitalfootprintexplorer

class Greeting {
    private val platform = getPlatform()

    fun greet(): String {
        return "Hello, ${platform.name}!"
    }
}