#!/bin/bash

echo "🧹 Deep cleaning MeetMemento project..."

# Kill Xcode background processes
echo "Stopping Xcode background services..."
killall -9 SourceKitService XCBBuildService com.apple.dt.SKAgent swift-plugin-server 2>/dev/null

# Shutdown simulators
echo "Shutting down simulators..."
xcrun simctl shutdown all 2>/dev/null

# Remove project-local build artifacts
echo "Removing local build artifacts..."
rm -rf .build/ .swiftpm/ build/
rm -rf MeetMemento.xcodeproj/xcuserdata/
rm -rf MeetMemento.xcodeproj/project.xcworkspace/xcuserdata/
rm -rf MeetMemento.xcodeproj/project.xcworkspace/xcshareddata/swiftpm/

# Remove Xcode derived data
echo "Removing Xcode derived data..."
rm -rf ~/Library/Developer/Xcode/DerivedData/MeetMemento-*

# Remove Swift package manager caches
echo "Removing SwiftPM caches..."
rm -rf ~/Library/Caches/org.swift.swiftpm/

# Re-resolve packages
echo "Resolving Swift packages..."
xcodebuild -resolvePackageDependencies -project MeetMemento.xcodeproj > /dev/null 2>&1

echo "✅ Deep clean complete! You can now build or clean the project in Xcode."
