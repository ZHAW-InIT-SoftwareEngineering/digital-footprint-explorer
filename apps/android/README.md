# Digital Footprint Explorer for Android

The Android app uses Compose for its screens and Glance for the garden widget. It gathers the activity Android makes available and sends those inputs to the shared Kotlin model for a daily CO₂e estimate. A WorkManager job saves the estimate and updates the widget. The [Google Play listing](https://play.google.com/store/apps/details?id=ch.zhaw.digitalfootprintexplorer) provides the public version.

## Build and run

Use Android Studio, JDK 17 and Android SDK Platform 36. The minimum supported version is Android 7.0 (API 24). The Gradle wrapper and version catalog are at the [repository root](../../README.md).

1. Open the repository root in Android Studio and select the `digitalFootprintExplorer-android` run configuration.
2. Start an emulator or connect an Android device. Run the debug app.
3. When the app asks for Usage Access, allow it in Android Settings. Use the launcher widget picker to add the garden widget if you want to see it on the Home Screen.

To build, install or run unit tests from the repository root:

```sh
./gradlew :digitalFootprintExplorer-android:assembleDebug
./gradlew :digitalFootprintExplorer-android:installDebug
./gradlew :digitalFootprintExplorer-android:testDebugUnitTest
```

On Windows, use `gradlew.bat` with the same task names. The Gradle module name stays `digitalFootprintExplorer-android` even though its source lives in `apps/android/`. No release signing credentials are needed for a debug build.

## Source map

```text
apps/android/
├── build.gradle.kts                   # Module configuration
└── src/
    ├── androidMain/
    │   ├── AndroidManifest.xml        # Permissions, service and widget registration
    │   ├── kotlin/ch/zhaw/digitalfootprintexplorer/
    │   │   ├── MainActivity.kt        # App entry point
    │   │   ├── App.kt                 # Compose navigation
    │   │   ├── ui/                    # Screens, components and theme
    │   │   ├── permission/            # Usage Access helpers
    │   │   ├── servicelayerplatform/  # Activity sources and tracking service
    │   │   ├── worker/                # Daily estimate and reboot scheduling
    │   │   ├── widget/                # Garden widget and launcher integration
    │   │   └── demo/                  # Demo inputs, calculation and preferences
    │   ├── res/                       # Android resources and garden images
    │   └── composeResources/          # Compose resources
    └── androidUnitTest/               # JVM tests for activity data sources
```

The calculation code, SQLDelight schema and shared tests live in [`shared/`](../../shared/). The Android architecture diagrams are in [`docs/architecture/diagrams/`](../../docs/architecture/diagrams/).

## Device checks

The unit tests cover installed-app lookups, metric collection and network data handling. On a device, check the Usage Access prompt, the daily statistics and the widget. A device or emulator needs usable activity before you can check a real daily estimate. Android can restrict network counters, so traffic data may be unavailable. The model handles missing inputs and presents the result as an estimate.
