# MediaWatch

A privacy-focused iOS app for tracking TV shows and movies with CloudKit sharing.

## Overview

MediaWatch is designed to be **simple, private, and shareable**. Track what you watch, organize content into lists, and share those lists with family members via iCloud.

## Key Features

- **Content Tracking**: Movies and TV shows with episode-level tracking
- **Lists**: Organize content into multiple custom lists
- **Sharing**: Share lists with other Apple ID users via CloudKit
- **Privacy**: Notes are private by default; your data stays on your devices and iCloud
- **Offline**: Full offline functionality with automatic sync
- **Backup**: Export/import JSON or ZIP backups

## Documentation

Detailed documentation is available in the `Documentation/` folder:

| Document | Description |
|----------|-------------|
| [REQUIREMENTS.md](Documentation/REQUIREMENTS.md) | Feature requirements and specifications |
| [DATA_MODELS.md](Documentation/DATA_MODELS.md) | Core Data entities and relationships |
| [ARCHITECTURE.md](Documentation/ARCHITECTURE.md) | MVVM architecture with SwiftUI |
| [CLOUDKIT_SYNC.md](Documentation/CLOUDKIT_SYNC.md) | CloudKit configuration and sharing |
| [UI_UX_DESIGN.md](Documentation/UI_UX_DESIGN.md) | Screen designs and user flows |
| [IMPLEMENTATION_ROADMAP.md](Documentation/IMPLEMENTATION_ROADMAP.md) | Phased development plan |

## Requirements

- iOS 17.0+
- iPadOS 17.0+
- Xcode 15+
- Apple Developer Account
- TMDb API Key

## Getting Started

### 1. Clone the Repository

```bash
git clone <repository-url>
cd MediaWatch
```

### 2. Open in Xcode

```bash
open MediaWatch.xcodeproj
```

### 3. Configure Signing

1. Select the MediaWatch target
2. Go to "Signing & Capabilities"
3. Select your team
4. Update the bundle identifier

### 4. Set Up CloudKit

1. Enable iCloud capability
2. Check "CloudKit"
3. Create container: `iCloud.com.<your-team>.MediaWatch`
4. Enable Push Notifications capability

### 5. Add TMDb API Key

Get an API key from [TMDb](https://www.themoviedb.org/documentation/api) and add it to your configuration.

### 6. Build and Run

Build the project (⌘B) and run on a device or simulator.

## Architecture

MediaWatch uses a clean MVVM architecture:

```
┌─────────────────┐
│  SwiftUI Views  │
└────────┬────────┘
         │
┌────────▼────────┐
│   ViewModels    │
│  (@Observable)  │
└────────┬────────┘
         │
┌────────▼────────┐
│    Services     │
└────────┬────────┘
         │
┌────────▼────────┐
│   Core Data +   │
│    CloudKit     │
└─────────────────┘
```

## Data Model

```
List ──< ListItem >── Title ──< Episode
                        │
                        └──< Note
```

- **List**: User-created collections
- **Title**: Movies or TV shows
- **Episode**: Individual episodes (TV only)
- **Note**: User notes (private by default)

## Project Structure

```
MediaWatch/
├── App/              # App entry, delegates
├── Core/             # Persistence, services
├── Features/         # Feature modules
│   ├── Library/      # Lists and content
│   ├── Search/       # Find and add
│   ├── TitleDetail/  # Title views
│   └── Settings/     # Preferences
├── Models/           # Core Data, DTOs
└── Resources/        # Assets, strings
```

## Development Phases

1. **Foundation** - Project setup, Core Data, architecture
2. **TMDb Integration** - API service, image caching
3. **Core Features** - Lists, tracking, notes
4. **User Interface** - All SwiftUI views
5. **CloudKit Sharing** - Share lists between users
6. **Backup & Restore** - Export/import functionality
7. **Polish & Testing** - UX refinement, testing
8. **Release** - App Store preparation

See [IMPLEMENTATION_ROADMAP.md](Documentation/IMPLEMENTATION_ROADMAP.md) for details.

## Not Included (By Design)

- Notifications
- Widgets
- In-app purchases
- Ads
- Social features
- Analytics

## Tech Stack

- **UI**: SwiftUI
- **Architecture**: MVVM with @Observable
- **Persistence**: Core Data + CloudKit
- **Networking**: Swift Concurrency (async/await)
- **API**: TMDb API v3

## Contributing

This is a personal project, but suggestions are welcome via issues.

## License

Private project - all rights reserved.

## Acknowledgments

- [TMDb](https://www.themoviedb.org) for movie/TV metadata
- Apple for CloudKit and SwiftUI
