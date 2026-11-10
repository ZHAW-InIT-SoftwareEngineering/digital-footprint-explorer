# Digital Footprint Explorer for iOS

The native app uses the existing shared emission model. It turns the available Screen Time activity into a daily estimate, a garden and a local history. The small and medium Home Screen widgets show the latest saved garden.

| Today | History | Settings |
| --- | --- | --- |
| ![Today with a green garden](docs/images/ios-today.png) | ![Saved daily estimates](docs/images/ios-history.png) | ![Connection and privacy settings](docs/images/ios-settings.png) |

These previews use isolated example history. They show the interface, not measured activity or verified emissions.

## Apple device coverage

The app targets iPhone and adapts Today to the wider iPhone Duo display. This release has no native iPad target. An optional Apple Watch companion shows the latest saved garden. The device acceptance record separates local tests, example screenshots, signed builds and physical-device checks. It keeps earlier failures with their follow-up results so each outcome can be traced to its own test.

Today keeps one column on compact screens and at larger accessibility text sizes. A regular window at least 760 points wide places the frameless garden beside the existing actions. On a wide window with moderate height, the result and the link to that day move beside the garden and use larger text. Native tabs can adapt to a sidebar. The same saved dates, pending messages, refresh path and daily calculations apply in each arrangement.

Screen Time queries use the current device, without adding activity from other devices. The Watch displays a saved iPhone result after the person enables sharing, which is off by default. It does not collect Watch activity or run the Screen Time calculation. WatchConnectivity requires a paired iPhone.

