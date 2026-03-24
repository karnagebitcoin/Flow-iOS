# Flow iOS Home Feed Migration Tracker

Last updated: 2026-03-21

## Scope

This tracker covers parity between:
- Web source: `/Users/k/code/x21`
- iOS target: `/Users/k/code/x21-ios`

Current phase:
- Welcome + onboarding gate
- Authenticated Home feed
- Thread/detail view from Home rows
- Profile surface + mobile slideout menu parity

## Status Legend

- `DONE`: Implemented in iOS
- `PARTIAL`: Implemented, but missing important web behavior
- `TODO`: Not implemented yet

## Parity Checklist (Home Feed + Thread)

| Capability | Web Source of Truth | iOS Status | Notes |
|---|---|---|---|
| Default relay feed (`nostr.wine`) | `src/providers/FeedProvider.tsx` | `DONE` | iOS starts at `wss://nostr.wine/` after auth gate. |
| Welcome screen + onboarding handoff to signup/signin | `src/components/AccountManager/SignupOnboarding.tsx` + `src/components/AccountManager/index.tsx` | `DONE` | Logged-out users now see dedicated welcome/onboarding flow and open auth/signup from there. |
| Feed list with Notes/Replies mode | `src/components/NormalFeed/index.tsx` | `DONE` | Segmented control implemented. |
| Relay timeline fetch (`kind:1`) | `src/components/NoteList/index.tsx` + `client.service.ts` | `DONE` | WebSocket REQ/EVENT/EOSE flow in iOS client. |
| Pull-to-refresh | `src/components/NoteList/index.tsx` | `DONE` | Native `.refreshable`. |
| Incremental pagination/load more | `src/components/NoteList/index.tsx` + `client.service.ts` | `DONE` | On-scroll load-more implemented. |
| Stable timeline key generation | `src/services/client/timeline-key.ts` | `DONE` | SHA256 canonical key ported. |
| In-flight timeline request de-dup | `src/services/client.service.ts` timeline patterns | `DONE` | Shared task reuse in `TimelineEventCache`. |
| Bounded timeline memory cache | `src/services/client.service.ts` (`BoundedMap`) | `DONE` | Bounded in-memory cache plus disk-backed recent feed snapshot warm-start. |
| Profile metadata hydration (`kind:0`) | `client.service.ts` + `profile-prefetch.ts` | `DONE` | Author profiles + mention pubkeys resolved. |
| Profile cache + known misses | `profile-prefetch.ts` + replaceable caches | `PARTIAL` | Memory-only cache; no disk priming yet. |
| Home row -> Thread navigation | Web note interaction flows | `DONE` | Native navigation destination from feed item. |
| Thread view surface (root + replies) | Web note/reply surfaces | `DONE` | Dedicated single-note root card now includes author header + follow affordance, content-first body, horizontal media carousel, social action row, and docked reply composer, with replies below. |
| Thread reply query by `#e` references | Web event/tag logic | `DONE` | Direct + nested reply fetch pass implemented. |
| Hashtag feed navigation (`#tag` -> filtered timeline) | `EmbeddedHashtag.tsx` + `toNoteList` + `NoteListPage` | `DONE` | Tapping hashtags now opens a dedicated hashtag timeline using `#t` relay filters, with pagination and thread drill-in. |
| Avatar tap action sheet (`Follow`, `View Profile`) | Mobile note interactions (`NoteCard`/profile affordances) | `DONE` | Home, thread, hashtag, and profile note rows now open native action sheet from avatar taps. |
| Profile view route + author timeline (`Notes` / `Replies`) | `src/components/Profile/index.tsx` + `src/components/Profile/ProfileFeed.tsx` | `DONE` | Native profile screen renders metadata (name, handle, npub, about, banner/avatar, NIP-05, website, lightning, following count) and author feed segmented by notes/replies. |
| Mobile top-left menu button + slideout | `src/components/MobileTopNavMenuButton/index.tsx` | `DONE` | Home now uses fixed custom top nav with left profile button opening slideout menu (`View Profile`, `Manage Accounts`, `Log Out`). |
| Realtime `onNew` notes behavior | `client.service.ts` subscribe flow | `DONE` | Live relay subscription buffers events only after initial `EOSE`, mirroring web `onNew` intent. |
| New Notes banner behavior | `src/components/NewNotesButton` | `DONE` | Native in-feed button shows buffered new note count and inserts on tap. |
| Sign in / sign up account flow (nsec + npub) | `NostrProvider` + `AccountManager` | `DONE` | Native auth sheet supports private/public key login, key generation signup, account persistence, switch/remove/logout. |
| Reaction stats fetch with local cache + note matching | `services/note-stats.service.ts` + `indexed-db.service.ts` | `DONE` | iOS now preloads cached reaction stats, batches kind-7 fetches by `#e`, matches reactions onto tracked note IDs, and persists refreshed stats locally. |
| Kind filter UI (voice/photo/video/polls/etc.) | `KindFilter` + `KindFilterProvider` | `DONE` | Native toolbar filter menu with grouped kind toggles, View All, reset/default-save actions. |
| Media-only filter | `MediaOnlyProvider` + note filtering | `DONE` | Media-only toggle ported with URL/imeta media detection and filtered-out empty-state recovery action. |
| Mute/content policy filtering | `MuteListProvider` + `ContentPolicyProvider` | `TODO` | Not started. |
| Trusted/untrusted filtering | `UserTrustProvider` | `TODO` | Not started. |
| Repost/quote note rendering | `NoteCard` (`RepostNoteCard`) | `TODO` | Not started. |
| Media cards (image/video/voice) | `MainNoteCard` + media parsing | `PARTIAL` | iOS rows now render image grids, video players, and audio players from content + `imeta` tags. |
| Rich text parsing (mentions/hashtags/urls) | note rendering utilities | `PARTIAL` | iOS now parses and renders clickable URLs, hashtags (opening hashtag feed), and Nostr URIs (`npub`/`nprofile`/`note`/`nevent`/`naddr`, including bare and `nostr:` forms), plus website preview cards; cashtag/LN invoice rendering parity is still pending. |
| Relay close reason handling | `NoteList` `showRelayCloseReason` | `TODO` | Not started. |
| Recent feed persistent cache | `indexed-db.service.ts` (`RECENT_FEEDS`) | `DONE` | Disk-backed snapshot cache added; Home can warm-start from cached feed then silently refresh. |
| Multi-relay merged timeline behavior | `subscribeTimeline` merged timelines | `TODO` | Current iOS uses single relay feed only. |
| Metadata relay tiering fallback | `metadata-relay-tiers.ts` | `TODO` | Not started. |

