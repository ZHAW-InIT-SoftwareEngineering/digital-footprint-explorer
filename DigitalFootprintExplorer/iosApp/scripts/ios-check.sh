#!/bin/bash
# [01] Stop if a build step fails, so a later success cannot hide an earlier problem.
set -euo pipefail
# [02] Find the project from this script, allowing the check to run from another folder.
ios_dir="$(cd "$(dirname "$0")/.." && pwd)"
project_dir="$(cd "$ios_dir/.." && pwd)"
export DEVELOPER_DIR="${DEVELOPER_DIR:-/Applications/Xcode.app/Contents/Developer}"
export JAVA_HOME="${JAVA_HOME:-$(/usr/libexec/java_home -v 17)}"
# [03] Keep build caches together and resolve their real paths; Kotlin can treat two spellings as different locations.
cache_dir="${DFE_BUILD_CACHE:-/private/tmp/dfe-build-cache}"
mkdir -p "$cache_dir"
cache_dir="$(cd "$cache_dir" && pwd -P)"
export GRADLE_USER_HOME="${GRADLE_USER_HOME:-$cache_dir/gradle}"
export KONAN_DATA_DIR="${KONAN_DATA_DIR:-$cache_dir/konan}"
mkdir -p "$GRADLE_USER_HOME" "$KONAN_DATA_DIR"
export GRADLE_USER_HOME="$(cd "$GRADLE_USER_HOME" && pwd -P)"
export KONAN_DATA_DIR="$(cd "$KONAN_DATA_DIR" && pwd -P)"
# [04] Use the requested simulator, or choose an available iPhone simulator without touching a real phone.
simulator_id="$(xcrun simctl list devices available -j \
  | python3 "$ios_dir/scripts/select-ios-simulator.py" --preferred-id "${DFE_SIMULATOR_ID:-}")"
# [05] Explain the missing simulator instead of trying a build with no test destination.
if [ -z "$simulator_id" ]; then
  echo "Install an iOS simulator runtime in Xcode Settings, then run this check again." >&2
  exit 1
fi
# [08] Finish the first boot before Xcode starts its shorter test-launch timer.
# Some runtimes report a migration failure with exit zero, so keep that failure visible too.
boot_log="$cache_dir/simulator-boot.log"
xcrun simctl bootstatus "$simulator_id" -b | tee "$boot_log"
if grep -q 'Data Migration Failed' "$boot_log"; then
  echo "The selected simulator could not finish data migration. Restart it before running the tests again." >&2
  exit 1
fi
# [06] Check the shared calculation first, then run controlled native tests without requesting personal Screen Time access.
cd "$project_dir"
./gradlew :shared:iosSimulatorArm64Test --console=plain
result_bundle="${DFE_RESULT_BUNDLE:-$cache_dir/ios-tests-$(date +%Y%m%d-%H%M%S).xcresult}"
xcodebuild -project iosApp/iosApp.xcodeproj -scheme iosApp-ScreenTime -configuration ScreenTimeDebug \
  -destination "platform=iOS Simulator,id=$simulator_id" -parallel-testing-enabled NO \
  -derivedDataPath "$cache_dir/DerivedData" -resultBundlePath "$result_bundle" CODE_SIGNING_ALLOWED=NO \
  -only-testing:iosAppTests \
  -skip-testing:iosAppTests/LiveScreenTimeImportTests \
  -skip-testing:iosAppTests/LiveAllActivityImportTests test
echo "Test results: $result_bundle"
# [07] A green Xcode exit must not hide skipped feature checks or an empty controlled suite.
xcrun xcresulttool get test-results summary --path "$result_bundle" --compact \
  | python3 "$ios_dir/scripts/check-controlled-test-summary.py"
