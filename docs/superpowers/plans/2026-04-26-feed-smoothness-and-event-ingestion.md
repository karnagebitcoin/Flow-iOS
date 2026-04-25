# Feed Smoothness And Event Ingestion Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Eliminate feed jitter caused by staged row mutations and broad engagement invalidation while redesigning local storage so Halo can ingest, index, and retain a much larger event corpus safely.

**Architecture:** Split the work into two coordinated tracks. First, make feed lists render from stable row snapshots and move reactions to row-scoped, batched updates so scrolling is smooth even while counts refresh. Second, replace the current small cache-style mirror with a durable event archive in `Application Support`, keep Flow DB as the hot query index, and add a background ingestion coordinator that uses author outbox hints plus broad relay fallback.

**Tech Stack:** SwiftUI, Combine, SQLite3, FlowNostrDB, Nostr relay fetchers, XCTest, xcodebuild

---

## Scope Note

This plan intentionally keeps feed smoothness and ingestion in one document because they touch the same data path:

- `NostrFeedService` decides what data arrives and when rows get hydrated.
- `SeenEventStore` and `FlowNostrDB` decide what local corpus exists.
- `NoteReactionStatsService` decides how often visible rows update after first paint.

If execution needs to be parallelized, split tasks 1-4 as the "smooth scrolling" stream and tasks 5-8 as the "storage and ingestion" stream.

## Storage Decision

Do **not** jump straight to "store one million events in the current architecture."

With the current design:

- the SQLite mirror stores full JSON payloads
- Flow DB stores the same corpus again as the hot query index
- Flow DB rebuilds from a recent subset when thresholds are hit

That makes `1_000_000` events likely a multi-gigabyte footprint with expensive rebuilds. The safe target is:

- **archive layer:** allow up to `1_000_000` events, but enforce a byte budget
- **hot Flow DB index:** keep a smaller working set, not the full archive
- **derived caches:** keep them rebuildable and purgeable

Recommended rollout:

- Milestone A: archive target `250_000` events or `500 MB`, hot index `120_000`
- Milestone B: archive target `500_000` events or `1.0 GB`, hot index `180_000`
- Milestone C: archive target `1_000_000` events or `1.5 GB`, hot index `250_000`, only if device-free-space and rebuild benchmarks stay healthy

## File Map

### Feed smoothness

- Modify: `Sources/Feed/NoteReactionStatsService.swift`
  Row-scoped snapshots, batched publish behavior, fetch batching
- Modify: `Sources/Design/FeedRowView.swift`
  Use a row-local engagement snapshot and stop relying on parent-wide reaction observation
- Modify: `Sources/Home/HomeFeedView.swift`
  Remove broad reaction observation, wire viewport batching
- Modify: `Sources/Profile/ProfileView.swift`
  Remove broad reaction observation for profile list rows
- Modify: `Sources/Search/SearchView.swift`
  Remove broad reaction observation for search result rows
- Modify: `Sources/Hashtag/HashtagFeedView.swift`
  Remove broad reaction observation for hashtag list rows
- Modify: `Sources/Home/HomeFeedViewModel.swift`
  Stop mutating already-visible rows across multiple hydration passes
- Modify: `Sources/Profile/ProfileViewModel.swift`
  Same visible-row hydration rule for profile feeds
- Modify: `Sources/Hashtag/HashtagFeedViewModel.swift`
  Same visible-row hydration rule for hashtag feeds
- Modify: `Sources/Search/SearchViewModel.swift`
  Same visible-row hydration rule for search note results
- Create: `Sources/Feed/FeedEngagementViewportCoordinator.swift`
  Debounced, list-level engagement prefetch coordinator
- Create: `Sources/Feed/FeedPresentationCache.swift`
  Bounded cache of row-ready presentation snapshots

### Storage and ingestion

- Modify: `Sources/Feed/SeenEventStore.swift`
  Convert from "small mirror" into a facade over durable archive + hot index + recent-feed ordering
- Modify: `Sources/NostrDB/FlowNostrDB.swift`
  Keep Flow DB as the bounded hot index, not the sole durable store
- Modify: `Sources/Feed/NostrFeedService.swift`
  Read from archive-backed lookups, store fetched events through the new ingestion path
- Modify: `Sources/Profile/ProfileEventService.swift`
  Reuse relay list / inbox relay parsing for background ingestion targets
- Modify: `Sources/Feed/FeedCaches.swift`
  Extend relay hint persistence for ingestion decisions
- Modify: `Sources/App/FlowApp.swift`
  Start background ingestion with lifecycle-safe configuration
- Modify: `Sources/Home/SettingsMediaView.swift`
  Show archive size, archive count, hot index count, background ingestion health
- Create: `Sources/Feed/EventArchiveStore.swift`
  Durable SQLite archive in `Application Support`
- Create: `Sources/Feed/EventStorageBudget.swift`
  Byte-budget policy, free-space guardrails, rollout limits
- Create: `Sources/Feed/BackgroundIngestionCoordinator.swift`
  Self/follows/profile/thread background warming using outbox + broad fallback

### Tests

- Modify: `Tests/NoteReactionBonusTests.swift`
  Add publisher-isolation and batched-publish tests
- Modify: `Tests/HomeFeedViewModelTests.swift`
  Add single-commit hydration tests
- Modify: `Tests/NostrFeedServiceTests.swift`
  Add archive-first lookup and background-ingestion tests
- Modify: `Tests/FlowNostrDBTests.swift`
  Add hot-index budget and rebuild-seed tests
- Create: `Tests/FeedEngagementViewportCoordinatorTests.swift`
  Verify debounce and dedupe behavior
