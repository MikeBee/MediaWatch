# Version Management Guide

## Overview

The MediaWatch project now includes automated version management for both TestFlight releases and Profile page updates.

## Current Configuration

- **Auto-increment**: Enabled for all builds via Xcode build phase
- **Current Version**: 1.58 (Build 25)
- **Mode**: TestFlight (increments both marketing version and build number)

## Scripts

### 1. `increment_version.sh`
- Called automatically by Xcode build phase
- Defaults to TestFlight mode
- Runs before compilation

### 2. `version_manager.sh`
- Manual version control script
- Supports multiple modes

## Usage

### Automatic (Recommended)
Every time you build in Xcode, versions are automatically incremented for TestFlight.

### Manual Control

```bash
# For TestFlight builds (increments both version and build)
./Scripts/version_manager.sh testflight

# For Profile page updates (build number only)
./Scripts/version_manager.sh profile

# Manual version setting
./Scripts/version_manager.sh manual 2.0 1

# Manual build increment only
./Scripts/version_manager.sh manual "" 50
```

## Modes

### TestFlight Mode
- **Marketing Version**: 1.58 → 1.59
- **Build Number**: 25 → 26
- Use for: App Store Connect TestFlight releases

### Profile Mode
- **Marketing Version**: 1.58 (unchanged)
- **Build Number**: 25 → 26
- Use for: Internal testing, Profile page updates

### Manual Mode
- Set specific version and/or build numbers
- Use for: Major releases, specific versioning needs

## Version History

All version changes are logged in `Scripts/version_history.log` with timestamps.

## Integration Notes

- The build script runs as the first build phase
- Versions are updated before compilation
- All build configurations (Debug/Release) are synchronized
- CloudKit sync logs show successful merge between devices

## Next Steps

1. **TestFlight Releases**: Build normally, versions auto-increment
2. **Profile Updates**: Use `./Scripts/version_manager.sh profile`
3. **Major Releases**: Use manual mode for semantic versioning