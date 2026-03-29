package ch.zhaw.init.digitalfootprintexplorer.digitalfootprintexplorer.servicelayerplatform.datasource

import android.content.Context
import org.json.JSONObject

class AppCategoryConfigLoader {
    fun load(context: Context): Map<String, List<String>> {
        val jsonString = context.assets
            .open("app_categories.json")
            .bufferedReader()
            .use { it.readText() }

        val json = JSONObject(jsonString)
        val result = mutableMapOf<String, List<String>>()
        json.keys().forEach { key ->
            val array = json.getJSONArray(key)
            val list = mutableListOf<String>()

            for (i in 0 until array.length()) {
                list.add(array.getString(i))
            }

            result[key] = list
        }
        return result
    }
}