- Create: `Tests/EventArchiveStoreTests.swift`
  Verify durable archive lookup and byte-budget pruning
- Create: `Tests/BackgroundIngestionCoordinatorTests.swift`
  Verify outbox prioritization and fallback behavior

---

### Task 1: Make Feed Rows Reaction-Scoped Instead Of Screen-Scoped

**Files:**
- Modify: `Sources/Feed/NoteReactionStatsService.swift`
- Modify: `Sources/Design/FeedRowView.swift`
- Modify: `Sources/Home/HomeFeedView.swift`
- Modify: `Sources/Profile/ProfileView.swift`
- Modify: `Sources/Search/SearchView.swift`
- Modify: `Sources/Hashtag/HashtagFeedView.swift`
- Test: `Tests/NoteReactionBonusTests.swift`

- [ ] **Step 1: Write the failing tests for publisher isolation**

```swift
@MainActor
func testPublisherOnlyEmitsForTouchedEventID() async throws {
    let targetA = String(repeating: "a", count: 64)
    let targetB = String(repeating: "b", count: 64)
    let reactor = String(repeating: "c", count: 64)
    let service = NoteReactionStatsService(
        relayClient: SpyReactionRelayClient(),
        store: NoteReactionStatsStore(fileManager: ReactionTestFileManager(rootURL: temporaryRootURL()))
    )

    var valuesA: [Int] = []
    var valuesB: [Int] = []
    let cancellableA = service.publisher(for: targetA).sink { valuesA.append($0.reactionCount) }
    let cancellableB = service.publisher(for: targetB).sink { valuesB.append($0.reactionCount) }
    defer {
        cancellableA.cancel()
        cancellableB.cancel()
    }

    service.registerPublishedReaction(
        makeReactionEvent(
            id: String(repeating: "d", count: 64),
            pubkey: reactor,
            targetEventID: targetA,
            targetPubkey: String(repeating: "e", count: 64),
            bonusCount: 0
        ),
        targetEventID: targetA
    )

    XCTAssertEqual(valuesA, [0, 1])
    XCTAssertEqual(valuesB, [0])
}

@MainActor
func testCurrentSnapshotReturnsLatestStateWithoutObservation() async {
    let eventID = String(repeating: "f", count: 64)
    let reactor = String(repeating: "1", count: 64)
    let service = NoteReactionStatsService(
        relayClient: SpyReactionRelayClient(),
        store: NoteReactionStatsStore(fileManager: ReactionTestFileManager(rootURL: temporaryRootURL()))
    )

    service.registerPublishedReaction(
        makeReactionEvent(
            id: String(repeating: "2", count: 64),
            pubkey: reactor,
            targetEventID: eventID,
            targetPubkey: String(repeating: "3", count: 64),
            bonusCount: 0
        ),
        targetEventID: eventID
    )

    XCTAssertEqual(service.currentSnapshot(for: eventID).reactionCount, 1)
}
```

- [ ] **Step 2: Run the focused tests to verify the seam is missing**

Run:

```bash
xcodebuild test \
  -project /Users/k/code/x21-ios/Flow.xcodeproj \
  -scheme Flow \
  -destination 'platform=iOS Simulator,name=iPhone 17' \
  -only-testing:FlowTests/NoteReactionBonusTests
```

Expected: FAIL because `currentSnapshot(for:)` does not exist and the publisher isolation behavior is not yet guaranteed by tests.

- [ ] **Step 3: Add a non-observing snapshot API and remove list-wide reaction observation**

```swift
// Sources/Feed/NoteReactionStatsService.swift
@MainActor
func currentSnapshot(for eventID: String) -> NoteReactionEventSnapshot {
    snapshot(for: eventID)
}

// Sources/Home/HomeFeedView.swift
// Before:
// @ObservedObject private var reactionStats = NoteReactionStatsService.shared
// After:
private let reactionStats = NoteReactionStatsService.shared

private func feedRow(_ item: FeedItem, visibleReplyCounts: [String: Int]) -> some View {
    FeedRowView(
        item: item,
        initialEngagementSnapshot: reactionStats.currentSnapshot(for: item.displayEventID),
        commentCount: visibleReplyCounts[item.displayEventID.lowercased()] ?? 0,
        showReactions: appSettings.reactionsVisibleInFeeds,
        ...
    )
}

// Sources/Design/FeedRowView.swift
let initialEngagementSnapshot: NoteReactionEventSnapshot?

init(
    item: FeedItem,
    initialEngagementSnapshot: NoteReactionEventSnapshot? = nil,
    ...
) {
    self.item = item
    self.initialEngagementSnapshot = initialEngagementSnapshot
    _reactionSnapshot = State(initialValue: initialEngagementSnapshot)
}
```

- [ ] **Step 4: Apply the same reaction-store removal to the other list screens**

```swift
// Sources/Profile/ProfileView.swift
private let reactionStats = NoteReactionStatsService.shared

// Sources/Search/SearchView.swift
private let reactionStats = NoteReactionStatsService.shared

// Sources/Hashtag/HashtagFeedView.swift
private let reactionStats = NoteReactionStatsService.shared
```

Rows in those screens should pass `initialEngagementSnapshot:` once and let `FeedRowView` own live updates via its per-note publisher.

- [ ] **Step 5: Run the focused tests and a compile-only build**

Run:

```bash
xcodebuild test \
  -project /Users/k/code/x21-ios/Flow.xcodeproj \
  -scheme Flow \
  -destination 'platform=iOS Simulator,name=iPhone 17' \
  -only-testing:FlowTests/NoteReactionBonusTests

xcodebuild build \
  -project /Users/k/code/x21-ios/Flow.xcodeproj \
  -scheme Flow \
  -destination 'platform=iOS Simulator,name=iPhone 17'
```

