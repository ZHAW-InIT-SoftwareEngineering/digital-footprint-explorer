# Apple device coverage

This document describes the build 4 candidate starting from revision `47e651759e5991dbceef0d85bf3ea6451aa916d8`. It records the device layouts, simulator results and checks needed for a signed release.

## Layout and navigation

The interface uses the current window width, size class and text size. It does not choose a layout from a device-name list.

- Compact windows keep the existing single-column Today layout, 294.3-point maximum garden width, native tabs and automatic-only input.
- Regular windows at least 760 points wide can show two columns. The garden stays frameless and has a maximum width of 400 points; the existing setup, pending message and navigation actions sit beside it.
- When that window is 430 to 640 points tall, Today uses larger text. It places the saved amount, activity and source beside the garden, with the link to the same day below the amount. An unfinished day keeps its existing explanation. The arrangement follows the available space, so an unusually shallow iPhone window keeps its earlier layout.
- Narrower windows and accessibility text sizes return to one column. Changing arrangement does not create another calculation or alter the saved day.
- On iOS 18 and later, the native adaptable tab style supports a sidebar where the system offers one. Compact navigation remains a tab bar.
- Safe areas come from the system. The layout does not draw over the Dynamic Island, sensor area or native navigation controls.

Both arrangements use the same period label, unfinished-day explanation, theme, refresh action and Today deep link. The Light canvas remains white, and the original garden images remain unchanged.

### Dynamic Island

The iPhone checks cover the real navigation and safe areas on iPhone 18 Pro and Pro Max. DFE does not add a Live Activity just to keep yesterday's estimate in the Dynamic Island. Apple's guidance recommends Live Activities for an ongoing task or event with a clear beginning and end. A saved daily estimate fits the existing widgets and optional morning notification better. This is a design choice for the current product; a Live Activity would not add Screen Time permission or make iOS run a new import.

## What each platform calculates

The iPhone and iPad app query the current device's available Screen Time app activity. The query is not changed to combine several devices. Broader access still requires Apple's capabilities, a suitable provisioning profile and the person's authorization.

iPad uses the unchanged phone reference model and shows that limit in the saved-day explanation. There are no new tablet power coefficients or claims of measured iPad energy. Split View, picture-in-picture and overlapping activity need physical checks. Invalid or excessive durations remain pending or report an error; the app does not clamp them into a convenient daily total.

The independent Home Screen widget retains its existing protected input path and pending handoff. The current device expansion does not guarantee complete activity coverage, an exact morning execution time or a fresh calculation after every force-quit.

Apple's published EU conditions for expanded customer access remain separate from development testing. Adding iPad or Watch support does not authorize general Screen Time collection for customers in Switzerland.

## Apple Watch companion

The Watch app is a companion to the paired iPhone, rather than a second activity collector. Sharing is off by default and requires a separate choice in iPhone Settings.

The bounded transfer contains the latest saved day, estimated total, garden state, source, calculation time and completion state. A local installation code and update number keep updates in order and reject late results. It does not include app names, app identifiers, category durations or full history. The privacy copy dated 8 November 2026 describes these ordering details and the exchange between the paired devices. The Watch keeps its accepted copy in protected local storage and identifies missing, older and offline results.

The Watch's saved inbox preserves withdrawal and sender-ordering state. If a clear comes from a different phone installation, passive results stay blocked: a delayed older sender cannot restore the garden, and a valid reply to a current refresh is needed to resume. A privacy clear takes effect in memory even if saving fails, and the app tries to remove the readable old result and save the blocked state. If the filesystem rejects every write, protection across a relaunch cannot be guaranteed. The app reports the storage problem. An offline Watch cannot receive a new clear until connectivity delivers it, so this is not an immediate remote-wipe promise.

The Watch privacy manifest declares `SystemBootTime` with reason `35F9.1` for its local elapsed-time refresh deadline. System uptime is not added to the transferred summary. Both activation and the phone reply have a bounded wait, and a late reply cannot complete a newer request.

