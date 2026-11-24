# File upload endpoint

`upload.php` accepts a ZIP file over HTTP POST (for example from the Android app) and saves it on the server. `tests.sh` checks the endpoint with `curl`.

## How `upload.php` works

The script expects a `multipart/form-data` POST request. The file must be in a form field named `file`, and the shared secret must be in an `X-API-Key` header. It runs these checks in order and stops at the first one that fails:

| Step | Check | Response on failure |
|------|-------|---------------------|
| 1 | The `X-API-Key` header matches the shared secret | `401 Unauthorized` |
| 2 | A file was sent in the field `file`, and PHP received it without errors | `400 Upload error` |
| 3 | The file is no larger than 10 MB | `413 Too large` |
| 4 | The file's content is really a ZIP. PHP's `finfo` reads the file's first bytes, so the filename and the client's stated content type don't count | `415 Not a ZIP` |
| 5 | The file is moved to the upload folder | `500 Save failed` |

If every check passes, the response is `200` with a JSON body:

```json
{"status":"ok","file":"3f9c...e1a.zip"}
```

### Where files are stored

Uploaded files go to `dfe_uploads/`, two levels above the folder that contains `upload.php` (`__DIR__ . '/../../dfe_uploads/'`). This folder should be outside the web root so uploaded files can't be downloaded or run through the web server. The folder must exist, and the web server's user must be able to write to it. Otherwise step 5 fails with a 500.

The server gives each file a random 32-character hex name, such as `3f9c...e1a.zip`. The name the client sends is ignored, so a client can't overwrite existing files or choose where a file is saved.

### Server requirements

- PHP with the `fileinfo` extension, which is enabled by default in most installations.
- In `php.ini`, `upload_max_filesize` and `post_max_size` must be at least 10 MB. If an upload exceeds these limits, PHP drops it before the script runs, and the script returns `400`.
- Serve the endpoint over HTTPS only, because the secret is sent in a header.

### The shared secret

The secret is read from a file named `.env` in the upload folder (`dfe_uploads/.env`). It is not stored in the script itself, and it doesn't come from a server environment variable. Because the folder is outside the web root, nobody can download the file through a URL. Uploaded files get random `.zip` names, so they can never overwrite `.env`.

```ini
# dfe_uploads/.env
UPLOAD_SECRET="long-random-string"
```

- Put the value in quotes. Without them, PHP's `parse_ini_file` treats some characters (`!`, `;`, `=`) and words (`yes`, `none`) specially. You can generate a secret with `openssl rand -hex 32`.
- If the file is missing, unreadable, or has no `UPLOAD_SECRET`, the script rejects every request with `500 Server misconfigured` and writes a message to the PHP error log. It never accepts uploads without a secret.
- The key is compared with `hash_equals`, which takes the same time whether the guess is close or not. This stops attackers from guessing the secret by measuring response times.
- Don't commit `.env` to git. If your host allows it, set its permissions to `600` or `640`.

## Using the endpoint from Android