Expected: PASS for the focused reaction test suite and PASS for compile-only build.

- [ ] **Step 6: Commit**

```bash
git add \
  Sources/Feed/NoteReactionStatsService.swift \
  Sources/Design/FeedRowView.swift \
  Sources/Home/HomeFeedView.swift \
  Sources/Profile/ProfileView.swift \
  Sources/Search/SearchView.swift \
  Sources/Hashtag/HashtagFeedView.swift \
  Tests/NoteReactionBonusTests.swift
git commit -m "refactor: scope feed reaction updates to rows"
```

### Task 2: Batch Engagement Prefetch At The Viewport Level

**Files:**
- Create: `Sources/Feed/FeedEngagementViewportCoordinator.swift`
- Modify: `Sources/Home/HomeFeedView.swift`
- Modify: `Sources/Profile/ProfileView.swift`
- Modify: `Sources/Search/SearchView.swift`
- Modify: `Sources/Hashtag/HashtagFeedView.swift`
- Modify: `Sources/Thread/ThreadDetailComponents.swift`
- Test: `Tests/FeedEngagementViewportCoordinatorTests.swift`

- [ ] **Step 1: Write the failing tests for debounce and dedupe**

```swift
@MainActor
func testCoordinatorBatchesVisibleEventsIntoSinglePrefetch() async throws {
    let spy = SpyEngagementPrefetchSink()
    let coordinator = FeedEngagementViewportCoordinator(prefetchSink: spy)
    let relayURL = try XCTUnwrap(URL(string: "wss://relay.example.com"))

    coordinator.noteVisible(event: makeReactionTargetEvent(id: String(repeating: "a", count: 64)), relayURLs: [relayURL])
    coordinator.noteVisible(event: makeReactionTargetEvent(id: String(repeating: "b", count: 64)), relayURLs: [relayURL])
    coordinator.noteVisible(event: makeReactionTargetEvent(id: String(repeating: "a", count: 64)), relayURLs: [relayURL])

    try await Task.sleep(nanoseconds: 250_000_000)

    let calls = await spy.calls()
    XCTAssertEqual(calls.count, 1)
    XCTAssertEqual(Set(calls[0].eventIDs), [
        String(repeating: "a", count: 64),
        String(repeating: "b", count: 64)
    ])
}
```

- [ ] **Step 2: Run the focused tests**

Run:

```bash
xcodebuild test \
  -project /Users/k/code/x21-ios/Flow.xcodeproj \
  -scheme Flow \
  -destination 'platform=iOS Simulator,name=iPhone 17' \
  -only-testing:FlowTests/FeedEngagementViewportCoordinatorTests
```

Expected: FAIL because the coordinator does not exist yet.

- [ ] **Step 3: Implement the coordinator**

```swift
// Sources/Feed/FeedEngagementViewportCoordinator.swift
@MainActor
final class FeedEngagementViewportCoordinator {
    struct Batch {
        let events: [NostrEvent]
        let relayURLs: [URL]
    }

    private let prefetchSink: NoteReactionStatsService
    private var pendingEventsByID: [String: NostrEvent] = [:]
    private var pendingRelayURLs: [String: URL] = [:]
    private var flushTask: Task<Void, Never>?

    init(prefetchSink: NoteReactionStatsService = .shared) {
        self.prefetchSink = prefetchSink
    }

    func noteVisible(event: NostrEvent, relayURLs: [URL]) {
        pendingEventsByID[event.id.lowercased()] = event
        for relayURL in relayURLs {
            pendingRelayURLs[relayURL.absoluteString.lowercased()] = relayURL
        }
        scheduleFlush()
    }

    private func scheduleFlush() {
        guard flushTask == nil else { return }
        flushTask = Task { @MainActor [weak self] in
            try? await Task.sleep(nanoseconds: 150_000_000)
            self?.flush()
        }
    }

    private func flush() {
        flushTask = nil
        let events = Array(pendingEventsByID.values)
        let relayURLs = Array(pendingRelayURLs.values)
        pendingEventsByID.removeAll()
        pendingRelayURLs.removeAll()
        guard !events.isEmpty, !relayURLs.isEmpty else { return }
        prefetchSink.prefetch(events: events, relayURLs: relayURLs)
    }
}
```

- [ ] **Step 4: Replace direct per-row prefetch calls**

```swift
// Sources/Home/HomeFeedView.swift
@StateObject private var engagementViewport = FeedEngagementViewportCoordinator()

.onAppear {
    if appSettings.reactionsVisibleInFeeds {
        engagementViewport.noteVisible(
            event: item.displayEvent,
            relayURLs: effectiveReadRelayURLs
        )
    }
    Task(priority: .utility) {
        await viewModel.loadMoreIfNeeded(currentItem: item)
    }
}
```

Apply the same coordinator wiring in profile, search, hashtag, and thread reply rows.

- [ ] **Step 5: Run tests and build**

Run:

```bash
xcodebuild test \
  -project /Users/k/code/x21-ios/Flow.xcodeproj \
  -scheme Flow \
  -destination 'platform=iOS Simulator,name=iPhone 17' \
  -only-testing:FlowTests/FeedEngagementViewportCoordinatorTests \
  -only-testing:FlowTests/NoteReactionBonusTests

xcodebuild build \
  -project /Users/k/code/x21-ios/Flow.xcodeproj \
  -scheme Flow \
  -destination 'platform=iOS Simulator,name=iPhone 17'
```

Expected: PASS.

- [ ] **Step 6: Commit**