The Watch app and its complications use the five existing garden states. Rectangular, circular and inline complications are included; the rectangular layout can also appear in Smart Stack. A refresh action can ask a reachable paired iPhone for its latest saved result. It does not grant Screen Time access, measure Watch use or guarantee that the iPhone can run while closed.

WatchConnectivity uses an iPhone and its paired Apple Watch. The iPad app does not act as the Watch's phone. The minimum Watch target is watchOS 10, so Apple Watch Series 3 is not included. Current-device simulator availability does not change that minimum or replace testing on an actual paired Watch.

New Watch bundle identifiers, the watch-local App Group and matching signing profiles need their own review. The app's existing Screen Time permission is not a Watch entitlement, and this companion does not request Watch Screen Time data.

## Available simulator inventory

Xcode 27.2 exposes the following device types in this development environment. This is an inventory, not a list of completed tests.

| Device class | Installed simulator examples | Check scope |
| --- | --- | --- |
| Compact iPhone with Dynamic Island | iPhone 18 Pro and Pro Max | Portrait and landscape safe areas, unchanged compact flow, refresh and larger text |
| Adaptable iPhone | iPhone Duo | Available compact and expanded window sizes, rotation, column changes and navigation |
| iPad | iPad Pro M5, 11-inch and 13-inch | Portrait and landscape, narrow windows, larger text, current-device activity and model explanation |
| Apple Watch | Series 12 and Ultra 4 | App layout, complications, cached state, pairing and transfer ordering |

## Acceptance record

The 8 November device audit used local source snapshot `8bb970b2b90e8d2baede7804edfc740564dd3a89beb7bfba429dfdd2c632bdfd`, recorded in the private source manifest. This is a content fingerprint, not a Git commit. It covers versioned and unignored new source, configuration and resources under `DigitalFootprintExplorer/`, excluding documentation and prose. The installed TestFlight 1.0 (3) beta has not changed.

The retained native runs passed 448 unit methods. The shared model and its 24 previously passing Kotlin methods are unchanged. A tool run passed 56 Python methods, and the policy copies agree. The unsigned build for this audit passed 30 package checks, including matching build 4 source labels in the phone app, Home Screen widget, Watch app and Watch widget. These checks do not provide distribution signing or Apple validation.

The interface record contains 49 device-and-method pairs with a passing execution. The same method on two devices counts as two pairs, rather than two different test methods. Failed and interrupted attempts remain beside the later focused checks; this is not a single clean 49-test run. The earlier 42-method phone inventory keeps its own dated evidence and is not added to this table.

| Simulator | Passing interface scope | What was checked |
| --- | --- | --- |
| iPhone 18 Pro | 6 pairs across retained runs | Native safe areas, rotation, refresh, larger text, light/dark routes and the dry garden's pending explanation |
| iPhone 18 Pro Max | 6 pairs | The same compact phone behaviour at the larger size |
| iPhone Duo | 7 pairs across retained runs | Real window geometry, navigation, refresh, larger text, light/dark routes and the dry garden |
| iPad Pro 11-inch M5 | 7 pairs across retained runs | Wide layout, a native sidebar in landscape, saved-day preservation, refresh, larger text and both themes |
| iPad Pro 13-inch M5 | 7 pairs | A real narrow window with a nonzero screen origin, refresh, larger text, saved-day preservation and both themes |
| Apple Watch Series 12 | 8 pairs | Five gardens, scrolling at accessibility text size, pending/disconnected states, stale context, three complication content layouts and privacy redaction |
| Apple Watch Ultra 4 | 8 pairs | The same Watch content checks at the larger size |

The gallery contains 97 unchanged native PNGs from 121 attachment records: 82 isolated app views, 12 complication-content previews and three manual Duo pose observations. Duplicate attachments stay in the provenance record. Example history is not real Screen Time input, and a complication content preview does not prove system hosting.

### What the failed checks taught us

