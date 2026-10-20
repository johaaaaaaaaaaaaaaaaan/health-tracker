#!/usr/bin/env bash
# Prints an xcodebuild destination: "iPhone 13" on the newest iOS runtime if available,
# otherwise the first iPhone on the newest iOS runtime.
set -euo pipefail
json=$(xcrun simctl list devices available -j)
pick() {
  echo "$json" | jq -r --arg name "$1" '
    [.devices | to_entries | map(select(.key | test("SimRuntime\\.iOS-")))
     | sort_by(.key | capture("iOS-(?<maj>[0-9]+)-(?<min>[0-9]+)") | [(.maj|tonumber), (.min|tonumber)])
     | reverse[] | .value[] | select(if $name == "" then (.name | startswith("iPhone")) else .name == $name end)]
    | first | .udid // empty'
}
udid=$(pick "iPhone 13")
[ -z "$udid" ] && udid=$(pick "")
if [ -z "$udid" ]; then echo "No iPhone simulator available" >&2; exit 1; fi
echo "platform=iOS Simulator,id=$udid"
