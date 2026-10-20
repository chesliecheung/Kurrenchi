#!/bin/zsh
set -euo pipefail

repo_dir="${0:A:h:h}"
output_dir="$repo_dir/outputs"
app_dir="$output_dir/Kurrenchi.app"

cd "$repo_dir"
swift build -c release

mkdir -p "$app_dir/Contents/MacOS" "$app_dir/Contents/Resources"
cp ".build/release/Kurrenchi" "$app_dir/Contents/MacOS/Kurrenchi"
cp ".build/release/KurrenchiHelper" "$app_dir/Contents/MacOS/kurrenchi-helper"
cp "Resources/Info.plist" "$app_dir/Contents/Info.plist"
cp "Resources/AppIcon.icns" "$app_dir/Contents/Resources/AppIcon.icns"
cp "Resources/MenuBarBoltTemplate.png" "$app_dir/Contents/Resources/MenuBarBoltTemplate.png"
cp "Sources/KurrenchiShared/LICENSE-MIT.txt" "$app_dir/Contents/Resources/ThirdPartyLicenses.txt"
chmod +x "$app_dir/Contents/MacOS/Kurrenchi" "$app_dir/Contents/MacOS/kurrenchi-helper"

# Ad-hoc signing makes local launch behavior predictable. Distribution builds
# should replace this with an Apple Developer ID signature and notarization.
signing_identity="${KURRENCHI_SIGN_IDENTITY:--}"
codesign --force --options runtime --timestamp=none --sign "$signing_identity" "$app_dir/Contents/MacOS/kurrenchi-helper"
codesign --force --deep --options runtime --timestamp=none --sign "$signing_identity" "$app_dir"
echo "$app_dir"
