# Nutzerstudie 2026

Alles, was nur für die Nutzerstudie gebraucht wird, liegt in diesem Ordner. Grundlage ist das Infoblatt `docs/survey-2026-info-sheet.html`.

An der Berechnung, an ihrem Zeitpunkt und an der Baseline des Gartens ändert die Studie nichts. Sie blendet nur Anzeigen aus und schreibt zusätzlich ein Log.

## Was die Studie macht

| Feature | Datei |
|---|---|
| Startdatum, Empfängeradresse | `StudyConfig.kt` |
| Baseline-Phase: Tag 1 bis 7 ohne Rückmeldung (Garten fest "Stable", kein Statistik-Tab, keine Push-Nachricht) | `StudyPhase.kt` |
| Persönlicher Code (2 Buchstaben, 4 Ziffern, z. B. MA0732) | `ParticipantCode.kt` |
| Studien-Log `study_log.txt` (App-Öffnungen, täglicher Check, Widget hinzugefügt/entfernt, Auslöser jeder Berechnung) | `StudyLog.kt` |
| Täglicher Check von Widget und Benachrichtigungen, eigener periodischer Auftrag `study_daily_check`, fest um 0:30 Uhr (`StudyConfig.DAILY_CHECK_HOUR`/`_MINUTE`). Er zeichnet auch das Widget neu, damit es an Tag 8 gleich nach Mitternacht umschaltet | `StudyDailyCheck.kt` |
| Export als `dfe-<code>.zip` per Mail an das Studienteam | `StudyExport.kt`, `StudyExportFormat.kt` |
| Box "Share Data" im Info-Tab | `ShareDataCard.kt` |
| Einziger Einstieg für den übrigen Code | `Study.kt` |

Vor dem Release `StudyConfig.START_DATE` auf den echten Studienstart setzen. Tage vor dem Start zählen ebenfalls als Baseline.

**Inhalt des ZIP:** Jede Datei trägt den Code vor der Endung, z. B. `daily_values-MA0732.csv`. So bleiben die Dateien auch nach dem Entpacken einer Person zugeordnet.

- `daily_values.csv`: eine Zeile pro gespeichertem Tag mit `date, app_usage_kg, display_kg, background_kg, total_kg, garden_state, baseline_kg, calculated_at`. `background_kg` umfasst GPS und Bluetooth. `garden_state` ist der berechnete Zustand, auch in der Baseline-Phase.
- `app_opens_per_day.csv`: eine Zeile pro Tag vom Studienstart bis zum Export mit `date, opens` (Anzahl Öffnungen, 0 = nicht geöffnet). Tage vor dem Start, an denen die App geöffnet wurde, stehen ebenfalls drin. Gezählt wird in den Einstellungen `dfe_study_opens`, nicht im Log.
- `study_log.txt`: das ganze Studien-Log.

Werte pro Kategorie und App-Namen werden nicht exportiert.

**Definition "App geöffnet":** Die App kommt in den Vordergrund (`MainActivity.onStart`). Ein Neuaufbau durch Drehen, Dark Mode oder Sprachwechsel zählt nicht. Die Rückkehr aus einer anderen App, z. B. aus den Einstellungen, zählt als Öffnung. Jede Öffnung erhöht den Zähler des Kalendertags (Ortszeit des Geräts). Ins Log kommt nur die erste Öffnung des Tages als `APP_OPEN`, mit ihrem Zeitpunkt.

## Einstiegspunkte im übrigen Code

Jede Stelle ist mit `// STUDY:` (Kotlin) oder `<!-- STUDY: -->` (XML) markiert. Alle findet man mit:

```bash
grep -rn "STUDY:" apps/android/src
```

| Datei | Was dort passiert |
|---|---|
| `DFEApplication.kt` | Hält `database` für den Export, plant den täglichen Check (`Study.onProcessStart`) |
| `MainActivity.kt` | `onStart`/`onStop` melden die App-Öffnung |
| `App.kt` | `studyBaseline`: blendet den Statistik-Tab aus, Garten auf der Startseite fest "Stable" |
| `ui/screen/InfoScreen.kt` | Zeigt die Box "Share Data" |
| `widget/GardenWidget.kt` | Widget zeigt in der Baseline "Stable" |
| `widget/GardenWidgetReceiver.kt` | `onEnabled`/`onDeleted` loggen Widget hinzugefügt/entfernt |
| `worker/DailyFootprintWorker.kt` | Loggt Tag und Auslöser nach dem Speichern, keine Push-Nachricht in der Baseline. `doWorkInternal` bekommt dafür den Auslöser als Parameter |
| `AndroidManifest.xml` | FileProvider für das ZIP |
| `res/xml/study_file_paths.xml` | Pfad des ZIP für den FileProvider |
| `res/values/strings_study.xml`, `res/values-de/strings_study.xml` | Texte |

## Nach der Studie

Für beide Varianten braucht es eine neue Version im Play Store (`versionCode` erhöhen).

### Variante A: nur ausblenden

Die Baseline-Phase endet über das Startdatum von selbst nach Tag 7. Sichtbar bleibt danach nur die Box "Share Data".

1. In `ui/screen/InfoScreen.kt` die zwei Zeilen unter `// STUDY: participant code and export by mail` entfernen (`Spacer` und `ShareDataCard()`).
2. Optional den täglichen Check stoppen: In `DFEApplication.kt` `Study.onProcessStart(this)` ersetzen durch
   `WorkManager.getInstance(this).cancelUniqueWork("study_daily_check")`.

Das Studien-Log wird dann nur noch bei App-Öffnungen, Widget-Änderungen und Berechnungen ergänzt. Es bleibt lokal auf dem Gerät.

### Variante B: ganz entfernen

1. An allen `STUDY:`-Stellen aus der Tabelle oben den Studien-Code entfernen:
   - In `App.kt` den Statistik-Tab wieder ohne `if (!studyBaseline)` einfügen und `GardenStateCard(gardenState)` aufrufen.
   - In `GardenWidget.kt` wieder `GardenContent(state)` aufrufen.
   - Im Worker wieder `showDailyFootprintNotification(gardenState)` ohne Bedingung aufrufen.
   - Den `database`-Property in `DFEApplication.kt` nur entfernen, wenn ihn sonst niemand mehr braucht.
2. In `DFEApplication.onCreate` den geplanten Check auf den Geräten abbrechen, sonst läuft er nach dem Update weiter und findet seine Klasse nicht mehr:
   ```kotlin
   WorkManager.getInstance(this).cancelUniqueWork("study_daily_check")
   ```
   Diese Zeile mindestens eine Version lang behalten.
3. Den Provider-Eintrag im Manifest, `res/xml/study_file_paths.xml` und die beiden `strings_study.xml` löschen.
4. Den Ordner `study` löschen, auch die Tests in `androidUnitTest/.../study`.
5. Prüfen: Beide Suchen dürfen nichts mehr finden, danach muss die App bauen.
   ```bash
   grep -rn "STUDY:" apps/android/src
   ```
   ```bash
   grep -rn "\.study\." apps/android/src
   ```

Auf den Geräten bleiben `files/study_log.txt` und die Einstellungen `dfe_study` und `dfe_study_opens` liegen, bis die App deinstalliert wird. Sie stören nicht, auf Wunsch kann man sie beim Start einmal löschen.

## Studie wiederholen

Der Stand liegt auf dem Branch `feat/study`. Nach dem Entfernen am besten mit einem Tag sichern (z. B. `study-2026`). So lässt sich der Ordner später zurückholen. Startdatum und Infoblatt dann neu prüfen.