See [Apple device coverage and acceptance](docs/apple-device-coverage.md#acceptance-record) for the recorded local results, simulator observations, platform limits and pending checks. Apple's regional Screen Time conditions, including the unresolved Swiss customer route, are unchanged.

## Independent widget updates

The Screen Time build includes an activity reader in the widget, using the same shared calculation model as the app. With the saved automatic setup and Apple's required widget permissions, it can attempt the previous completed day's calculation when WidgetKit runs it. A protected pending record reaches disk before the garden changes, and the app checks and adds that record to its private history when it next opens. Disconnecting stops widget imports. Deleting entries clears old widget work and keeps a valid automatic setup for new days.

iOS chooses widget execution times. This route does not promise an 08:00 refresh, complete Screen Time coverage or customer access in Switzerland. Each release needs its own distribution, TestFlight and new-day checks; a controlled same-day calculation is not evidence of an unattended daily update.

## Build and run

Use an Apple silicon Mac with Xcode 27.1 or later, JDK 17 and an installed iPhone simulator. The build needs the iOS 27 SDK for the newer background-task API; the app and widget can run on iOS 26.4 or later. The wider-device and Watch candidate is prepared for the installed Xcode 27.2 toolchain. The Watch target requires watchOS 10 or later. The Gradle wrapper in `DigitalFootprintExplorer/` builds the neighbouring `shared/` module; there is no separate copy of the calculation model in Swift.

1. Open `DigitalFootprintExplorer/iosApp/iosApp.xcodeproj` from the repository root.
2. Select `iosApp-ScreenTime`, then choose an iPhone simulator and run. Xcode builds the shared framework before the app.
3. For a physical iPhone, copy `Configuration/Local.xcconfig.example` to `Configuration/Local.xcconfig`. Use your approved Apple team and matching app/widget identifiers, App Group and provisioning profiles. Keep this local signing file out of Git.
4. On a supported device, choose **Enable automatic estimates** and complete Apple's authorization. No daily form or app-by-app selection is required. A completed day stays pending until Apple supplies usable activity.

The ordinary `iosApp` scheme is also available for builds without the expanded Screen Time route. Changing a scheme or entitlement file does not grant Apple's permission.

The automatic widget needs its own Family Controls and App and Website Usage rights, as well as the same App Group. Check both signed bundles and their matching profiles; the host's approval alone does not configure the widget.

For the companion, select the `WatchApp` scheme and build or run it on an available Watch simulator. Its eight isolated app and complication-content interface tests run on watchOS; the contract, deadline and inbox checks belong to the iOS unit-test target. See [the Watch test guide](WatchAppUITests/README.md) for the commands and the separate system-host audit. Use an actual paired iPhone and Watch for release acceptance. Simulator layouts do not establish delivery, real complication hosting or signing.

## Automatic estimates and privacy

Screen Time supplies the app durations that Apple makes available for a completed day on this device. Compare the date shown with the same device's daily Screen Time report, rather than today's changing total or a weekly average across devices. Local exact-ID rules map known apps; unknown IDs keep their time under Other apps. A source with screen-on activity but no positive app time stays pending. This guard does not prove complete coverage of every activity. Matching the same date and device does not guarantee matching totals: Apple's returned app activity can still differ from Settings. The calculation uses those available app rows and does not scale them up or assign unexplained screen time to a category.

Traffic uses category-average assumptions. Brightness, GPS, Bluetooth and carbon emissions remain model inputs or estimates, not measurements collected from other apps. The import does not establish all background music listening, call type, video quality or actual traffic. Website rows are excluded. Automatic setup keeps the saved routine's assumptions, including valid zero GB/h, and clears only usage minutes for Apple to supply. New days use their applicable routine; existing days keep their saved assumptions. The garden compares each result with up to seven earlier saved days, rather than grading an absolute measured impact.

The app keeps its full history on the device. Its App Group holds the latest garden summary, the applicable automatic setup and a bounded pending-day handoff from the widget. The handoff uses iOS file protection and contains category totals and calculation inputs. The app checks and recalculates pending results before saving them to history. App names, app IDs and individual app records are excluded. Separate storage/read checks contain dates and fixed statuses, without usage amounts or footprint values. After opt-in, Apple manages delivery of the latest saved summary to the paired Watch through Watch Connectivity. There is no DFE account, activity-upload service or remote push server.

Optional morning reminders are local notifications saved for the next 30 mornings, around 08:00 local time. iOS can display them while DFE is closed, including after force-quit. App use or permitted background time renews the schedule. Generic wording varies by the local delivery date, without a personal profile or extra activity collection, and does not claim that a fresh estimate is ready. Known future requests can receive updated wording under the same ID and delivery time. Before a reminder is due, a fresh valid result may replace its message using the same dated request; a later import does not send a second message after that day's reminder may have fired. Turning reminders off cancels pending messages, and deleting entries resets the choice and log. Screen Time access remains a separate choice.

A saved reminder does not run a new calculation or update a widget. Force-quit normally stops the main app's background launches; this candidate's widget can attempt its own query when iOS permits execution. Focus and notification settings can delay or hide reminders. Neither route promises an update at exactly 08:00, indefinite reminders after more than 30 days without runtime, or a fresh result whenever the app is closed.

Family Controls and App and Website Usage need the correct capabilities, profiles and user authorization. Apple's published expanded-access customer conditions include an EU-located device and an EU Apple Account region. Development testing elsewhere does not prove customer availability there. Check [Apple's entitlement guide](https://developer.apple.com/documentation/familycontrols/requesting-the-family-controls-entitlement) and [expanded access conditions](https://developer.apple.com/documentation/familycontrols/authorizationstatus/approvedwithdataaccess) before choosing release countries.

The offline policy is in the app. The privacy and support addresses are set in the release configuration, and their sources are in the repository website. After the changes are accepted, verify that GitHub Pages serves both updated pages at the addresses listed in App Store Connect before submitting to App Review.

## Verify an automatic update

In Settings, expand **Connection details → Automatic update checks**. A successful import records its actual completion after the protected history save, with the work's origin and the app state at that time. The first observed save stays unchanged when the app opens later. Previously imported days have no reconstructed first-import time. The app keeps at most 32 completed-day checks, without activity amounts or app identities.

The host writes and reads back the shared garden in memory. Small and medium widgets record real timeline reads separately; gallery previews cannot create evidence, and a timeline read is not proof of on-screen rendering. Safe copies of these checks also live beside the app history, so a local test need not export the shared garden values. **Copy update checks** shares only this technical information when the user chooses it. Delete all entries clears the checks too.

A new build must be tested on a physical phone before treating its receipts as beta evidence. Record the build/configuration, completed day, completion state and timestamps. Keep natural callbacks separate from foreground refreshes or debugger-forced work. These checks cannot recover the original time of an import that happened before they existed, establish complete Screen Time coverage or change Apple's regional access rules.

## Run the checks

From the repository root:

```sh
python3 -m unittest discover -s DigitalFootprintExplorer/iosApp/tests -v
python3 DigitalFootprintExplorer/iosApp/scripts/generate_privacy_policy.py --check
python3 DigitalFootprintExplorer/iosApp/scripts/generate_privacy_policy.py --check --include-web
bash DigitalFootprintExplorer/iosApp/scripts/ios-check.sh
```

The last command runs all 24 shared calculation tests, including the iOS bridge and the corrected time-unit fixtures, followed by the controlled native unit tests. Set `DFE_SIMULATOR_ID` to choose a particular installed simulator. It writes an `.xcresult` bundle outside the repository by default and prints its path. These tests use isolated stores and do not request personal Screen Time access.

GitHub Actions runs these checks for pull requests to `main` and saves the logs, shared reports and `.xcresult` as an artifact for 14 days. The workflow uses GitHub's arm64 `xcode-27` preview image and selects an installed Xcode with the required SDKs and a compatible standard iPhone simulator. It checks for a matching watchOS runtime before building the embedded companion. It does not use signing credentials or run the live Screen Time phone tests. A maintainer may need to approve the first run from a fork; adding the workflow is not evidence that its hosted run has passed.

To run the interface tests, replace the destination below with an installed iPhone simulator:

```sh
xcodebuild -project DigitalFootprintExplorer/iosApp/iosApp.xcodeproj \
  -scheme iosApp -configuration ScreenTimeDebug \
  -destination 'platform=iOS Simulator,name=iPhone 18 Pro Max' \
  -parallel-testing-enabled NO CODE_SIGNING_ALLOWED=NO \
  -only-testing:iosAppUITests test
```

Live Screen Time import, a natural new-day background update, visible widget refresh and notice delivery need separate physical-device acceptance. Simulator tests and compilation do not establish those results or App Store readiness.

## Local tools

Edit the policy in `Configuration/PrivacyPolicyContent.json`, then run `scripts/generate_privacy_policy.py`. The default updates only `iosApp/PrivacyPolicyContent.swift` and leaves the website alone. Add `--include-web` to update the same policy's HTML, Markdown and JSON copies in the repository's root `docs/` folder. No extra public copies are created inside this iOS folder. Use `--check --include-web` to report differences without changing any file.

The generated public files are `docs/privacy-policy.html`, `docs/privacy-policy.md` and `docs/privacy-policy-content.json` at the repository root. Generating them does not deploy the website. GitHub Pages publishes the repository's approved website source after the pull request is merged.

`scripts/check-ios-release.py` inspects a built bundle or archive without uploading it or changing signing resources. Pass `--require-store` when a distribution signature, approved public URLs and matching Store profiles are required. Its `--project-root` input is the repository root.

The export options and Store checker target the ZHAW release identity. Development signing still comes from your ignored `Local.xcconfig`; cloning the project does not select the ZHAW team.

Before a distribution archive, choose an unused build number and supply `DFE_SOURCE_REVISION` with the reviewed Git revision or a recorded source fingerprint. The host, Home Screen widget, Watch app and Watch widget must contain the same value. The preparation check rejects missing values and placeholders; it does not calculate or verify the fingerprint for you.

```text
DigitalFootprintExplorer/iosApp/
├── Configuration/          # Capabilities, policy source and local signing example
├── iosApp.xcodeproj/       # Xcode project and shared schemes
├── iosApp/                 # SwiftUI app, local storage and automatic refresh
├── GardenWidget/           # Small and medium WidgetKit layouts
├── WidgetShared/           # Shared calculation inputs, pending imports and widget storage
├── WatchApp/               # Optional display of a saved paired-iPhone result
├── WatchAppUITests/        # Isolated Watch views and a separate system-host audit
├── WatchWidgets/           # Watch complications and Smart Stack layout
├── CompanionShared/        # Bounded Watch payload and local storage
├── iosAppTests/            # Controlled model, storage and refresh tests
├── iosAppUITests/          # Navigation, layout and accessibility tests
├── scripts/                # Local build, policy and release checks
├── tests/                  # Python tests for those checks
└── docs/                   # Device acceptance notes and example-history previews
```

The acceptance record tracks the signed TestFlight build and the remaining checks before App Review.

## Public pages and contact

The DFE Team maintains the app and answers privacy and support questions at [digital-footprint-explorer.init@zhaw.ch](mailto:digital-footprint-explorer.init@zhaw.ch). The website sources are in the repository's `docs/` folder. The app also includes a copy of the privacy policy that is available offline.
