#!/bin/sh
set -e

xcodebuild -project RSSwizzleTests/RSSwizzleTests.xcodeproj -scheme RSSwizzleTests-iOS -sdk iphonesimulator -destination OS=7.0,name=iPad -configuration Release test
xcodebuild -project RSSwizzleTests/RSSwizzleTests.xcodeproj -scheme RSSwizzleTests-iOS -sdk iphonesimulator -destination OS=6.1,name=iPhone -configuration Release test
xcodebuild -project RSSwizzleTests/RSSwizzleTests.xcodeproj -scheme RSSwizzleTests-iOS -sdk iphonesimulator -destination OS=5.0,name=iPhone -configuration Release test

