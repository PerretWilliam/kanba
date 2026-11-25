#!/bin/sh
# Builds Kanba.app next to this script. Usage: ./build.sh
set -e
cd "$(dirname "$0")"
VERSION=${VERSION:-$(cat VERSION)}   # the VERSION file is the app version; VERSION=1.2.3 ./build.sh overrides it
swift build -c release
APP=Kanba.app
rm -rf $APP && mkdir -p $APP/Contents/MacOS
cp .build/release/Kanban $APP/Contents/MacOS/
mkdir -p $APP/Contents/Resources && cp -R Fonts $APP/Contents/Resources/Fonts
cp Icon.icns $APP/Contents/Resources/
cat > $APP/Contents/Info.plist <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
<key>CFBundleExecutable</key><string>Kanban</string>
<key>CFBundleIdentifier</key><string>fr.williamperret.kanban</string>
<key>CFBundleIconFile</key><string>Icon</string>
<key>CFBundleName</key><string>Kanba</string>
<key>CFBundlePackageType</key><string>APPL</string>
<key>CFBundleShortVersionString</key><string>$VERSION</string>
<key>CFBundleVersion</key><string>$VERSION</string>
<key>CFBundleDevelopmentRegion</key><string>fr</string>
<key>LSMinimumSystemVersion</key><string>26.0</string>
<key>ATSApplicationFontsPath</key><string>Fonts</string>
<key>NSHighResolutionCapable</key><true/>
</dict></plist>
PLIST
codesign --force --sign - $APP
echo "Built $APP"