## Implemented iOS Files (Current)

- App bootstrap:
  - `/Users/k/code/x21-ios/Sources/App/FlowApp.swift`
- Auth:
  - `/Users/k/code/x21-ios/Sources/Auth/AuthModels.swift`
  - `/Users/k/code/x21-ios/Sources/Auth/AuthStore.swift`
  - `/Users/k/code/x21-ios/Sources/Auth/AuthManager.swift`
  - `/Users/k/code/x21-ios/Sources/Auth/AuthSheetView.swift`
- Onboarding:
  - `/Users/k/code/x21-ios/Sources/Onboarding/WelcomeOnboardingView.swift`
- Feed models/client/service/cache:
  - `/Users/k/code/x21-ios/Sources/Feed/NostrModels.swift`
  - `/Users/k/code/x21-ios/Sources/Feed/NostrRelayClient.swift`
  - `/Users/k/code/x21-ios/Sources/Feed/NostrFeedService.swift`
  - `/Users/k/code/x21-ios/Sources/Feed/NoteContentParser.swift`
  - `/Users/k/code/x21-ios/Sources/Feed/FeedFilterConfig.swift`
  - `/Users/k/code/x21-ios/Sources/Feed/HomeFeedFilterStore.swift`
  - `/Users/k/code/x21-ios/Sources/Feed/TimelineKey.swift`
  - `/Users/k/code/x21-ios/Sources/Feed/FeedCaches.swift`
  - `/Users/k/code/x21-ios/Sources/Feed/RecentFeedStore.swift`
  - `/Users/k/code/x21-ios/Sources/Feed/NoteReactionStatsStore.swift`
  - `/Users/k/code/x21-ios/Sources/Feed/NoteReactionStatsService.swift`
  - `/Users/k/code/x21-ios/Sources/Feed/RelayMessageParser.swift`
  - `/Users/k/code/x21-ios/Sources/Feed/NostrLiveFeedSubscriber.swift`
- Home UI:
  - `/Users/k/code/x21-ios/Sources/Home/HomeFeedViewModel.swift`
  - `/Users/k/code/x21-ios/Sources/Home/HomeFeedView.swift`
  - `/Users/k/code/x21-ios/Sources/Home/HomeSlideoutMenuView.swift`
  - `/Users/k/code/x21-ios/Sources/Hashtag/HashtagFeedViewModel.swift`
  - `/Users/k/code/x21-ios/Sources/Hashtag/HashtagFeedView.swift`
  - `/Users/k/code/x21-ios/Sources/Design/FeedRowView.swift`
  - `/Users/k/code/x21-ios/Sources/Design/NoteContentView.swift`
  - `/Users/k/code/x21-ios/Sources/Design/RelativeTimestampFormatter.swift`
- Profile UI:
  - `/Users/k/code/x21-ios/Sources/Profile/ProfileRoute.swift`
  - `/Users/k/code/x21-ios/Sources/Profile/ProfileViewModel.swift`
  - `/Users/k/code/x21-ios/Sources/Profile/ProfileView.swift`
  - `/Users/k/code/x21-ios/Sources/Profile/FollowStore.swift`
- Thread UI:
  - `/Users/k/code/x21-ios/Sources/Thread/ThreadDetailViewModel.swift`
  - `/Users/k/code/x21-ios/Sources/Thread/ThreadDetailView.swift`

## Recommended Next Port (Highest ROI)

1. Signed interactions parity (react/reply/repost publish flow).
2. Repost/quote/media note card rendering parity.
3. Content policy + mute/trust filtering parity.
4. Metadata relay tiering fallback parity.
5. Multi-relay merged timeline parity.

## Session Update Rule

For each future session:
- Update this file first when a feature is added.
- Mark `DONE/PARTIAL/TODO`.
- Link the web source file that defines expected behavior.
