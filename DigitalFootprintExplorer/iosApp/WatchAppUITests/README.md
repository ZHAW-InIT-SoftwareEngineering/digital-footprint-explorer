# Watch simulator checks

The `WatchApp` scheme includes eight app and content UI tests, plus a separate system-host audit. The eight `WatchExperienceUITests` launch explicit DEBUG examples and never read saved activity, write a shared file or activate Watch Connectivity. Their screenshots in the test result bundle are labelled as examples.

Run the suite on a compact and a larger installed Watch simulator. Use one destination at a time, with parallel testing disabled. A useful limit is 90 seconds per test and 15 minutes for the whole command; a timeout is a failed or blocked run, never a pass.

```sh
xcodebuild test \
  -project DigitalFootprintExplorer/iosApp/iosApp.xcodeproj \
  -scheme WatchApp \
  -configuration Debug \
  -destination 'platform=watchOS Simulator,id=WATCH_SIMULATOR_ID' \
  -parallel-testing-enabled NO \
  -only-testing:WatchAppUITests/WatchExperienceUITests \
  -maximum-test-execution-time-allowance 90 \
  -resultBundlePath /absolute/path/WatchUI.xcresult \
  CODE_SIGNING_ALLOWED=NO
```

The suite covers all five gardens, the first visible amount, large-text scrolling, unavailable and older results, and three complication content layouts. The complication checks use the exact content view used by the extension. Their app screen is a layout test host; it does not prove placement, activation or delivery in a real watch face or Smart Stack.

For a separate manual visual check, launch the DEBUG Watch app with these arguments:

```text
-ui-watch-example growing
-ui-watch-example stale -ui-watch-text-size accessibility3
-ui-watch-example pending -ui-watch-complication rectangular
-ui-watch-example growing -ui-watch-complication circular
-ui-watch-example growing -ui-watch-complication inline
-ui-watch-example growing -ui-watch-complication rectangular -ui-watch-privacy-redacted
```

For real WidgetKit hosting, install the app and add **Your phone garden** under **Digital Footprint** in the watch face editor or Smart Stack gallery. Check the three supported families, the saved-day label and the tap into the Watch app. A fresh installation should show sharing off; do not write examples into its App Group to make it look connected.

Run `WatchSystemHostUITests` separately on a fresh Watch simulator, using `-only-testing:WatchAppUITests/WatchSystemHostUITests` in the command above and a new result-bundle path. Set `TEST_RUNNER_DFE_WATCH_SYSTEM_HOST_AUDIT=1` for the command so Xcode forwards `DFE_WATCH_SYSTEM_HOST_AUDIT=1` to the runner; without that opt-in the OS-dependent audit is skipped. It opens the native app with sharing off, and uses the public Clockface system UI to find and add the real widget. It records accessibility trees and screenshots at each step. Missing gallery controls or an absent widget are failures or blockers to investigate, rather than a claimed hosting pass. The native app may initialise its normal Watch connection, but this audit neither enables sharing nor inserts example data.

Pairing, background Watch Connectivity delivery, offline recovery and signed App Group access still need an authorised physical iPhone and Watch. A passing simulator layout test does not prove those behaviours. The Watch shows the saved phone estimate and never collects Watch Screen Time.

## Optional paired-simulator transport smoke test

`iosAppUITests/SimulatorWatchTransportUITests` is a separate phone-side test for a fresh owned pair. The phone simulator's name must start with `DFE`. Install and open the ordinary DEBUG phone and Watch apps before attaching the test runner. Do not supply `-ui-testing`, any example arguments or a test launch environment to those normal app processes. The test deliberately calls neither `launch()` nor `activate()`.

Set these runner environment values explicitly in the `.xctestrun` used for the phone test:

```text
DFE_SIMULATOR_WATCH_TRANSPORT=1
DFE_WATCH_TRANSPORT_ACTION=enable
```

Select only `iosAppUITests/SimulatorWatchTransportUITests`. It requires an empty native History, enables the real Settings switch and checks that Apple accepted the empty context for queuing. Pause after this run and inspect the Watch's actual state and protected cache. Queue acceptance does not prove delivery. Then run the same test with `DFE_WATCH_TRANSPORT_ACTION=disable` and verify separately that the Watch received the sharing-off clear.

If pairing, companion registration or the Watch App Group is unavailable, record that gate. Do not copy an example cache into the group or loosen the app's test-isolation guards. Foreground simulator communication, if it works, still cannot establish real-device background delivery or signing acceptance.

Official references: [watchOS testing](https://developer.apple.com/documentation/watchos-apps/setting-up-tests-for-your-watchos-app), [WidgetKit debugging](https://developer.apple.com/documentation/widgetkit/debugging-widgets).