The original rotation checks treated device orientation as window shape. That assumption is wrong for resizable windows. An explicit independent-window test mode now reads the actual viewport, size class and native selection; ordinary phone runs keep the stricter interface-orientation check. This follows [Apple's Duo preparation guidance](https://developer.apple.com/iphone-duo/prepare/), rather than selecting a layout from a device name.

A second issue was in the test's coordinate comparison. XCTest snapshots could report a local origin while live element frames used screen coordinates. The narrow iPad window began at x=258, so comparing the two made visible text look unreachable and caused repeated pull gestures. The reach helper now uses live frames. Another regression checks the welcome text without increasing the refresh counter.

The wide iPad exposed two more test assumptions. Its horizontal native tabs were in an `Other` header group, rather than a typed tab bar or toolbar. In landscape, its accessibility scroll shell also included a 280-point sidebar, while the real content pane was 930 points wide. The final test verifies selected, usable native controls inside the actual header and reads the pane origin from the existing one-point DEBUG geometry receipt. It still checks the pane against the real window, safe area, column widths and spacing. No production layout was changed to satisfy these assertions.

Separate Device Hub observations checked Closed, Open and Partially Open Duo poses using the native controls. The saved day, garden and routes stayed consistent. Those manual observations remain separate from automated runs and do not establish physical Duo activity access. An earlier boot returned `Data Migration Failed` despite exit code zero; it remains an unstarted check, not a pass.

### Watch content and transport

The eight Watch checks passed on both sizes using isolated DEBUG examples. The app and the content test host use the same complication view. Privacy redaction also hides the amount and garden from the accessibility description. The amount fits the first view at normal text sizes; additional context remains reachable by scrolling. The garden keeps a minimum height of 64 points, or 48 points with accessibility text.

A separate fresh paired-simulator smoke test used the ordinary apps with an empty phone history. Its first attempts did not reach the send operation because the system reported that the Watch app was not installed. After both simulators were connected, a local Xcode-built Watch bundle was installed again and both apps were reopened. These actions were applied together, so they do not identify a single cause.

The later ON check confirmed queue acceptance and matching receipt of an empty context on the Watch. The final OFF check confirmed matching `sharingOff` messages and protected Watch storage; sharing was left off. Three new control checks passed across these stages. They are separate from the 49 isolated interface pairs. No example garden was placed in normal shared storage. This proves an empty-context simulator transport and withdrawal, not a live estimate, background delivery or physical-device signing.

Actual complication placement and navigation in a watch face or Smart Stack remain unverified. The OS-host attempts and manual handoffs did not produce a confirmed native card capture. They are preserved as unsuccessful checks and are not replaced by the passing content previews.

### Visual follow-up: 9 November

The Watch app gives the garden more space at accessibility text sizes and leaves the rest of the saved result in the scroll view. The visible button says **Refresh**, while its accessible name still identifies the paired iPhone. The saved date sits below the result, and the scroll view keeps its content clear of the clock. The companion's transfer logic and its complication layouts are unchanged.

The local visual review keeps the 8 November screenshots alongside the new native captures. The examples show the layout and navigation without reading personal activity. A screenshot of the Duo inner display uses the simulator's real window size; it does not measure a physical hinge angle.

Three focused interface checks passed on each Watch size. The tests covered the garden and refresh action with accessibility text, the first view at normal text size and the enabled action in an empty simulator. Two Duo checks passed on the 867 × 553-point inner window, including light and dark appearances, the link to the saved day and the single column at maximum text size. One iPhone 18 Pro Max check and eight layout unit checks also passed. The updated unsigned package passed all 30 local checks. These are follow-up results for the changed screens; the earlier full runs keep their original source record.

### Remaining acceptance gates

| Area | Required next evidence |
| --- | --- |
| Physical iPad activity | A signed iPad imports its own completed day without combining devices, with the phone-reference model clearly labelled |
| iPad calibration | Review the reference assumptions before making any claim about actual tablet energy |
| Paired Watch delivery | A signed physical pair transfers the latest real aggregate, handles offline recovery, withdrawal and deletion, and updates the visible complication |
| Watch system hosting | Add each supported family in its real system host and verify the saved-day label and tap into the Watch app |
| Signing and distribution | Register the Watch identifiers and group, prepare matching profiles and validate the exact signed candidate before any upload |
| Swiss customer eligibility | Apple's written response confirms an available customer route, or the release accurately limits automatic access |

The owner currently has an iPhone only. The physical iPad and Watch checks therefore remain open. Local simulator success does not establish production readiness, complete Screen Time coverage or regional customer eligibility.

## Running the layout checks

Use an installed simulator destination and the local Xcode toolchain. The tests use isolated example history and never request personal activity.

```sh
xcodebuild -project DigitalFootprintExplorer/iosApp/iosApp.xcodeproj \
  -scheme iosApp-ScreenTime -configuration ScreenTimeDebug \
  -destination 'platform=iOS Simulator,name=iPhone 18 Pro Max' \
  -parallel-testing-enabled NO CODE_SIGNING_ALLOWED=NO \
  -only-testing:iosAppTests/AdaptiveDeviceLayoutTests \
  -only-testing:iosAppUITests/AdaptiveDeviceUITests test
```

For Duo and independently sized iPad windows, set `DFE_UI_WINDOW_ORIENTATION_INDEPENDENT=1` explicitly in the `iosAppUITests` runner environment of the generated `.xctestrun`, then use `test-without-building` with that file. The acceptance runs used this explicit contract; ordinary phone runs leave it unset. `DFE_UI_REQUIRE_OFFSET_WINDOW=1` can require a genuinely moved window for the focused origin regression. Neither option resizes the app or supplies a fake viewport. Record the actual geometry and preserve the failed attempts. Use Device Hub separately for the three Duo poses, since the public SDK has no pose setter. The `WatchApp` scheme now includes the eight isolated Watch UI tests and a separate opt-in system-host audit; see [the Watch test guide](../WatchAppUITests/README.md). Shared contract, deadline and inbox methods run in the iOS unit-test target. Physical permission, new-day and paired-Watch acceptance remain separate.

No build from this branch should replace the current beta until the relevant checks and privacy changes have been reviewed.

## Release and device follow-up

The owner currently has only an iPhone. A physical iPad and paired Watch must be arranged for the remaining acceptance checks. Simulator fixtures do not establish real activity coverage or phone-to-Watch delivery.

Before distributing the companion, register `ch.zhaw.digitalfootprintexplorer.ios.watchkitapp` and `ch.zhaw.digitalfootprintexplorer.ios.watchkitapp.GardenWidget`, assign the watch-local group `group.ch.zhaw.digitalfootprintexplorer.ios.watch` to those two targets, and prepare matching signing profiles. The Watch does not need the phone's Family Controls rights. Review the optional derived-summary transfer and the updated privacy text with the release owner and App Review; this document does not claim Apple has approved this particular companion flow.

The generic iOS simulator build now gives the Home Screen widget the same arm64 architecture as the app and existing Kotlin targets. The Watch keeps its own standard architectures. The shared model and Android app remain unchanged.

Use the ordinary iOS simulator for routine checks, or set `DFE_SIMULATOR_ID` to request a particular phone or iPad. The check script waits for boot to finish and rejects a failed migration instead of counting an unstarted test as a pass. A device-specific runtime still needs its own acceptance. The prepared CI changes have not run on GitHub from this local branch.

## Platform references

- [Apple layout guidance](https://developer.apple.com/design/human-interface-guidelines/layout) covers safe areas, window sizes and adaptable navigation.
- [Live Activities](https://developer.apple.com/design/human-interface-guidelines/live-activities) describes suitable ongoing tasks and their presentation in the Dynamic Island.
- [Watch Connectivity](https://developer.apple.com/documentation/watchconnectivity/transferring-data-with-watch-connectivity) describes the paired-phone transport and its delivery limits.
- [Watch background tasks](https://developer.apple.com/documentation/watchkit/using-background-tasks) explains handling connectivity updates before finishing background time.
- [Expanded activity access](https://developer.apple.com/documentation/familycontrols/authorizationstatus/approvedwithdataaccess) remains subject to Apple's device, account and regional rules.