```bash
git add \
  Sources/Feed/FeedEngagementViewportCoordinator.swift \
  Sources/Home/HomeFeedView.swift \
  Sources/Profile/ProfileView.swift \
  Sources/Search/SearchView.swift \
  Sources/Hashtag/HashtagFeedView.swift \
  Sources/Thread/ThreadDetailComponents.swift \
  Tests/FeedEngagementViewportCoordinatorTests.swift
git commit -m "feat: batch feed engagement prefetches"
```

### Task 3: Coalesce Reaction Batch Updates So Each Note Publishes Once Per Fetch

**Files:**
- Modify: `Sources/Feed/NoteReactionStatsService.swift`
- Test: `Tests/NoteReactionBonusTests.swift`

- [ ] **Step 1: Write the failing test for batch coalescing**

```swift
@MainActor
func testPrefetchPublishesOneSnapshotPerTouchedNotePerBatch() async throws {
    let targetEventID = String(repeating: "9", count: 64)
    let targetPubkey = String(repeating: "8", count: 64)
    let relayURL = try XCTUnwrap(URL(string: "wss://relay.example.com"))
    let targetEvent = makeReactionTargetEvent(id: targetEventID, pubkey: targetPubkey)
    let relayClient = SpyReactionRelayClient(events: [
        makeReplyEvent(
            id: String(repeating: "7", count: 64),
            pubkey: String(repeating: "6", count: 64),
            targetEventID: targetEventID,
            targetPubkey: targetPubkey
        ),
        makeRepostEvent(
            id: String(repeating: "5", count: 64),
            pubkey: String(repeating: "4", count: 64),
            targetEventID: targetEventID,
            targetPubkey: targetPubkey
        ),
        makeReactionEvent(
            id: String(repeating: "3", count: 64),
            pubkey: String(repeating: "2", count: 64),
            targetEventID: targetEventID,
            targetPubkey: targetPubkey,
            bonusCount: 0
        )
    ])
    let service = NoteReactionStatsService(
        relayClient: relayClient,
        store: NoteReactionStatsStore(fileManager: ReactionTestFileManager(rootURL: temporaryRootURL()))
    )

    var snapshots: [NoteReactionEventSnapshot] = []
    let cancellable = service.publisher(for: targetEventID).sink { snapshots.append($0) }
    defer { cancellable.cancel() }

    service.prefetch(events: [targetEvent], relayURLs: [relayURL])
    try await Task.sleep(nanoseconds: 200_000_000)

    XCTAssertEqual(snapshots.map(\.reactionCount), [0, 1])
    XCTAssertEqual(snapshots.last?.replyCount, 1)
    XCTAssertEqual(snapshots.last?.repostCount, 1)
}
```

- [ ] **Step 2: Run the focused test**

Run:

```bash
xcodebuild test \
  -project /Users/k/code/x21-ios/Flow.xcodeproj \
  -scheme Flow \
  -destination 'platform=iOS Simulator,name=iPhone 17' \
  -only-testing:FlowTests/NoteReactionBonusTests
```

Expected: FAIL because current merge logic can publish multiple times inside one fetch batch.

- [ ] **Step 3: Refactor batch merge logic to publish once per note**

```swift
// Sources/Feed/NoteReactionStatsService.swift
private func applyBatchResult(
    events: [NostrEvent],
    trackedEventIDs: Set<String>
) -> Set<String> {
    var nextStats = statsByEventID
    var touched = Set<String>()

    touched.formUnion(mergeReactionEvents(events, trackedEventIDs: trackedEventIDs, into: &nextStats))
    touched.formUnion(mergeReplyEvents(events, trackedEventIDs: trackedEventIDs, into: &nextStats))
    touched.formUnion(mergeRepostEvents(events, trackedEventIDs: trackedEventIDs, into: &nextStats))

    for eventID in touched {
        if let stats = nextStats[eventID] {
            statsByEventID[eventID] = stats
        }
        publishSnapshot(for: eventID)
    }

    return touched
}
```

Each merge helper should mutate `inout [String: NoteReactionStats]` instead of calling `setStats` directly.

- [ ] **Step 4: Run tests and build**

Run:

```bash
xcodebuild test \
  -project /Users/k/code/x21-ios/Flow.xcodeproj \
  -scheme Flow \
  -destination 'platform=iOS Simulator,name=iPhone 17' \
  -only-testing:FlowTests/NoteReactionBonusTests

xcodebuild build \
  -project /Users/k/code/x21-ios/Flow.xcodeproj \
  -scheme Flow \
  -destination 'platform=iOS Simulator,name=iPhone 17'
```

Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add Sources/Feed/NoteReactionStatsService.swift Tests/NoteReactionBonusTests.swift
git commit -m "perf: coalesce engagement snapshot publishes"
```

### Task 4: Stop Mutating Visible Feed Rows Across Multiple Hydration Passes

**Files:**
- Modify: `Sources/Home/HomeFeedViewModel.swift`
- Modify: `Sources/Profile/ProfileViewModel.swift`
- Modify: `Sources/Hashtag/HashtagFeedViewModel.swift`
- Modify: `Sources/Search/SearchViewModel.swift`
- Modify: `Sources/Feed/NostrFeedService.swift`
- Create: `Sources/Feed/FeedPresentationCache.swift`
- Test: `Tests/HomeFeedViewModelTests.swift`
- Test: `Tests/NostrFeedServiceTests.swift`

- [ ] **Step 1: Write the failing tests for single-commit hydration**

```swift
func testLoadRecentSnapshotDoesNotReorderVisibleRowsDuringHydration() async throws {
    let harness = try HomeFeedViewModelHarness()
    try await harness.seedRecentFeedSnapshot()

    await harness.viewModel.loadIfNeeded()

    let initialIDs = await harness.visibleItemIDs()
    try await harness.finishBackgroundHydration()
    let finalIDs = await harness.visibleItemIDs()

    XCTAssertEqual(initialIDs, finalIDs)
}

