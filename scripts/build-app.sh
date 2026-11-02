#!/bin/bash
set -euo pipefail

project_root="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
app_dir="$project_root/dist/KomariBar.app"
icon_work_dir="$project_root/.build/komaribar-icon"
iconset_dir="$icon_work_dir/AppIcon.iconset"

swift build --package-path "$project_root" -c release
binary_dir="$(swift build --package-path "$project_root" -c release --show-bin-path)"

mkdir -p "$app_dir/Contents/MacOS" "$app_dir/Contents/Resources" "$iconset_dir"
install -m 755 "$binary_dir/KomariBar" "$app_dir/Contents/MacOS/KomariBar"

cat > "$app_dir/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleExecutable</key>
    <string>KomariBar</string>
    <key>CFBundleIdentifier</key>
    <string>cc.komaribar.app</string>
    <key>CFBundleName</key>
    <string>KomariBar</string>
    <key>CFBundleDisplayName</key>
    <string>KomariBar</string>
    <key>CFBundleDevelopmentRegion</key>
    <string>zh_CN</string>
    <key>CFBundlePackageType</key>
    <string>APPL</string>
    <key>CFBundleShortVersionString</key>
    <string>0.1.0</string>
    <key>CFBundleVersion</key>
    <string>1</string>
    <key>CFBundleIconFile</key>
    <string>AppIcon</string>
    <key>LSMinimumSystemVersion</key>
    <string>13.0</string>
    <key>LSUIElement</key>
    <true/>
    <key>NSHighResolutionCapable</key>
    <true/>
    <key>NSAppTransportSecurity</key>
    <dict>
        <key>NSAllowsArbitraryLoads</key>
        <true/>
    </dict>
    <key>NSHumanReadableCopyright</key>
    <string>Copyright © 2026 1gxv1. MIT License.</string>
</dict>
</plist>
PLIST

swift "$project_root/scripts/make-icon.swift" "$icon_work_dir/AppIcon.png"
for icon_size in 16 32 128 256 512; do
    sips -z "$icon_size" "$icon_size" "$icon_work_dir/AppIcon.png" \
        --out "$iconset_dir/icon_${icon_size}x${icon_size}.png" >/dev/null
    doubled_size=$((icon_size * 2))
    sips -z "$doubled_size" "$doubled_size" "$icon_work_dir/AppIcon.png" \
        --out "$iconset_dir/icon_${icon_size}x${icon_size}@2x.png" >/dev/null
done
iconutil -c icns "$iconset_dir" -o "$app_dir/Contents/Resources/AppIcon.icns"

plutil -lint "$app_dir/Contents/Info.plist"
codesign --force --sign - "$app_dir"
codesign --verify --deep --strict "$app_dir"
printf '\n已生成本机架构的应用：%s\n' "$app_dir"
printf '示例预览：open -n "%s" --args --demo --window\n' "$app_dir"
