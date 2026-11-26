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


package ch.zhaw.digitalfootprintexplorer.study

import android.content.ClipData
import android.content.ClipboardManager
import android.content.Context
import android.util.Log
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.text.selection.SelectionContainer
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.ContentCopy
import androidx.compose.material3.Card
import androidx.compose.material3.CardDefaults
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.OutlinedButton
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.text.font.FontFamily
import androidx.compose.ui.unit.dp
import ch.zhaw.digitalfootprintexplorer.R
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.launch

/**
 * Box "Share Data" on the Info tab: shows the generated participant code (to enter in the questionnaires)
 * and a button for the manual upload, the backup for the automatic upload on the upload day.
 */
@Composable
fun ShareDataCard() {
    val context = LocalContext.current
    val scope = rememberCoroutineScope()

    val code = remember { ParticipantCode.getOrCreate(context) }
    val uploadDate = remember { StudyRemoteConfig.uploadDate(context) }
    var lastUploadAt by remember { mutableStateOf(StudyUpload.lastUploadAt(context)) }
    var uploading by remember { mutableStateOf(false) }
    var failed by remember { mutableStateOf(false) }

    Card(
        modifier = Modifier.fillMaxWidth(),
        colors = CardDefaults.cardColors(containerColor = MaterialTheme.colorScheme.surfaceContainer),
        shape = MaterialTheme.shapes.medium
    ) {
        Column(modifier = Modifier.padding(20.dp)) {
            Text(text = stringResource(R.string.study_share_title), style = MaterialTheme.typography.titleMedium)

            Spacer(modifier = Modifier.height(8.dp))

            Text(
                text = stringResource(R.string.study_code_description),
                style = MaterialTheme.typography.bodyMedium,
                color = MaterialTheme.colorScheme.onSurfaceVariant
            )

            Spacer(modifier = Modifier.height(8.dp))

            Row(verticalAlignment = Alignment.CenterVertically) {
                val codeLabel = stringResource(R.string.study_code_label)
                SelectionContainer(modifier = Modifier.weight(1f)) {
                    Text(
                        text = code,
                        modifier = Modifier.semantics { contentDescription = "$codeLabel ${code.toList().joinToString(" ")}" },
                        style = MaterialTheme.typography.headlineSmall,
                        fontFamily = FontFamily.Monospace
                    )
                }
                IconButton(onClick = { copyToClipboard(context, codeLabel, code) }) {
                    Icon(Icons.Default.ContentCopy, contentDescription = stringResource(R.string.study_code_copy))
                }
            }

            Spacer(modifier = Modifier.height(12.dp))

            Text(
                text = if (uploadDate != null) stringResource(R.string.study_upload_auto, uploadDate.toString())
                else stringResource(R.string.study_upload_auto_unknown),
                style = MaterialTheme.typography.bodyMedium,
                color = MaterialTheme.colorScheme.onSurfaceVariant
            )

            Spacer(modifier = Modifier.height(12.dp))

            OutlinedButton(
                modifier = Modifier.fillMaxWidth(),
                enabled = !uploading,
                onClick = {
                    scope.launch {
                        uploading = true
                        failed = false
                        try {
                            StudyUpload.uploadNow(context, StudyUpload.SOURCE_MANUAL)
                            lastUploadAt = StudyUpload.lastUploadAt(context)
                        } catch (e: CancellationException) {
                            throw e
                        } catch (e: Exception) {
                            Log.e(StudyUpload.TAG, "Manual upload failed", e)
                            failed = true
                        } finally {
                            uploading = false
                        }
                    }
                }
            ) {
                if (uploading) {
                    CircularProgressIndicator(
                        modifier = Modifier.padding(end = 8.dp).size(18.dp),
                        strokeWidth = 2.dp
                    )
                }
                Text(stringResource(R.string.study_upload_button))
            }

            if (failed) {
                Spacer(modifier = Modifier.height(8.dp))
                Text(
                    text = stringResource(R.string.study_upload_failed),
                    style = MaterialTheme.typography.bodyMedium,
                    color = MaterialTheme.colorScheme.error
                )
            } else if (lastUploadAt != null) {
                Spacer(modifier = Modifier.height(8.dp))
                Text(
                    text = stringResource(R.string.study_upload_last, lastUploadAt!!),
                    style = MaterialTheme.typography.bodyMedium,
                    color = MaterialTheme.colorScheme.onSurfaceVariant
                )
            }
        }
    }
}

private fun copyToClipboard(context: Context, label: String, text: String) {
    val clipboard = context.getSystemService(Context.CLIPBOARD_SERVICE) as ClipboardManager
    clipboard.setPrimaryClip(ClipData.newPlainText(label, text))
}
