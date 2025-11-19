# MediaWatch - Feature Requirements

## Overview

MediaWatch is a privacy-focused iOS app for tracking TV shows and movies. It emphasizes simplicity, offline-first functionality, and secure sharing between users via CloudKit.

**Target Platforms:** iOS 17.0+, iPadOS 17.0+

---

## 1. Core Features

### 1.1 Content Tracking

#### Movies
- **Required Fields:**
  - Title (String)
  - Year (Int16)
  - TMDb ID (Int64) - Primary external identifier
  - Runtime in minutes (Int16)
  - Poster image path (String, cached locally)
  - Backdrop image path (String, cached locally)

- **Optional Fields:**
  - IMDb ID (String)
  - Synopsis/Overview (String)
  - Genres (Array of Strings, stored as transformable)
  - Original language (String)
  - Original title (String)

#### TV Shows
- All movie fields plus:
  - Number of seasons (Int16)
  - Number of episodes (Int16)
  - Status (String: "Returning Series", "Ended", "Canceled", etc.)
  - First air date (Date)
  - Last air date (Date, optional)
  - Episode runtime (Int16, average)

#### Episodes
- **Required Fields:**
  - Season number (Int16)
  - Episode number (Int16)
  - Name/Title (String)
  - Parent TV Show reference

- **Optional Fields:**
  - Synopsis/Overview (String)
  - Air date (Date)
  - Still image path (String)
  - Runtime (Int16)

### 1.2 User Tracking Data

#### Watch Status
- **Movies:** Boolean watched/unwatched
- **Episodes:** Boolean watched/unwatched per episode
- **TV Shows:** Calculated from episode watch status (percentage/count)

#### Watch Date
- Date when marked as watched (auto-set, user-editable)

#### Liked Status (Tri-state)
- Liked (1)
- Neutral (0) - Default
- Disliked (-1)

Applies to: Movies and TV Shows (not individual episodes)

### 1.3 Notes

- **Scope:** Can be attached to Movies, TV Shows, or Episodes
- **Content:** Plain text or Markdown (stored as String)
- **Privacy:** `ownerOnly` flag (Boolean)
  - `true`: Only visible to note creator (even in shared lists)
  - `false`: Visible to all users with list access
- **Default:** `ownerOnly = true`

### 1.4 Lists

#### Requirements
- Every Title (Movie/TV Show) MUST belong to at least one List
- Titles cannot exist outside of Lists
- A Title can belong to multiple Lists

#### List Properties
- Name (String, required)
- Color/Icon (optional, for visual distinction)
- Sort order (Int16)
- Created date (Date)
- Modified date (Date)

#### List Membership (ListItem)
- Reference to Title
- Order index within list (Int16)
- Date added to list (Date)

### 1.5 Sharing via CloudKit

#### Shareable Entities
- Lists (primary shareable unit)
- Titles within shared Lists (automatically included)
- Episodes of shared Titles (automatically included)
- Notes with `ownerOnly = false`

#### Sharing Flow
1. User taps share button on a List
2. System presents CloudKit share sheet
3. User enters Apple ID email or selects from contacts
4. Recipient receives invitation via Messages/Email
5. Recipient accepts and List appears in their app
6. Both users can view/edit shared content

#### Permissions
- **Read-only:** Can view content, cannot modify
- **Read-write:** Full edit access to shared content

#### Conflict Resolution
- Last-modified-wins per field
- Each field has its own modification timestamp
- CloudKit handles merge conflicts automatically

### 1.6 Search and Add Flow

#### Search
- Query TMDb API for movies and TV shows
- Display results with poster, title, year, overview
- Support search filtering by type (Movie/TV)

#### Add Flow (REQUIRED SEQUENCE)
1. User searches for title
2. User selects title from results
3. **REQUIRED:** User selects destination List(s)
4. **OPTIONAL:** Set liked status
5. **OPTIONAL:** Add initial note
6. Save to local database
7. Fetch full metadata and images from TMDb
8. Sync to CloudKit

### 1.7 Backup & Restore

#### Export Formats
- **JSON:** Structured data only
- **ZIP:** JSON + cached images

#### Export Content
- All Lists
- All Titles with metadata
- All Episodes
- All Notes
- All watch status and dates
- User preferences

