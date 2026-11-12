# Digital Footprint Explorer

Digital Footprint Explorer (DFE) is a research app from the Zurich University of Applied Sciences (ZHAW). It estimates the greenhouse gas emissions linked to everyday phone use. A digital garden helps users see how their estimates change over time. Android and iPhone share the same Kotlin model and use the activity each platform makes available.

| Android | iPhone |
| --- | --- |
| Available on [Google Play](https://play.google.com/store/apps/details?id=ch.zhaw.digitalfootprintexplorer). Includes a garden, daily statistics and a Home Screen widget. | In testing. Includes Today, History, small and medium Home Screen widgets, optional morning reminders and an optional Apple Watch companion. |
| [Android setup and tests](apps/android/README.md) | [iOS and watchOS setup and tests](apps/ios/README.md) |

## Build and test

Run the commands from the repository root after cloning it.

### Android

Open the repository root in Android Studio. Use JDK 17 and Android SDK Platform 36. The app runs on Android 7.0 (API 24) or later.

```sh
./gradlew :digitalFootprintExplorer-android:assembleDebug :digitalFootprintExplorer-android:testDebugUnitTest
```

On Windows, use `gradlew.bat` with the same tasks. The [Android guide](apps/android/README.md) explains how to run the app and check the widget on a device.

### iPhone and Apple Watch

Use an Apple silicon Mac with Xcode 27.1 or later, JDK 17, Python 3 and compatible iOS and watchOS simulator runtimes. Select `iosApp-ScreenTime` for the iPhone build with Screen Time support, or `WatchApp` for the companion.

```sh
open apps/ios/iosApp.xcodeproj
bash apps/ios/scripts/ios-check.sh
```

The script runs the shared Kotlin and iOS unit tests. See the [iOS guide](apps/ios/README.md) for signing, simulator setup and physical-device checks. GitHub Actions runs the Android, shared Kotlin, iOS and tooling checks on pull requests to `main`. [CI workflow](.github/workflows/ios-checks.yml)

## Repository layout

```text
.
├── apps/
│   ├── android/
│   │   ├── build.gradle.kts          # Android module settings
│   │   ├── src/androidMain/          # Compose app, Glance widget and resources
│   │   ├── src/androidUnitTest/      # Android unit tests
│   │   └── README.md                 # Android build and device guide
│   └── ios/
│       ├── iosApp.xcodeproj/         # Xcode targets and shared schemes
│       ├── Configuration/            # Signing, entitlements and privacy source
│       ├── iosApp/                   # SwiftUI app, history and reminders
│       ├── GardenWidget/             # iPhone Home Screen widgets
│       ├── WidgetShared/             # Code used by the iPhone app and widgets
│       ├── WatchApp/                 # Apple Watch companion
│       ├── WatchWidgets/             # Watch complications and Smart Stack
│       ├── CompanionShared/          # Garden summaries and storage for Watch
│       ├── iosAppTests/              # iOS unit and integration tests
│       ├── iosAppUITests/            # iPhone interface tests
│       ├── WatchAppUITests/          # Watch interface and widget tests
│       ├── scripts/                  # Build, privacy and release checks
│       ├── tests/                    # Python tests for the scripts
│       ├── docs/                     # Device test notes and iPhone screenshots
│       └── README.md                 # iOS and watchOS build and signing guide
├── shared/
│   ├── build.gradle.kts              # Kotlin Multiplatform and SQLDelight settings
│   └── src/
│       ├── commonMain/               # Emissions model, iOS bridge and database schema
│       ├── commonTest/               # Model and bridge tests
│       ├── androidMain/              # Android platform code and database driver
│       └── iosMain/                  # iOS platform code and database driver
├── docs/                             # Project website and architecture notes
│   ├── architecture/diagrams/        # PlantUML diagrams
│   ├── dfe-sensitivity-analyser/     # Web tool for exploring model assumptions
│   ├── images/                       # Site images and Android screenshots
│   ├── index.html                    # Project homepage
│   ├── support-ios.html              # iPhone support page
│   ├── privacy-policy.html           # iOS privacy page
│   ├── privacy-policy.md             # Markdown copy of the iOS policy
│   └── privacy-policy-content.json   # Structured copy of the iOS policy
├── report/backups/                   # Earlier project report backups
├── .github/workflows/                # Android, iOS and shared checks
├── gradle/                           # Version catalog and Gradle wrapper files
├── build.gradle.kts                  # Root Gradle build
├── settings.gradle.kts               # Module names and paths
├── gradle.properties                 # Gradle build settings
├── gradlew                           # macOS and Linux launcher
├── gradlew.bat                       # Windows launcher
├── .gitignore                        # Rules for local settings and build output
├── LICENSE                           # GNU AGPL v3 licence
└── README.md                         # Project overview
```

The diagrams show how the shared model fits into the original Android app. GitHub Pages serves the project website from `docs/` on `main`. [Architecture diagrams](docs/architecture/diagrams/) · [Project website](https://zhaw-init-softwareengineering.github.io/digital-footprint-explorer/)

## App previews

| Android garden widget | Android daily statistics |
| --- | --- |
| <a href="docs/images/widget.png"><img src="docs/images/widget.png" width="170" alt="Android Home Screen with the DFE garden widget"></a> | <a href="docs/images/stats.png"><img src="docs/images/stats.png" width="170" alt="Android daily statistics with an emissions breakdown"></a> |

| iPhone Today | iPhone History |
| --- | --- |
| <a href="apps/ios/docs/images/ios-today.png"><img src="apps/ios/docs/images/ios-today.png" width="170" alt="Today on iPhone with a green garden and a daily estimate"></a> | <a href="apps/ios/docs/images/ios-history.png"><img src="apps/ios/docs/images/ios-history.png" width="170" alt="iPhone History with saved daily estimates and a practical tip"></a> |

## Activity and privacy

Android uses Usage Access and the device statistics Android provides. On iPhone, Screen Time can supply app activity for a completed day after the user gives permission. The model uses assumptions for inputs such as iPhone data traffic, brightness and Bluetooth use. Both apps report their results as estimates in CO₂e.

The iPhone keeps results on the device. Users can share the latest saved garden summary with a paired Apple Watch. iOS controls when background work and widgets can update. Expanded Screen Time access for Swiss App Store users still needs confirmation. [iPhone support](https://zhaw-init-softwareengineering.github.io/digital-footprint-explorer/support-ios.html) · [iOS privacy policy](https://zhaw-init-softwareengineering.github.io/digital-footprint-explorer/privacy-policy.html)

## Contributing

Open a pull request that explains what changed and how you tested it. List the platforms you checked and any checks that still need a device. Keep local signing settings and build output outside Git.

DFE is licensed under the [GNU Affero General Public License](LICENSE). For project, support or privacy questions, [email the DFE Team](mailto:digital-footprint-explorer.init@zhaw.ch).
