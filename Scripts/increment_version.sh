#!/bin/bash

# Auto-increment build number for every build
# Increments CURRENT_PROJECT_VERSION in project file

PROJECT_FILE="$PROJECT_DIR/MediaWatch.xcodeproj/project.pbxproj"
CURRENT_BUILD=$(grep -m 1 "CURRENT_PROJECT_VERSION = " "$PROJECT_FILE" | sed 's/.*= \([0-9]*\);.*/\1/')
NEW_BUILD=$((CURRENT_BUILD + 1))

sed -i '' "s/CURRENT_PROJECT_VERSION = $CURRENT_BUILD;/CURRENT_PROJECT_VERSION = $NEW_BUILD;/g" "$PROJECT_FILE"
echo "🔨 Build: $CURRENT_BUILD → $NEW_BUILD"