# Gotm Feature Wishlist - Status Report

## ✅ FULLY IMPLEMENTED

| Feature | Status | Details |
|---------|--------|---------|
| **Working Auto-Tags** | ✅ 90% | 11 tag types with rule-based detection (Question, Reminder, Event, Action, Reference, Purchase, Money, etc.). AI-powered Person detection. Shows on cards with icons. |
| **High Accuracy Speech-to-Text** | ✅ 85% | 3-tier system: SFSpeechRecognizer (instant) → Deepgram nova-2 (refinement) → WhisperKit (offline fallback). Context-aware AI formatting. |
| **Intuitive & Beautiful UI/UX** | ✅ 80% | Clean card-based feed, quick record with swipe-to-lock, compose bar, attachment support, selection mode. Design system in progress. |

## 🟡 PARTIALLY IMPLEMENTED

| Feature | Status | What's Missing | Priority |
|---------|--------|----------------|----------|
| **Quick Model Load Time** | 🟡 60% | Warm-up on launch, but WhisperKit still slow on first load. Needs pre-download or lighter model. | Medium |
| **Multi-Language & Auto-Detection** | 🟡 40% | Deepgram has `detect_language=true`, but no UI to select language. AI formatting assumes English. No non-English models. | High |
| **Notes Frontend** | 🟡 70% | Basic note cards with transcript preview. No rich text, no markdown, no formatting toolbar. | Medium |

## ❌ NOT IMPLEMENTED

| Feature | Status | Complexity | Business Value |
|---------|--------|------------|----------------|
| **Full-Auto Apple Integrations** | ❌ 0% | High | Very High |
| ├─ Apple Notes | ❌ | Medium | High |
| ├─ Reminders | ❌ | Medium | High |
| ├─ Calendar | ❌ | Medium | High |
| ├─ Alarms | ❌ | Low | Medium |
| ├─ Email | ❌ | High | Medium |
| └─ Lists | ❌ | Medium | Medium |
| **Automatic Backend Connections** | ❌ 0% | High | High |
| **Notes/Project Folders** | ❌ 0% | Low | High |
| **Action Button Shortcut** | ❌ 0% | Low | Very High |
| **iCloud Sync** | ❌ 0% | Medium | Very High |

---

## Implementation Roadmap

### Phase 4: Apple Ecosystem Integration (Biggest Gap)
**Goal:** Auto-export to Apple apps based on tags

**Implementation Plan:**
1. **EventKit Integration** (Calendar + Reminders)
   - Add `import EventKit`
   - Request calendar/reminders permission
   - On "Event" tag → create EKEvent
   - On "Reminder" tag → create EKReminder
   - Show success/failure feedback

2. **Apple Notes Export**
   - Use `AppIntents` framework
   - Create "Export to Notes" action
   - Format transcript as note body
   - Add title and tags as hashtags

3. **Shortcuts App Integration**
   - Create App Intent for "Create Note"
   - Allow Siri: "Create a note in Gotm"
   - Enable Shortcuts automation

4. **Action Button (iPhone 15 Pro)**
   - `UIApplication.shared.applicationIconBadgeNumber`
   - Override `application(_:performActionFor:)`
   - Quick record from lock screen

### Phase 5: Organization & Sync

1. **Folders/Projects**
   - Add `folder: String?` to `RecordingEntry`
   - Create folder picker UI
   - Filter feed by folder
   - Move entries between folders

2. **iCloud Sync**
   - Add `import CloudKit`
   - Create `CKRecord` mapping
   - Sync on save
   - Handle conflicts

3. **Multi-Language**
   - Language picker in settings
   - Download Whisper models per language
   - AI prompt localization
   - Date/time formatting per locale

### Phase 6: Polish

1. **Rich Text Editor**
   - Markdown support
   - Bold/italic/headings
   - Checklist items → actual Reminders

2. **Widget**
   - Home screen widget for quick record
   - Recent notes preview

---

## Current Rating by Category

| Category | Score | Notes |
|----------|-------|-------|
| Core Recording | 9/10 | Excellent 3-tier transcription |
| Auto-Tagging | 8/10 | Comprehensive rule-based system |
| Security | 9/10 | Encrypted, API key protected |
| Stability | 8/10 | Race conditions fixed, retry logic |
| Apple Integration | 2/10 | Biggest gap - no EventKit, no Shortcuts |
| Organization | 3/10 | No folders, no sync |
| Multi-Language | 3/10 | Auto-detection enabled but not utilized |
| **Overall** | **6.5/10** | Solid foundation, missing integrations |

---

## MVP vs Full Product

### Current App = Good MVP ✅
- Records voice
- Transcribes accurately  
- Auto-tags content
- Shows in feed

### Ship-Ready Product Needs:
1. **Action Button** (iPhone 15 Pro differentiator)
2. **Apple Integrations** (Calendar/Reminders export)
3. **Folders** (basic organization)
4. **iCloud Sync** (data persistence)
5. **Language Selection** (broader market)

**Estimated Work:** 2-3 weeks for Phase 4 (Apple integrations)