The Android app uploads a ZIP the same way `tests.sh` does: it sends a `multipart/form-data` POST with the file in a field named `file` and the secret in an `X-API-Key` header. The examples below use [OkHttp](https://square.github.io/okhttp/) and Kotlin.

### 1. Setup

Add OkHttp to the app's `build.gradle.kts`:

```kotlin
dependencies {
    implementation("com.squareup.okhttp3:okhttp:4.12.0")
}
```

Add the internet permission to `AndroidManifest.xml`:

```xml
<uses-permission android:name="android.permission.INTERNET" />
```

The endpoint must use HTTPS. Since Android 9, apps block plain-HTTP requests unless you configure an exception, and the secret should never travel unencrypted anyway.

### 2. Providing the secret to the app

Don't write the secret directly into the source code. One option is to keep it in `local.properties`, which isn't committed to git, and expose it to the app through `BuildConfig`:

```properties
# local.properties
UPLOAD_SECRET=your-secret
UPLOAD_URL=https://example.com/upload.php
```

```kotlin
// app/build.gradle.kts
import java.util.Properties

val localProps = Properties().apply {
    rootProject.file("local.properties").takeIf { it.exists() }?.inputStream()?.use { load(it) }
}

android {
    buildFeatures { buildConfig = true }
    defaultConfig {
        buildConfigField("String", "UPLOAD_SECRET", "\"${localProps["UPLOAD_SECRET"] ?: ""}\"")
        buildConfigField("String", "UPLOAD_URL", "\"${localProps["UPLOAD_URL"] ?: ""}\"")
    }
}
```

> **Note:** This keeps the secret out of the repository, but it is still compiled into the APK, and anyone who has the app can extract it. A shared secret is fine for a prototype or a study with a known group of participants. For a public release, use per-user authentication instead, such as tokens issued after login.

### 3. Uploading a file

```kotlin
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext
import okhttp3.MediaType.Companion.toMediaType
import okhttp3.MultipartBody
import okhttp3.OkHttpClient
import okhttp3.Request
import okhttp3.RequestBody.Companion.asRequestBody
import org.json.JSONObject
import java.io.File
import java.io.IOException
import java.util.concurrent.TimeUnit

object ZipUploader {

    private val client = OkHttpClient.Builder()
        .connectTimeout(30, TimeUnit.SECONDS)
        .writeTimeout(120, TimeUnit.SECONDS)   // allow time for slow mobile uploads
        .readTimeout(30, TimeUnit.SECONDS)
        .build()

    /** Uploads [zip] and returns the file name the server assigned. */
    suspend fun upload(zip: File): String = withContext(Dispatchers.IO) {
        val body = MultipartBody.Builder()
            .setType(MultipartBody.FORM)
            .addFormDataPart(
                "file",                                   // must match $_FILES['file']
                zip.name,
                zip.asRequestBody("application/zip".toMediaType())
            )
            .build()

        val request = Request.Builder()
            .url(BuildConfig.UPLOAD_URL)
            .header("X-API-Key", BuildConfig.UPLOAD_SECRET)
            .post(body)
            .build()

        client.newCall(request).execute().use { resp ->
            val text = resp.body?.string().orEmpty()
            when (resp.code) {
                200  -> JSONObject(text).getString("file")
                401  -> throw IOException("Wrong or missing upload secret")
                413  -> throw IOException("File larger than 10 MB")
                415  -> throw IOException("File is not a valid ZIP")
                else -> throw IOException("Upload failed (${resp.code}): $text")
            }
        }
    }
}
```

Call it from a coroutine, for example in a `ViewModel`:

```kotlin
viewModelScope.launch {
    try {
        val serverName = ZipUploader.upload(File(context.filesDir, "data.zip"))
        // success: serverName is the name the file was saved under
    } catch (e: IOException) {
        // show an error, or retry later
    }
}
```

Network calls aren't allowed on Android's main thread. `withContext(Dispatchers.IO)` moves the upload to a background thread.

### 4. Uploads that should survive the app closing (optional)

An upload started from a `ViewModel` stops if the user leaves the app. If uploads must finish reliably, for example when a study participant submits data, use [WorkManager](https://developer.android.com/topic/libraries/architecture/workmanager). It waits for a network connection and retries failed uploads automatically:

```kotlin
// implementation("androidx.work:work-runtime-ktx:<version>")

class UploadWorker(ctx: Context, params: WorkerParameters) : CoroutineWorker(ctx, params) {
    override suspend fun doWork(): Result {
        val path = inputData.getString("path") ?: return Result.failure()
        return try {
            ZipUploader.upload(File(path))
            Result.success()
        } catch (e: IOException) {
            // Don't retry errors that won't go away on their own
            if (e.message?.contains("not a valid ZIP") == true ||
                e.message?.contains("larger than") == true ||
                e.message?.contains("secret") == true) Result.failure()
            else Result.retry()
        }
    }
}

val request = OneTimeWorkRequestBuilder<UploadWorker>()
    .setInputData(workDataOf("path" to zipFile.absolutePath))
    .setConstraints(Constraints.Builder().setRequiredNetworkType(NetworkType.CONNECTED).build())
    .build()
WorkManager.getInstance(context).enqueue(request)
```

### Server responses the app should handle

| Code | Meaning | What the app should do |
|------|---------|------------------------|
| `200` | Saved. The JSON `file` field holds the server-side name | Mark the upload as done |
| `400` | No file received, or the upload was cut off | Retry |
| `401` | Wrong secret | Don't retry. The app's configuration is wrong |
| `413` | File larger than 10 MB | Don't retry. Split or compress the data, or raise the server limit |
| `415` | Not a ZIP | Don't retry. Check how the app creates the ZIP |
| `500` | Server couldn't save the file | Retry later |

## Running the tests

### Prerequisites

- `curl`
- `upload.php` deployed on a server you can reach
- The test files in `test_files/`:
  - `test.zip`: a valid ZIP archive
  - `text.txt`: a plain text file, which should be rejected

### Configuration

1. The tests send requests to `https://example.com/upload.php`, which is written into `tests.sh`. Replace it with your server's URL in all three `curl` lines.
2. Set the shared secret as an environment variable. The script refuses to run without it:

   ```
   Error: environment variable UPLOAD_SECRET is not set.
   ```

### Running

Run the script from this folder, because it finds the test files through the relative path `./test_files/`:

```bash
cd fileupload
UPLOAD_SECRET='your-secret' ./tests.sh
```

### What the tests check

The script makes three requests and prints each response, including the status line and headers (`curl -i`). It doesn't decide pass or fail itself, so check the status codes in the output:

| # | Request | Expected result |
|---|---------|-----------------|
| 1 | Upload `test.zip` with the correct key | `HTTP/... 200` and `{"status":"ok","file":"…zip"}` |
| 2 | Upload `text.txt` with the correct key | `HTTP/... 415` and `Not a ZIP` |
| 3 | Upload `test.zip` without a key | `HTTP/... 401` and `Unauthorized` |

After test 1 succeeds, a new `.zip` file should appear in `dfe_uploads/` on the server.

### Troubleshooting

| Symptom | Likely cause |
|---------|--------------|
| Test 1 returns `401` | The `UPLOAD_SECRET` you set doesn't match the value in `dfe_uploads/.env` on the server |
| Every test returns `500 Server misconfigured` | `dfe_uploads/.env` is missing, unreadable, or has no `UPLOAD_SECRET` |
| Test 1 returns `400` | The file exceeds `upload_max_filesize` or `post_max_size`, or the form field isn't named `file` |
| Test 1 returns `500` | `dfe_uploads/` doesn't exist or the web server can't write to it |
| `curl: (26) Failed to open/read local data` | The script wasn't run from the `fileupload` folder, or a test file is missing |
| `curl: (60) SSL certificate problem` | The test server uses a self-signed certificate. For local testing only, add `-k` to the `curl` calls |