func testRefreshCommitsFullyHydratedTopBatchBeforePublishingItems() async throws {
    let harness = try HomeFeedViewModelHarness()
    await harness.viewModel.refresh()

    XCTAssertEqual(await harness.itemCommitCount(), 1)
}
```

- [ ] **Step 2: Run the focused tests**

Run:

```bash
xcodebuild test \
  -project /Users/k/code/x21-ios/Flow.xcodeproj \
  -scheme Flow \
  -destination 'platform=iOS Simulator,name=iPhone 17' \
  -only-testing:FlowTests/HomeFeedViewModelTests \
  -only-testing:FlowTests/NostrFeedServiceTests
```

Expected: FAIL because home feed currently commits fetched rows, then author-hydrated rows, then fully hydrated rows.

- [ ] **Step 3: Add a row-ready presentation cache and use single-commit hydration for visible batches**

```swift
// Sources/Feed/FeedPresentationCache.swift
actor FeedPresentationCache {
    static let shared = FeedPresentationCache()

    private var itemsByEventID: [String: FeedItem] = [:]

    func cachedItems(for eventIDs: [String]) -> [String: FeedItem] {
        Dictionary(uniqueKeysWithValues: eventIDs.compactMap { id in
            guard let item = itemsByEventID[id.lowercased()] else { return nil }
            return (id.lowercased(), item)
        })
    }

    func store(_ items: [FeedItem]) {
        for item in items {
            itemsByEventID[item.id] = item
        }
    }
}

// Sources/Home/HomeFeedViewModel.swift
// Replace "publish partially hydrated items, then merge in more detail later"
// with "fully hydrate the visible top batch before committing items".
let committedItems = await service.buildFeedItems(
    relayURLs: requestRelayURLs,
    events: timelineEvents,
    hydrationMode: .full,
    moderationSnapshot: muteFilterSnapshot
)
items = committedItems
await presentationCache.store(committedItems)
```

- [ ] **Step 4: Restrict background hydration to cache warming instead of visible-row mutation**

```swift
// Sources/Home/HomeFeedViewModel.swift
private func warmPresentationCache(
    for source: HomePrimaryFeedSource,
    relayTargets: [URL],
    events: [NostrEvent]
) {
    Task.detached(priority: .utility) { [service, presentationCache] in
        let hydrated = await service.buildFeedItems(
            relayURLs: relayTargets,
            events: events,
            hydrationMode: .full
        )
        await presentationCache.store(hydrated)
    }
}
```

Apply the same "single visible commit, background cache warming only" rule to profile, hashtag, and search feeds.

- [ ] **Step 5: Run the focused tests and build**

Run:

```bash
xcodebuild test \
  -project /Users/k/code/x21-ios/Flow.xcodeproj \
  -scheme Flow \
  -destination 'platform=iOS Simulator,name=iPhone 17' \
  -only-testing:FlowTests/HomeFeedViewModelTests \
  -only-testing:FlowTests/NostrFeedServiceTests

xcodebuild build \
  -project /Users/k/code/x21-ios/Flow.xcodeproj \
  -scheme Flow \
  -destination 'platform=iOS Simulator,name=iPhone 17'
```

Expected: PASS.

- [ ] **Step 6: Commit**

```bash
git add \
  Sources/Home/HomeFeedViewModel.swift \
  Sources/Profile/ProfileViewModel.swift \
  Sources/Hashtag/HashtagFeedViewModel.swift \
  Sources/Search/SearchViewModel.swift \
  Sources/Feed/NostrFeedService.swift \
  Sources/Feed/FeedPresentationCache.swift \
  Tests/HomeFeedViewModelTests.swift \
  Tests/NostrFeedServiceTests.swift
git commit -m "perf: stop visible feed rows from rehydrating in place"
```

### Task 5: Replace The Small Cache Mirror With A Durable Event Archive

**Files:**
- Create: `Sources/Feed/EventArchiveStore.swift`
- Modify: `Sources/Feed/SeenEventStore.swift`
- Modify: `Sources/Feed/FeedStorageProtocols.swift`
- Modify: `Sources/NostrDB/FlowNostrDB.swift`
- Test: `Tests/EventArchiveStoreTests.swift`
- Test: `Tests/FlowNostrDBTests.swift`

- [ ] **Step 1: Write the failing tests for durable archive behavior**

```swift
func testArchiveStoreRoundTripsEventsAndPrunesByByteBudget() async throws {
    let rootURL = try makeRootURL(prefix: "EventArchiveStore")
    let fileManager = FlowNostrDBTestFileManager(rootURL: rootURL)
    let store = EventArchiveStore(
        fileManager: fileManager,
        budget: .init(
            archiveSoftLimitBytes: 16_000,
            archiveHardLimitBytes: 20_000,
            hotIndexTargetEventCount: 100,
            minimumFreeDiskBytes: 0
        )
    )

    let events = (0..<50).map { index in
        makeEvent(
            id: String(format: "%064x", index),
            content: String(repeating: "x", count: 1024),
            createdAt: 1_700_000_000 + index
        )
    }

    await store.store(events: events)
    let diagnostics = await store.diagnosticsSnapshot()

    XCTAssertLessThanOrEqual(diagnostics.archiveBytes, 20_000)
    XCTAssertFalse((await store.events(ids: [events.first!.id])).isEmpty)
}
```

- [ ] **Step 2: Run the focused archive and Flow DB tests**

Run:

```bash
xcodebuild test \
  -project /Users/k/code/x21-ios/Flow.xcodeproj \
  -scheme Flow \
  -destination 'platform=iOS Simulator,name=iPhone 17' \
  -only-testing:FlowTests/EventArchiveStoreTests \
  -only-testing:FlowTests/FlowNostrDBTests
