#!/bin/bash

# Version Manager for MediaWatch
# Usage: version_manager.sh [testflight|profile|manual] [major.minor] [build_number]

set -e

PROJECT_FILE="$PROJECT_DIR/MediaWatch.xcodeproj/project.pbxproj"

if [ ! -f "$PROJECT_FILE" ]; then
    echo "Error: Project file not found at $PROJECT_FILE"
    exit 1
fi

MODE="${1:-testflight}"
CUSTOM_VERSION="$2"
CUSTOM_BUILD="$3"

# Get current versions
CURRENT_MARKETING_VERSION=$(grep -m 1 "MARKETING_VERSION = " "$PROJECT_FILE" | sed 's/.*MARKETING_VERSION = \([0-9.]*\);.*/\1/')
CURRENT_BUILD_NUMBER=$(grep -m 1 "CURRENT_PROJECT_VERSION = " "$PROJECT_FILE" | sed 's/.*CURRENT_PROJECT_VERSION = \([0-9]*\);.*/\1/')

echo "📱 Current Marketing Version: $CURRENT_MARKETING_VERSION"
echo "🔨 Current Build Number: $CURRENT_BUILD_NUMBER"
echo "⚙️  Mode: $MODE"

case "$MODE" in
    "testflight")
        # Auto-increment both version and build for TestFlight
        if [[ $CURRENT_MARKETING_VERSION =~ ^([0-9]+)\.([0-9]+)$ ]]; then
            MAJOR=${BASH_REMATCH[1]}
            MINOR=${BASH_REMATCH[2]}
            NEW_MINOR=$((MINOR + 1))
            NEW_MARKETING_VERSION="$MAJOR.$NEW_MINOR"
        else
            echo "⚠️  Unexpected version format, incrementing build only"
            NEW_MARKETING_VERSION=$CURRENT_MARKETING_VERSION
        fi
        NEW_BUILD_NUMBER=$((CURRENT_BUILD_NUMBER + 1))
        ;;
    
    "profile")
        # Increment build number only for Profile page updates
        NEW_MARKETING_VERSION=$CURRENT_MARKETING_VERSION
        NEW_BUILD_NUMBER=$((CURRENT_BUILD_NUMBER + 1))
        ;;
    
    "manual")
        # Use provided versions
        if [ -n "$CUSTOM_VERSION" ]; then
            NEW_MARKETING_VERSION="$CUSTOM_VERSION"
        else
            NEW_MARKETING_VERSION=$CURRENT_MARKETING_VERSION
        fi
        
        if [ -n "$CUSTOM_BUILD" ]; then
            NEW_BUILD_NUMBER="$CUSTOM_BUILD"
        else
            NEW_BUILD_NUMBER=$((CURRENT_BUILD_NUMBER + 1))
        fi
        ;;
    
    *)
        echo "❌ Invalid mode. Use: testflight, profile, or manual"
        echo "Usage: version_manager.sh [testflight|profile|manual] [major.minor] [build_number]"
        exit 1
        ;;
esac

echo ""
echo "📱 New Marketing Version: $NEW_MARKETING_VERSION"
echo "🔨 New Build Number: $NEW_BUILD_NUMBER"
echo ""

# Update project file
sed -i '' "s/MARKETING_VERSION = $CURRENT_MARKETING_VERSION;/MARKETING_VERSION = $NEW_MARKETING_VERSION;/g" "$PROJECT_FILE"
sed -i '' "s/CURRENT_PROJECT_VERSION = $CURRENT_BUILD_NUMBER;/CURRENT_PROJECT_VERSION = $NEW_BUILD_NUMBER;/g" "$PROJECT_FILE"

echo "✅ Version numbers updated successfully!"
echo "📱 Marketing Version: $CURRENT_MARKETING_VERSION → $NEW_MARKETING_VERSION"
echo "🔨 Build Number: $CURRENT_BUILD_NUMBER → $NEW_BUILD_NUMBER"

# Log the change for reference
DATE=$(date '+%Y-%m-%d %H:%M:%S')
echo "[$DATE] $MODE: $CURRENT_MARKETING_VERSION ($CURRENT_BUILD_NUMBER) → $NEW_MARKETING_VERSION ($NEW_BUILD_NUMBER)" >> "$PROJECT_DIR/Scripts/version_history.log"