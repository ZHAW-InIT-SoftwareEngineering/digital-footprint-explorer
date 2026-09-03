/*
 * Copyright (C) 2026 Zurich University of Applied Sciences, Switzerland
 *
 * This program is free software: you can redistribute it and/or modify
 * it under the terms of the GNU Affero General Public License as published by
 * the Free Software Foundation, either version 3 of the License, or
 * (at your option) any later version.
 *
 * This program is distributed in the hope that it will be useful,
 * but WITHOUT ANY WARRANTY; without even the implied warranty of
 * MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
 * GNU Affero General Public License for more details.
 *
 * You should have received a copy of the GNU Affero General Public License
 * along with this program.  If not, see <https://www.gnu.org/licenses/>.
 */

package ch.zhaw.digitalfootprintexplorer.servicelayerplatform.datasource

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