```

Expected: FAIL because `EventArchiveStore` does not exist yet.

- [ ] **Step 3: Implement the durable archive in Application Support**

```swift
// Sources/Feed/EventArchiveStore.swift
actor EventArchiveStore {
    struct Diagnostics: Sendable {
        let archiveCount: Int
        let archiveBytes: Int64
    }

    func store(events: [NostrEvent]) async
    func events(ids: [String]) async -> [String: NostrEvent]
    func recentEvents(limit: Int, pinnedIDs: Set<String>) async -> [NostrEvent]
    func diagnosticsSnapshot() async -> Diagnostics
}
```

Use a SQLite schema with:

```sql
CREATE TABLE archived_events (
    id TEXT PRIMARY KEY,
    pubkey TEXT NOT NULL,
    kind INTEGER NOT NULL,
    created_at INTEGER NOT NULL,
    seen_at REAL NOT NULL,
    payload_bytes INTEGER NOT NULL,
    pin_rank INTEGER NOT NULL DEFAULT 0,
    event_json BLOB NOT NULL
);

CREATE INDEX archived_events_seen_at_idx ON archived_events(seen_at DESC);
CREATE INDEX archived_events_created_at_idx ON archived_events(created_at DESC);
CREATE INDEX archived_events_pin_rank_idx ON archived_events(pin_rank DESC, seen_at DESC);
```

- [ ] **Step 4: Turn `SeenEventStore` into a facade over archive + hot index**

```swift
// Sources/Feed/SeenEventStore.swift
actor SeenEventStore: SeenEventStoring {
    private let archiveStore: EventArchiveStore
    private let nostrDatabase: FlowNostrDB

    func store(events: [NostrEvent]) {
        await archiveStore.store(events: events)
        let ingested = nostrDatabase.ingest(events: events)
        if !ingested || nostrDatabase.requiresRebuild() {
            let retained = await archiveStore.recentEvents(
                limit: hotIndexTargetEventCount,
                pinnedIDs: importantPinnedEventIDs()
            )
            _ = nostrDatabase.rebuild(retaining: retained)
        }
    }
}
```

- [ ] **Step 5: Run tests and build**

Run:

```bash
xcodebuild test \
  -project /Users/k/code/x21-ios/Flow.xcodeproj \
  -scheme Flow \
  -destination 'platform=iOS Simulator,name=iPhone 17' \
  -only-testing:FlowTests/EventArchiveStoreTests \
  -only-testing:FlowTests/FlowNostrDBTests \
  -only-testing:FlowTests/NostrFeedServiceTests

xcodebuild build \
  -project /Users/k/code/x21-ios/Flow.xcodeproj \
  -scheme Flow \
  -destination 'platform=iOS Simulator,name=iPhone 17'
```

Expected: PASS.

- [ ] **Step 6: Commit**

```bash
git add \
  Sources/Feed/EventArchiveStore.swift \
  Sources/Feed/SeenEventStore.swift \
  Sources/Feed/FeedStorageProtocols.swift \
  Sources/NostrDB/FlowNostrDB.swift \
  Tests/EventArchiveStoreTests.swift \
  Tests/FlowNostrDBTests.swift
git commit -m "feat: add durable local event archive"
```

### Task 6: Add Background Ingestion With Outbox Prioritization

**Files:**
- Create: `Sources/Feed/BackgroundIngestionCoordinator.swift`
- Modify: `Sources/Profile/ProfileEventService.swift`
- Modify: `Sources/Feed/FeedCaches.swift`
- Modify: `Sources/Feed/NostrFeedService.swift`
- Modify: `Sources/App/FlowApp.swift`
- Test: `Tests/BackgroundIngestionCoordinatorTests.swift`
- Test: `Tests/NostrFeedServiceTests.swift`

- [ ] **Step 1: Write the failing tests for outbox-first ingestion**

```swift
func testCoordinatorPrefersAuthorOutboxRelaysBeforeBroadFallback() async throws {
    let relayHints = ["author-pubkey": [URL(string: "wss://outbox.example.com")!]]
    let relayClient = RecordingRelayFetchClient()
    let coordinator = BackgroundIngestionCoordinator(
        relayClient: relayClient,
        archiveStore: InMemoryArchiveStore(),
        relayHintCache: StubRelayHintCache(hints: relayHints),
        broadFallbackRelayURLs: [URL(string: "wss://relay.damus.io")!]
    )

    await coordinator.enqueueFollowedAuthor(pubkey: "author-pubkey")
    await coordinator.runOnePass()

    let requestedRelays = await relayClient.requestedRelayURLs()
    XCTAssertEqual(requestedRelays.first?.absoluteString, "wss://outbox.example.com")
}
```

- [ ] **Step 2: Run the focused tests**

Run:

```bash
xcodebuild test \
  -project /Users/k/code/x21-ios/Flow.xcodeproj \
  -scheme Flow \
  -destination 'platform=iOS Simulator,name=iPhone 17' \
  -only-testing:FlowTests/BackgroundIngestionCoordinatorTests \
  -only-testing:FlowTests/NostrFeedServiceTests
```

Expected: FAIL because background ingestion coordinator does not exist yet.

- [ ] **Step 3: Implement the coordinator and relay-priority model**

```swift
// Sources/Feed/BackgroundIngestionCoordinator.swift
actor BackgroundIngestionCoordinator {
    func enqueueSelf(pubkey: String)
    func enqueueFollowedAuthor(pubkey: String)
    func enqueueViewedProfile(pubkey: String)
    func enqueueThreadRoot(eventID: String)
    func runOnePass() async
}

