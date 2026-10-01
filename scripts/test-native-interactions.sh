#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/../native"
FAMILY=${1:-iPhone}
RESULT=${2:-InteractionTests}
DEVICE=$(xcrun simctl list devices available -j | python3 -c 'import json,sys; d=json.load(sys.stdin); print(next(x["udid"] for group in d["devices"].values() for x in group if sys.argv[1] in x["name"]))' "$FAMILY")
ONLY=()
if [ "$FAMILY" = "iPad" ]; then ONLY=(-only-testing:SugerlyUITests/HomeInteractionTests); fi
xcodebuild test -project Sugerly.xcodeproj -scheme Sugerly \
  -destination "platform=iOS Simulator,id=$DEVICE" \
  -derivedDataPath simulator-build -resultBundlePath "$RESULT.xcresult" "${ONLY[@]}" \
  -parallel-testing-enabled NO CODE_SIGNING_ALLOWED=NO \
  2>&1 | tee simulator-test.log | grep -E "error:|Test Case|TEST (SUCCEEDED|FAILED)"
