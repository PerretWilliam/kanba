#!/bin/sh
# Builds Kanban.app next to this script. Usage: ./build.sh
set -e
cd "$(dirname "$0")"
swift build -c release
APP=Kanban.app
rm -rf $APP && mkdir -p $APP/Contents/MacOS
cp .build/release/Kanban $APP/Contents/MacOS/
cat > $APP/Contents/Info.plist <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
<key>CFBundleExecutable</key><string>Kanban</string>
<key>CFBundleIdentifier</key><string>fr.williamperret.kanban</string>
<key>CFBundleName</key><string>Kanban</string>
<key>CFBundlePackageType</key><string>APPL</string>
<key>CFBundleShortVersionString</key><string>1.0</string>
<key>CFBundleDevelopmentRegion</key><string>fr</string>
<key>LSMinimumSystemVersion</key><string>15.0</string>
<key>NSHighResolutionCapable</key><true/>
</dict></plist>
PLIST
codesign --force --sign - $APP
echo "Built $APP"