private func relayTargets(for pubkey: String) async -> [URL] {
    let outboxHints = await relayHintCache.prioritizedRelayURLs(
        baseRelayURLs: broadFallbackRelayURLs,
        for: [pubkey]
    )
    return Array(outboxHints.prefix(4)) + broadFallbackRelayURLs.prefix(2)
}
```

Use this fetch order:

1. author relay list / relay hints / inbox hints
2. currently successful user-configured read relays
3. broad fallback relays such as `relay.damus.io`, `relay.primal.net`, `relay.nostr.band`

- [ ] **Step 4: Start background ingestion from app lifecycle**

```swift
// Sources/App/FlowApp.swift
@StateObject private var backgroundIngestion = BackgroundIngestionCoordinator.shared

.task(id: auth.currentAccount?.pubkey) {
    backgroundIngestion.configure(
        currentPubkey: auth.currentAccount?.pubkey,
        followedPubkeys: FollowStore.shared.followedPubkeys,
        readRelayURLs: relaySettings.effectiveReadRelayURLs
    )
    await backgroundIngestion.startIfNeeded()
}
```

- [ ] **Step 5: Push background-fetched events through archive and hot index**

```swift
// Sources/Feed/NostrFeedService.swift
func ingestBackgroundEvents(_ events: [NostrEvent]) async {
    guard !events.isEmpty else { return }
    await seenEventStore.store(events: events)
}
```

- [ ] **Step 6: Run tests and build**

Run:

```bash
xcodebuild test \
  -project /Users/k/code/x21-ios/Flow.xcodeproj \
  -scheme Flow \
  -destination 'platform=iOS Simulator,name=iPhone 17' \
  -only-testing:FlowTests/BackgroundIngestionCoordinatorTests \
  -only-testing:FlowTests/NostrFeedServiceTests

xcodebuild build \
  -project /Users/k/code/x21-ios/Flow.xcodeproj \
  -scheme Flow \
  -destination 'platform=iOS Simulator,name=iPhone 17'
```

Expected: PASS.

- [ ] **Step 7: Commit**

```bash
git add \
  Sources/Feed/BackgroundIngestionCoordinator.swift \
  Sources/Profile/ProfileEventService.swift \
  Sources/Feed/FeedCaches.swift \
  Sources/Feed/NostrFeedService.swift \
  Sources/App/FlowApp.swift \
  Tests/BackgroundIngestionCoordinatorTests.swift \
  Tests/NostrFeedServiceTests.swift
git commit -m "feat: add outbox-first background ingestion"
```

### Task 7: Add Byte Budgets, Disk Guardrails, And A 1M-Event Rollout Path

**Files:**
- Create: `Sources/Feed/EventStorageBudget.swift`
- Modify: `Sources/Feed/EventArchiveStore.swift`
- Modify: `Sources/Feed/SeenEventStore.swift`
- Modify: `Sources/NostrDB/FlowNostrDB.swift`
- Modify: `Sources/Home/SettingsMediaView.swift`
- Test: `Tests/EventArchiveStoreTests.swift`
- Test: `Tests/FlowNostrDBTests.swift`

- [ ] **Step 1: Write the failing tests for budget behavior**

```swift
func testBudgetDisallowsMillionEventModeWhenFreeDiskBelowThreshold() {
    let budget = EventStorageBudget(
        archiveSoftLimitBytes: 1_500_000_000,
        archiveHardLimitBytes: 1_800_000_000,
        hotIndexTargetEventCount: 250_000,
        minimumFreeDiskBytes: 8_000_000_000
    )

    XCTAssertFalse(budget.canEnableLargeArchive(freeDiskBytes: 2_000_000_000))
    XCTAssertTrue(budget.canEnableLargeArchive(freeDiskBytes: 20_000_000_000))
}
```

- [ ] **Step 2: Run the focused tests**

Run:

```bash
xcodebuild test \
  -project /Users/k/code/x21-ios/Flow.xcodeproj \
  -scheme Flow \
  -destination 'platform=iOS Simulator,name=iPhone 17' \
  -only-testing:FlowTests/EventArchiveStoreTests \
  -only-testing:FlowTests/FlowNostrDBTests
```

Expected: FAIL because `EventStorageBudget` does not exist yet.

- [ ] **Step 3: Add explicit storage budgets**

```swift
// Sources/Feed/EventStorageBudget.swift
struct EventStorageBudget: Sendable, Equatable {
    let archiveSoftLimitBytes: Int64
    let archiveHardLimitBytes: Int64
    let hotIndexTargetEventCount: Int
    let minimumFreeDiskBytes: Int64

    static let milestoneA = EventStorageBudget(
        archiveSoftLimitBytes: 500 * 1024 * 1024,
        archiveHardLimitBytes: 650 * 1024 * 1024,
        hotIndexTargetEventCount: 120_000,
        minimumFreeDiskBytes: 3 * 1024 * 1024 * 1024
    )

    static let milestoneB = EventStorageBudget(
        archiveSoftLimitBytes: 1_000 * 1024 * 1024,
        archiveHardLimitBytes: 1_250 * 1024 * 1024,
        hotIndexTargetEventCount: 180_000,
        minimumFreeDiskBytes: 5 * 1024 * 1024 * 1024
    )

