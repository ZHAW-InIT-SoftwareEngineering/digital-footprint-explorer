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

/**
 * Package names per category. Takes precedence over the category an app declares itself in its
 * manifest, because many apps (e.g. YouTube) do not declare one. Keys are mapped to
 * [ch.zhaw.digitalfootprintexplorer.model.AppCategory] in `InstalledAppProvider`.
 */
val APP_CATEGORY_CONFIG: Map<String, List<String>> = mapOf(
    "AI" to listOf(
        "com.openai.chatgpt",
        "com.microsoft.copilot",
        "ai.perplexity.app.android",
        "com.google.android.apps.gemini",
        "com.google.android.apps.bard",
        "com.deepseek.chat",
        "com.anthropic.claude"
    ),
    "Mail" to listOf(
        "com.google.android.gm",
        "com.google.android.gm.lite",
        "com.microsoft.office.outlook",
        "ch.protonmail.android",
        "com.yahoo.mobile.client.android.mail",
        "com.fsck.k9",
        "de.tutao.tutanota",
        "com.samsung.android.email.provider"
    ),
    "Messaging" to listOf(
        "com.whatsapp",
        "com.whatsapp.w4b",
        "org.telegram.messenger",
        "com.facebook.orca",
        "jp.naver.line.android",
        "com.kakao.talk",
        "org.thoughtcrime.securesms",
        "ch.threema.app",
        "com.viber.voip",
        "com.discord",
        "com.google.android.apps.messaging",
        "com.samsung.android.messaging"
    ),
    "Video_Call" to listOf(
        "com.recommended.videocall",
        "us.zoom.videomeetings",
        "com.microsoft.teams",
        "com.google.android.apps.tachyon",
        "com.skype.raider",
        "com.cisco.webex.meetings",
        "org.jitsi.meet"
    ),
    "Video" to listOf(
        "com.google.android.youtube",
        "com.google.android.apps.youtube.kids",
        "com.google.android.videos",
        "com.netflix.mediaclient",
        "com.disney.disneyplus",
        "com.amazon.avod.thirdpartyclient",
        "tv.twitch.android.app",
        "com.samsung.android.tvplus",
        "com.apple.atve.androidtv.appletv",
        "com.vimeo.android.videoapp",
        "com.plexapp.android"
    ),
    "Audio" to listOf(
        "com.spotify.music",
        "com.google.android.apps.youtube.music",
        "com.apple.android.music",
        "deezer.android.app",
        "com.soundcloud.android",
        "com.aspiro.tidal",
        "com.amazon.mp3",
        "com.audible.application",
        "com.google.android.apps.podcasts"
    ),
    "Social" to listOf(
        "com.instagram.android",
        "com.instagram.barcelona",
        "com.facebook.katana",
        "com.facebook.lite",
        "com.zhiliaoapp.musically",
        "com.ss.android.ugc.trill",
        "com.snapchat.android",
        "com.twitter.android",
        "com.reddit.frontpage",
        "com.linkedin.android",
        "com.pinterest",
        "com.tumblr",
        "com.bereal.ft"
    ),
    "Navigation" to listOf(
        "com.google.android.apps.maps",
        "com.waze",
        "ch.sbb.mobile.android.b2c",
        "com.here.app.maps",
        "de.komoot.android",
        "com.sygic.aura"
    ),
    "Gaming" to listOf(
        "com.supercell.clashroyale",
        "com.supercell.clashofclans",
        "com.supercell.brawlstars",
        "com.king.candycrushsaga",
        "com.mojang.minecraftpe",
        "com.roblox.client",
        "com.activision.callofduty.shooter",
        "com.innersloth.spacemafia"
    )
)
