# Nutzerstudie 2026

> **Dieser Stand kommt nicht auf `main`.** Die Studienversion wird vom Branch `feat/study` gebaut und ausgerollt. Änderungen aus `main` werden bei Bedarf in diesen Branch gemergt, nie umgekehrt. Fixes, die auch ausserhalb der Studie gebraucht werden, gehören zuerst auf `main`.

Alles, was nur für die Nutzerstudie gebraucht wird, liegt in diesem Ordner. Grundlage ist das Infoblatt `docs/survey-2026-info-sheet.html`.

An der Berechnung, an ihrem Zeitpunkt und an der Baseline des Gartens ändert die Studie nichts. Sie blendet nur Anzeigen aus, schreibt zusätzlich ein Log und lädt die Daten am Ende hoch.

## Was die Studie macht

| Feature | Datei |
|---|---|
| URLs von Config und Upload und das Upload-Secret aus `BuildConfig` | `StudyConfig.kt` |
| Fernsteuerung über die Datei `dfe_config.yaml` auf dem Studienserver (siehe unten) | `StudyRemoteConfig.kt` |
| Survey-Modus ohne Rückmeldung (Garten fest "Stable", kein Statistik-Tab, keine Push-Nachricht) | `StudyPhase.kt` |
| Persönlicher Code, automatisch erzeugt (6 Zeichen ohne 0/O/1/I/L, z. B. K7RX4M) | `ParticipantCode.kt` |
| Studien-Log `study_log.txt` (App-Öffnungen, täglicher Check, Widget hinzugefügt/entfernt, Auslöser jeder Berechnung) | `StudyLog.kt` |
| Täglicher Check von Widget und Benachrichtigungen, eigener periodischer Auftrag `study_daily_check`, fest um 0:30 Uhr (`StudyConfig.DAILY_CHECK_HOUR`/`_MINUTE`). Er lädt auch die Config neu und startet einen fälligen Upload | `StudyDailyCheck.kt` |
| Export als ZIP mit zufälligem Namen | `StudyExport.kt`, `StudyExportFormat.kt` |
| Upload an `fileupload/upload.php`: automatisch ab `upload_date`, manuell als Backup | `StudyUpload.kt` |
| Box "Share Data" im Info-Tab: Code anzeigen und kopieren, Button "Daten jetzt hochladen" | `ShareDataCard.kt` |
| Einziger Einstieg für den übrigen Code | `Study.kt` |

Vor dem Release:

- In `local.properties` (nicht in git) die drei Werte des Studienservers eintragen. Die echten Werte hat das Studienteam, sie stehen absichtlich nirgends im Repository:

  ```properties
  STUDY_CONFIG_URL=https://<server>/<pfad>/dfe_config.yaml
  STUDY_UPLOAD_URL=https://<server>/<pfad>/upload.php
  STUDY_UPLOAD_SECRET=<derselbe Wert wie UPLOAD_SECRET in dfe_uploads/.env auf dem Server>
  ```

  Fehlt ein Wert, baut die App trotzdem, Gradle warnt aber (`STUDY_... missing in local.properties`). Ohne Config-URL lädt die App die Config nie und läuft normal, ohne Upload-URL oder Secret schlägt jeder Upload fehl (`UPLOAD_FAILED reason=no upload URL in this build` bzw. `no upload secret`). Vor dem Release-Build die Warnungen prüfen.
- URLs und Secret stehen damit nicht im Quellcode, sind aber im APK enthalten und lassen sich daraus auslesen, siehe Hinweis in `fileupload/README.md`.

### Versionsnummer (`versionCode`)

- Die Studienversion wird über einen Test-Track im Play Store verteilt und hat dieselbe `applicationId` wie die normale App. Sie ersetzt die normale Version auf dem Gerät, beide gleichzeitig geht nicht.
- Play nimmt nur Bundles mit einem höheren `versionCode` an als jeder bisher hochgeladene, über alle Tracks. Die Studienversion braucht also einen höheren Code als die aktuelle Produktionsversion.
- **Während der Studie darf keine Version mit höherem `versionCode` veröffentlicht werden**, weder von `main` noch auf einem anderen Track. Die Geräte der Teilnehmenden würden sonst auf diese Version aktualisieren, und die Studienfunktionen wären weg.
- Fixes während der Studie kommen als neue Studienversion von `feat/study` mit dem nächsthöheren Code.
- Die erste normale Version nach der Studie braucht einen höheren Code als die letzte Studienversion, sonst bekommen die Teilnehmenden sie nicht.

### Fernsteuerung `dfe_config.yaml`

