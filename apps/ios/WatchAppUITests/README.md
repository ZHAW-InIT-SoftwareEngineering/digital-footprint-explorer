# Watch simulator checks

The `WatchApp` scheme has eight interface tests and a separate test for the watch face and Smart Stack. `WatchExperienceUITests` uses isolated sample data in Debug builds. It starts with sample history and leaves saved activity and Watch Connectivity alone. The screenshots in the result bundle are labelled as examples.

From the repository root, run the suite on a compact Watch simulator and a larger one. Use one destination at a time and replace `WATCH_SIMULATOR_ID` with its ID. The result bundle path must be new for each run.

```sh
xcodebuild test \
  -project apps/ios/iosApp.xcodeproj \
  -scheme WatchApp \
  -configuration Debug \
  -destination 'platform=watchOS Simulator,id=WATCH_SIMULATOR_ID' \
  -parallel-testing-enabled NO \
  -only-testing:WatchAppUITests/WatchExperienceUITests \
  -maximum-test-execution-time-allowance 90 \
  -resultBundlePath /absolute/path/WatchUI.xcresult \
  CODE_SIGNING_ALLOWED=NO
```

The suite covers all five gardens, the first visible amount, large-text scrolling, unavailable and older results, and three complication content layouts. The complication checks use the exact content view used by the extension. Use the separate hosting test to verify placement and opening from a watch face or Smart Stack.

For a manual visual check, launch the Debug Watch app with one of these argument sets.

```text
-ui-watch-example growing
-ui-watch-example stale -ui-watch-text-size accessibility3
-ui-watch-example pending -ui-watch-complication rectangular
-ui-watch-example growing -ui-watch-complication circular
-ui-watch-example growing -ui-watch-complication inline
-ui-watch-example growing -ui-watch-complication rectangular -ui-watch-privacy-redacted
```

For real WidgetKit hosting, install the app and add **Your phone garden** under **Digital Footprint** in the watch face editor or Smart Stack gallery. Check the three supported families, the saved-day label and the tap into the Watch app. A fresh installation should show sharing off. Use the actual App Group state for this check.

Run `WatchSystemHostUITests` on a fresh Watch simulator. In the command above, use `-only-testing:WatchAppUITests/WatchSystemHostUITests` and a new result bundle path. Prefix the command with `TEST_RUNNER_DFE_WATCH_SYSTEM_HOST_AUDIT=1` so Xcode passes the opt-in to the test runner.

The test opens the native app with sharing off, then uses the watch face controls to find and add the real widget. It saves screenshots and accessibility trees. If the gallery controls or the widget are missing, check those records before counting the test as passed.

Use a paired physical iPhone and Watch to check pairing, background delivery, offline recovery and access to the signed App Group. The Watch shows the saved iPhone estimate.

## Optional paired-simulator transport smoke test

`iosAppUITests/SimulatorWatchTransportUITests` is a separate iPhone test for a fresh simulator pair you control. The phone simulator's name must start with `DFE`. Install and open the ordinary Debug iPhone and Watch apps before attaching the test runner. Start both apps normally, outside the sample and test launch modes. The runner uses these existing app processes.

Set these runner environment values in the `.xctestrun` file for the iPhone test.

```text
DFE_SIMULATOR_WATCH_TRANSPORT=1
DFE_WATCH_TRANSPORT_ACTION=enable
```

Select only `iosAppUITests/SimulatorWatchTransportUITests`. It needs an empty History. The test turns on the Settings switch and checks that the system queues the empty Watch update. Inspect the Watch and its protected cache to confirm delivery. Then run the test with `DFE_WATCH_TRANSPORT_ACTION=disable` and check that the Watch clears the shared result.

If pairing, companion registration or the Watch App Group blocks the test, record which step failed. Leave sample caches out of the shared group. Confirm background delivery and signing on paired physical devices.

See Apple’s [watchOS testing guide](https://developer.apple.com/documentation/watchos-apps/setting-up-tests-for-your-watchos-app) and [WidgetKit debugging guide](https://developer.apple.com/documentation/widgetkit/debugging-widgets).
