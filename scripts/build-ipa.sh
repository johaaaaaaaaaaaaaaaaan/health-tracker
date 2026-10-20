#!/usr/bin/env bash
# Builds an IPA ad-hoc signed WITH entitlements, so the sideloading tool knows it must request HealthKit.
# Usage: build-ipa.sh <entitlements.plist> <output.ipa>
set -euo pipefail
entitlements="$1"
output="$2"
archive=build/Readiness.xcarchive

if [ ! -d "$archive" ]; then
  xcodebuild archive -project Readiness.xcodeproj -scheme Readiness -configuration Release \
    -destination 'generic/platform=iOS' -archivePath "$archive" CODE_SIGNING_ALLOWED=NO
fi

name=$(basename "$output" .ipa)
stage="build/stage-$name"
rm -rf "$stage" && mkdir -p "$stage/Payload"
cp -R "$archive/Products/Applications/Readiness.app" "$stage/Payload/"
app="$stage/Payload/Readiness.app"

# XcodeGen leaves $(VAR) placeholders in the entitlements file; codesign does not expand them.
settings=$(xcodebuild -showBuildSettings -project Readiness.xcodeproj -scheme Readiness -configuration Release 2>/dev/null)
resolved="$stage/entitlements.plist"
cp "$entitlements" "$resolved"
while grep -q '\$(' "$resolved"; do
  var=$(grep -o '\$([A-Z_]*)' "$resolved" | head -1 | tr -d '$()')
  value=$(echo "$settings" | sed -n "s/^ *$var = //p" | head -1)
  if [ -z "$value" ]; then echo "Unresolved build setting \$($var) in $entitlements" >&2; exit 1; fi
  sed -i '' "s|\$($var)|$value|g" "$resolved"
done

if [ -d "$app/Frameworks" ]; then
  find "$app/Frameworks" -maxdepth 1 \( -name '*.framework' -o -name '*.dylib' \) -exec codesign --force --sign - --timestamp=none {} \;
fi
codesign --force --sign - --timestamp=none --entitlements "$resolved" "$app"

signed=$(codesign -d --entitlements :- "$app" 2>/dev/null)
echo "$signed"
if ! grep -q com.apple.developer.healthkit <<<"$signed"; then echo "HealthKit entitlement missing" >&2; exit 1; fi
if grep -q '\$(' <<<"$signed"; then echo "Unresolved variable in signed entitlements" >&2; exit 1; fi

mkdir -p "$(dirname "$output")"
abs_output="$(cd "$(dirname "$output")" && pwd)/$(basename "$output")"
rm -f "$abs_output"
(cd "$stage" && zip -qry "$abs_output" Payload)
echo "Built $output ($(du -h "$output" | cut -f1))"