```yaml
survey: true            # true: Garten fest "Stable", kein Statistik-Tab, keine Push-Nachricht
upload_date: 2026-12-29 # ab diesem Tag lädt die App die Daten einmal selbst hoch
```

- Geladen wird beim Öffnen der App, im täglichen Check um 0:30 und im nächtlichen Worker vor der Push-Nachricht.
- Die zuletzt geladenen Werte bleiben gespeichert. Offline gilt der letzte Stand. Wurde die Datei noch nie geladen, läuft die App im Survey-Modus (`StudyRemoteConfig.SURVEY_DEFAULT` = true, weil diese Version nur für die Studie ausgerollt wird) und lädt nichts automatisch hoch.
- Fehlt ein Schlüssel oder ist der Wert unlesbar, bleibt der letzte Wert.
- Jede Änderung (und das erste Laden) steht als `CONFIG` im Studien-Log. So sieht man, wann jedes Gerät umgeschaltet hat.
- Ändert sich `survey`, wird das Widget sofort neu gezeichnet, die App folgt ohne Neustart.

### Upload

- Geprüft, ob `upload_date` erreicht ist, wird bei jedem Öffnen der App (nach dem Laden der Config) und im täglichen Check um 0:30.
- Automatisch: Ab `upload_date` plant die App einen WorkManager-Auftrag `study_upload`. Er wartet auf Netz und wiederholt bei Netz- und Serverfehlern (exponentiell ab 30 min). Bei 401/413/415 bricht er ab. Nach einem erfolgreichen Upload für dieses Datum passiert nichts mehr. Ein neues `upload_date` startet einen neuen Upload.
- Manuell: Button in der Box "Share Data", beliebig oft. Ein manueller Upload am oder nach `upload_date` zählt auch als erledigt.
- Jeder Versuch steht als `UPLOAD` bzw. `UPLOAD_FAILED` im Studien-Log. Das ZIP wird nach dem Versuch gelöscht.
- Wiederholte Studie: Gesperrt wird nur ein Upload für dasselbe `upload_date`. Mit einem neuen `upload_date` lädt dieselbe Installation wieder hoch. Code und Studien-Log bleiben dabei auf dem Gerät erhalten, das neue ZIP enthält also auch die Daten der ersten Studie und denselben Code. Nach einer Neuinstallation gibt es einen neuen Code und ein leeres Log.
- Der Server gibt jeder Datei einen eigenen Zufallsnamen. Wer mehrfach hochlädt, hat mehrere ZIPs; der Code steht in den Dateinamen im ZIP, für die Auswertung zählt das neueste.

**Inhalt des ZIP:** Das ZIP hat einen zufälligen Namen. Jede Datei darin trägt den Code vor der Endung, z. B. `daily_values-K7RX4M.csv`. So bleiben die Dateien einer Person zugeordnet.

- `daily_values.csv`: eine Zeile pro gespeichertem Tag mit `date, app_usage_kg, display_kg, background_kg, total_kg, garden_state, baseline_kg, calculated_at`. `background_kg` umfasst GPS und Bluetooth. `garden_state` ist der berechnete Zustand, auch im Survey-Modus. Danach eine Spalte pro App-Kategorie aus `DailyEmissionCategory`, z. B. `video_streaming_kg`: immer alle Werte von `AppCategory` in derselben Reihenfolge, 0 wenn für den Tag nichts gespeichert ist. Gespeicherte Kategorien, die es im Enum nicht (mehr) gibt, kommen als zusätzliche Spalten ans Ende.
- `app_opens_per_day.csv`: eine Zeile pro Tag vom ersten Öffnen der Studienversion bis zum Export mit `date, opens` (Anzahl Öffnungen, 0 = nicht geöffnet). Ohne ein einziges Öffnen nur die Kopfzeile. Gezählt wird in den Einstellungen `dfe_study_opens`, nicht im Log.
- `study_log.txt`: das ganze Studien-Log (inkl. `CODE_CREATED`, `CONFIG`, `UPLOAD`, `UPLOAD_FAILED`). Dazu jede Zeile des Worker-Debug-Logs mit Präfix `WORKER_` (z. B. `WORKER_RUN_START`, `WORKER_RUN_SKIPPED`, `WORKER_RUN_STOPPED`, `WORKER_NEXT_RUN_PINNED`, `WORKER_PROCESS_EXIT`), jeweils mit Gerätezustand (Standby-Bucket, Akku-Optimierung, Energiesparmodus, Doze). So sieht man pro Person, ob und wann der nächtliche Worker lief. Nächte ohne `WORKER_RUN_START` sind Nächte, in denen er nicht lief.

