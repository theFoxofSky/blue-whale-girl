#!/bin/zsh
set -euo pipefail
PET_PROJECT="${0:A:h:h}"
PET_MODE="${1:-full}"
[[ "$PET_MODE" == full || "$PET_MODE" == --headless ]] || { print -u2 'Usage: zsh scripts/test.sh [--headless]'; exit 1; }
PET_RESULTS="${PET_TEST_DIR:-$PET_PROJECT/.build/regression}"
mkdir -p "$PET_RESULTS"
rm -f "$PET_RESULTS/results.json" "$PET_RESULTS/portable.json"
PET_APP="$PET_RESULTS/蓝色大肥鱼.app"
PET_OUTPUT="$PET_APP" zsh "$PET_PROJECT/build.sh"
xcrun swiftc -O -swift-version 5 -module-cache-path "$PET_PROJECT/.build/module-cache" \
  -framework AppKit -framework ImageIO -parse-as-library "$PET_PROJECT/Tests/AssetChecks.swift" \
  -o "$PET_RESULTS/asset-checks"
"$PET_RESULTS/asset-checks" "$PET_PROJECT" > "$PET_RESULTS/assets.json"
if [[ "$PET_MODE" == --headless ]]; then
  xcrun swiftc -O -swift-version 5 -module-cache-path "$PET_PROJECT/.build/module-cache" \
    "$PET_PROJECT/Sources/PetModel.swift" "$PET_PROJECT/Tests/ModelTests.swift" \
    "$PET_PROJECT/Tests/ModelRunner/main.swift" -o "$PET_RESULTS/model-tests"
  "$PET_RESULTS/model-tests" > "$PET_RESULTS/model.json"
else
  "$PET_APP/Contents/MacOS/BlueWhalePet" --self-test > "$PET_RESULTS/self-test.json"
  "$PET_APP/Contents/MacOS/BlueWhalePet" --behavior-smoke-test "$PET_RESULTS/native" > "$PET_RESULTS/native.stdout"
  "$PET_RESULTS/asset-checks" "$PET_PROJECT" "$PET_RESULTS/native" > "$PET_RESULTS/gaze.json"
fi
python3 "$PET_PROJECT/scripts/report.py" "$PET_PROJECT" "$PET_RESULTS" "$PET_MODE"