#### Import Options
- **Merge:** Add to existing data, skip duplicates (by TMDb ID)
- **Replace:** Clear existing data, import fresh

#### Storage Options
- Save to Files app
- Save to iCloud Drive
- Share via AirDrop/other apps

---

## 2. User Interface Requirements

### 2.1 iPhone Layout

#### Tab Bar Navigation
1. **Library** - Lists and content
2. **Search** - Find and add new titles
3. **Settings** - Preferences and backup

#### Library Tab (iPhone)
- List of all Lists with item counts
- Tap List to see Titles
- Progress indicators for watch completion
- Swipe actions for quick operations

#### Title Detail (iPhone)
- Full-screen scrollable view
- Hero image (backdrop/poster)
- Metadata section
- Watch/Liked status controls
- Episodes list (for TV Shows)
- Notes section
- List membership

### 2.2 iPad Layout

#### Split View Navigation
- **Sidebar:** Lists navigation
- **Content:** Titles in selected List
- **Detail:** Full Title/Episode detail

#### Multi-Column Display
- 2-column layout in compact width
- 3-column layout in regular width
- Optimized for landscape orientation

#### Enhanced Features
- Drag and drop between Lists
- Multi-select for batch operations
- Keyboard shortcuts
- Hover effects and context menus

### 2.3 Common UI Patterns

#### Progress Indicators
- Circular progress for TV Shows (episodes watched)
- Checkmark for watched Movies
- Color coding for liked status

#### Image Handling
- Placeholder images during load
- Progressive loading for large images
- Cached locally for offline access

#### Empty States
- Helpful messages and actions when Lists are empty
- First-run onboarding guidance

---

## 3. Technical Requirements

### 3.1 Offline Support

- **Full offline functionality** for read/write operations
- Local Core Data persistence
- Automatic sync when connectivity restored
- Sync status indicators
- Queue pending changes during offline

### 3.2 CloudKit Configuration

#### Container
- Use NSPersistentCloudKitContainer
- Custom container identifier: `iCloud.com.yourcompany.MediaWatch`

#### Zones
- **Private Zone:** User's personal data
- **Shared Zone:** Data shared with others

#### Record Types (auto-generated from Core Data)
- CD_Title
- CD_Episode
- CD_List
- CD_ListItem
- CD_Note

### 3.3 TMDb Integration

#### API Requirements
- API key stored securely (Keychain or build config)
- Rate limiting compliance
- Error handling and retry logic

#### Endpoints Used
- `/search/multi` - Search movies and TV
- `/movie/{id}` - Movie details
- `/tv/{id}` - TV show details
- `/tv/{id}/season/{season}` - Season episodes
- `/configuration` - Image base URLs

#### Image Caching
- Download and cache locally
- Multiple sizes for different contexts
- Clean up orphaned images

### 3.4 Performance Requirements

- App launch < 2 seconds
- Search results < 1 second
- Smooth 60fps scrolling
- Background sync without UI blocking
- Efficient memory usage for images

---

## 4. Privacy & Security

### 4.1 Data Privacy
- No analytics or tracking
- No third-party SDKs
- Data stored only on device and user's iCloud
- Notes private by default

### 4.2 CloudKit Security
- End-to-end encryption for shared data
- Apple ID authentication
- User controls sharing permissions

### 4.3 API Security
- TMDb API key not exposed in app
- HTTPS for all network requests
- Certificate pinning (optional)

---

## 5. Explicitly Excluded Features

The following are intentionally NOT included:

- Push notifications
- Widgets
- In-app purchases or subscriptions
- Ads
- Social features (beyond sharing)
- Recommendations engine
- Calendar integration
- Siri shortcuts
- Watch app
- TV app integration
- Separate "Library" concept (only Lists)

---

## 6. Future Considerations

These may be added in future versions:

- JustWatch API integration for streaming providers
- Trakt.tv import/export
- Letterboxd import
- Advanced sorting and filtering
- Statistics and viewing history
- Dark/Light theme options
- Custom app icons

---

## 7. Success Metrics

The app will be considered successful if:

1. **Simplicity:** New users can add their first title within 30 seconds
2. **Reliability:** Sync works seamlessly between devices
3. **Sharing:** Two users can share a list within 1 minute
4. **Privacy:** User feels in control of their data
5. **Performance:** No lag or crashes during normal use