App-Namen (`DailyEmissionApp`) werden nicht exportiert.

**Definition "App geöffnet":** Die App kommt in den Vordergrund (`MainActivity.onStart`). Ein Neuaufbau durch Drehen, Dark Mode oder Sprachwechsel zählt nicht. Die Rückkehr aus einer anderen App, z. B. aus den Einstellungen, zählt als Öffnung. Jede Öffnung erhöht den Zähler des Kalendertags (Ortszeit des Geräts). Ins Log kommt nur die erste Öffnung des Tages als `APP_OPEN`, mit ihrem Zeitpunkt.

## Einstiegspunkte im übrigen Code

Jede Stelle ist mit `// STUDY:` (Kotlin) oder `<!-- STUDY: -->` (XML) markiert. Alle findet man mit:

```bash
grep -rn "STUDY:" apps/android/src
```

| Datei | Was dort passiert |
|---|---|
| `DFEApplication.kt` | Hält `database` für den Export, plant den täglichen Check und erzeugt den Code (`Study.onProcessStart`) |
| `MainActivity.kt` | `onStart`/`onStop` melden die App-Öffnung; dabei werden auch Config geladen und ein fälliger Upload geplant |
| `App.kt` | `studyBaseline` (Survey-Modus): blendet den Statistik-Tab aus, Garten auf der Startseite fest "Stable" |
| `ui/screen/InfoScreen.kt` | Zeigt die Box "Share Data" |
| `widget/GardenWidget.kt` | Widget zeigt im Survey-Modus "Stable" |
| `widget/GardenWidgetReceiver.kt` | `onEnabled`/`onDeleted` loggen Widget hinzugefügt/entfernt |
| `worker/WorkerRunLog.kt` | Jede Zeile des Debug-Logs geht auch ins Studien-Log (`Study.onWorkerLog`) |
| `worker/DailyFootprintWorker.kt` | Loggt Tag und Auslöser nach dem Speichern, keine Push-Nachricht im Survey-Modus. `doWorkInternal` bekommt dafür den Auslöser als Parameter |
| `AndroidManifest.xml` | Berechtigung `INTERNET` für Config und Upload |
| `build.gradle.kts` | `BuildConfig.STUDY_UPLOAD_SECRET` aus `local.properties` |
| `res/values/strings_study.xml`, `res/values-de/strings_study.xml` | Texte |

## Nach der Studie

Der Branch `feat/study` bleibt, wie er ist. Alles passiert auf `main`.

Die Teilnehmenden behalten die Studienversion, auch wenn sie das Testprogramm verlassen, weil Android nicht auf einen tieferen `versionCode` zurückgeht. Erst eine neue Produktionsversion von `main` bringt sie wieder auf die normale App. Ihre Daten (Verlauf, Baseline des Gartens) bleiben dabei erhalten.

1. **Auf `main` zwei Zeilen in `DFEApplication.onCreate` einfügen:**
   ```kotlin
   // Removes the jobs of the study version 2026 from devices that ran it, see feat/study study/README.md
   WorkManager.getInstance(this).cancelUniqueWork("study_daily_check")
   WorkManager.getInstance(this).cancelUniqueWork("study_upload")
   ```
   Ohne diese Zeilen bleiben die beiden Aufträge auf den Geräten geplant. `main` kennt ihre Klassen nicht, WorkManager meldet jede Nacht einen Fehler und weckt das Gerät für nichts. Die App läuft trotzdem normal, auch der nächtliche Worker. Auf Geräten ohne Studienversion tun die Zeilen nichts. Mindestens eine Version lang behalten.
2. **Auf `main` den `versionCode` in `apps/android/build.gradle.kts` erhöhen**, über den der letzten Studienversion. Sonst bekommen die Teilnehmenden das Update nicht.
3. Von `main` bauen (nicht von `feat/study`) und in die Produktion hochladen.
4. In der Play Console den Test-Track der Studie beenden und die Liste der Testpersonen (E-Mail-Adressen) löschen.

Auf den Geräten bleiben `files/study_log.txt` und die Einstellungen `dfe_study` und `dfe_study_opens` liegen, bis die App deinstalliert wird. Sie stören nicht.

## Studie wiederholen

Der Stand liegt auf dem Branch `feat/study`. Nach der Studie am besten mit einem Tag sichern (z. B. `study-2026`). Für eine neue Studie von `feat/study` einen neuen Branch erstellen und `main` hineinmergen. `upload_date`, `versionCode` und Infoblatt neu prüfen.