    static let milestoneC = EventStorageBudget(
        archiveSoftLimitBytes: 1_500 * 1024 * 1024,
        archiveHardLimitBytes: 1_800 * 1024 * 1024,
        hotIndexTargetEventCount: 250_000,
        minimumFreeDiskBytes: 8 * 1024 * 1024 * 1024
    )
}
```

- [ ] **Step 4: Surface the budget and health in diagnostics**

```swift
// Sources/Home/SettingsMediaView.swift
DiagnosticsKeyValueRow(title: "Archive Events", value: "\(diagnostics.archiveCount)")
DiagnosticsKeyValueRow(title: "Archive Bytes", value: ByteCountFormatter.string(fromByteCount: diagnostics.archiveBytes, countStyle: .binary))
DiagnosticsKeyValueRow(title: "Hot Index Events", value: "\(diagnostics.hotIndexEventCount)")
DiagnosticsKeyValueRow(title: "Background Ingestion", value: diagnostics.backgroundIngestionStatus)
```

- [ ] **Step 5: Run tests and build**

Run:

```bash
xcodebuild test \
  -project /Users/k/code/x21-ios/Flow.xcodeproj \
  -scheme Flow \
  -destination 'platform=iOS Simulator,name=iPhone 17' \
  -only-testing:FlowTests/EventArchiveStoreTests \
  -only-testing:FlowTests/FlowNostrDBTests

xcodebuild build \
  -project /Users/k/code/x21-ios/Flow.xcodeproj \
  -scheme Flow \
  -destination 'platform=iOS Simulator,name=iPhone 17'
```

Expected: PASS.

- [ ] **Step 6: Commit**

```bash
git add \
  Sources/Feed/EventStorageBudget.swift \
  Sources/Feed/EventArchiveStore.swift \
  Sources/Feed/SeenEventStore.swift \
  Sources/NostrDB/FlowNostrDB.swift \
  Sources/Home/SettingsMediaView.swift \
  Tests/EventArchiveStoreTests.swift \
  Tests/FlowNostrDBTests.swift
git commit -m "feat: add event storage budgets and diagnostics"
```

### Task 8: Verify In Release-Like Conditions And Roll Out Gradually

**Files:**
- Modify: `docs/feed-smoothness-roadmap.md`
- Create: `docs/feed-ingestion-rollout.md`

- [ ] **Step 1: Update the roadmap docs with the new rollout gates**

```markdown
## Rollout Gates

1. Row-scoped engagement shipping gate
   - No feed screen observes `NoteReactionStatsService` with `@ObservedObject`
   - Engagement prefetch is batched
2. Hydration shipping gate
   - Visible rows are not mutated in place after first commit
3. Storage gate
   - Archive survives relaunch
   - Hot index rebuilds from archive seed
4. Large corpus gate
   - Milestone B passes before Milestone C is enabled
```

- [ ] **Step 2: Run the full targeted test slices**

Run:

```bash
xcodebuild test \
  -project /Users/k/code/x21-ios/Flow.xcodeproj \
  -scheme Flow \
  -destination 'platform=iOS Simulator,name=iPhone 17' \
  -only-testing:FlowTests/NoteReactionBonusTests \
  -only-testing:FlowTests/FeedEngagementViewportCoordinatorTests \
  -only-testing:FlowTests/HomeFeedViewModelTests \
  -only-testing:FlowTests/NostrFeedServiceTests \
  -only-testing:FlowTests/FlowNostrDBTests \
  -only-testing:FlowTests/EventArchiveStoreTests \
  -only-testing:FlowTests/BackgroundIngestionCoordinatorTests
```

Expected: PASS.

- [ ] **Step 3: Run simulator verification on the critical flows**

Run:

```bash
xcodebuild build \
  -project /Users/k/code/x21-ios/Flow.xcodeproj \
  -scheme Flow \
  -destination 'platform=iOS Simulator,name=iPhone 17'
```

Manual verification checklist:

- Home Following feed scrolls without visible row height changes
- Profile notes do not repaint into new layout blocks during scroll
- Search results keep smooth scroll while reaction counts refresh
- Reactions update after first paint without moving rows
- Archive diagnostics show growth while browsing and after relaunch

- [ ] **Step 4: Roll out budgets in three stages**

```text
Stage 1:
- ship Milestone A budgets
- collect archive bytes, hot index bytes, rebuild time, and crash-free sessions

Stage 2:
- if metrics are healthy for one release cycle, ship Milestone B

Stage 3:
- enable Milestone C only when:
  - rebuild time is acceptable
  - archive prune time is acceptable
  - free-disk guardrail is met
```

- [ ] **Step 5: Commit**

```bash
git add \
  docs/feed-smoothness-roadmap.md \
  docs/feed-ingestion-rollout.md
git commit -m "docs: add feed smoothness and ingestion rollout gates"
```

---

## Self-Review

### Spec coverage

- Feed jitter from repeated row repainting: covered in tasks 1-4
- Reaction-count freshness without broad invalidation: covered in tasks 1-3
- Flow DB / local ingestion weakness: covered in tasks 5-7
- Outbox-based ingestion: covered in task 6
- Large local corpus / one million events question: covered in storage decision and task 7

### Placeholder scan

- No `TBD`, `TODO`, or "implement later" markers remain.
- Each task has concrete files, code, commands, and expected outcomes.

### Type consistency

- Reaction snapshot API is consistently called `currentSnapshot(for:)`.
- Durable archive type is consistently called `EventArchiveStore`.
- Storage budget type is consistently called `EventStorageBudget`.
- Background worker type is consistently called `BackgroundIngestionCoordinator`.

## Execution Handoff

Plan complete and saved to `docs/superpowers/plans/2026-04-26-feed-smoothness-and-event-ingestion.md`. Two execution options:

**1. Subagent-Driven (recommended)** - I dispatch a fresh subagent per task, review between tasks, fast iteration

**2. Inline Execution** - Execute tasks in this session using executing-plans, batch execution with checkpoints

Which approach?
