# Digital Footprint Explorer for Android

The Android app uses Compose for its screens and Glance for the garden widget. It uses the activity Android makes available to calculate a daily CO₂e estimate with the shared Kotlin model. A WorkManager job saves the estimate and updates the widget. The public app is available on [Google Play](https://play.google.com/store/apps/details?id=ch.zhaw.digitalfootprintexplorer).

## Build and run

Use Android Studio, JDK 17 and Android SDK Platform 36. The minimum supported version is Android 7.0 (API 24). The Gradle wrapper and version catalog are at the [repository root](../../README.md).

1. Open the repository root in Android Studio and sync Gradle.
2. Start an emulator or connect an Android device. Select the `digitalFootprintExplorer-android` module and run the debug app.
3. When the app asks for Usage Access, allow it in Android Settings. Use the launcher widget picker to add the garden widget if you want to see it on the Home Screen.

Run these commands from the repository root. `installDebug` needs a running emulator or a connected device.

```sh
./gradlew :digitalFootprintExplorer-android:assembleDebug
./gradlew :digitalFootprintExplorer-android:installDebug
./gradlew :digitalFootprintExplorer-android:testDebugUnitTest
```

On Windows, use `gradlew.bat` with the same task names. The Gradle module name stays `digitalFootprintExplorer-android` even though its source lives in `apps/android/`. The debug build uses the local Android debug signing key.

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

The JVM tests cover installed-app lookups and how the app combines activity data. The `NetworkUsageDataSourceTest` is marked `@Ignore`. Check Android's network counters on a physical device, where access can vary.

1. Open the app, allow Usage Access and add the garden widget to the Home Screen.
2. Use the phone normally. After a completed day with usable activity, check that the app shows daily statistics and that the widget shows the saved garden.
