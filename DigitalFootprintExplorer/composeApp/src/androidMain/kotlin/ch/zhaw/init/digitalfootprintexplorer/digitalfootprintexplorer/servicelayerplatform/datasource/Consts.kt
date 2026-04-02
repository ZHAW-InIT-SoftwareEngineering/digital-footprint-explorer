package ch.zhaw.init.digitalfootprintexplorer.digitalfootprintexplorer.servicelayerplatform.datasource

val APP_CATEGORY_CONFIG: Map<String, List<String>> = mapOf(
    "AI" to listOf(
        "com.openai.chatgpt",
        "com.microsoft.copilot",
        "ai.perplexity.app.android",
        "com.google.android.apps.gemini",
        "com.google.android.apps.bard",
        "com.deepseek.chat"
    ),
    "Mail" to listOf(
        "com.google.android.gm",
        "com.microsoft.office.outlook"
    ),
    "Messaging" to listOf(
        "com.whatsapp",
        "com.whatsapp.w4b",
        "org.telegram.messenger",
        "com.facebook.orca",
        "jp.naver.line.android",
        "com.kakao.talk",
        "org.thoughtcrime.securesms"
    ),
    "Video_Call" to listOf(
        "com.recommended.videocall"
    )
)