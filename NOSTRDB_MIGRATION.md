# NostrDB Migration Checklist

This file is the working checklist for evaluating and integrating `nostrdb` into Flow without losing our place mid-migration.

## Goal

Move Flow toward a single local-first event store that can:

- ingest relay events once
- resolve profiles, follow lists, repost targets, and reply targets locally
- reduce duplicate caching layers and relay round-trips
- improve warm-feed performance, battery usage, and scroll-time CPU

## Non-Goals For Phase 1

- no full timeline rewrite yet
- no replacement of `NostrRelayClient`
- no user-visible behavior changes
- no removal of the current SQLite/file-backed caches until shadow validation is complete

## Rollback Point

- Git tag: `THE-BIG-ONE`
- Commit: `d52f067`

If this effort gets messy, we reset our mental model to `THE-BIG-ONE` and restart from there.

## Current Architecture Snapshot

- network fetch + feed stitching: [NostrFeedService.swift](/Users/k/code/x21-ios/Sources/Feed/NostrFeedService.swift)
- in-memory timeline cache: [FeedCaches.swift](/Users/k/code/x21-ios/Sources/Feed/FeedCaches.swift)
- persisted seen-event SQLite store: [SeenEventStore.swift](/Users/k/code/x21-ios/Sources/Feed/SeenEventStore.swift)
- persisted profile/follow cache files: [FeedCaches.swift](/Users/k/code/x21-ios/Sources/Feed/FeedCaches.swift)

## Phase Checklist

### Phase 0: Preparation

- [x] Create a remote restore checkpoint named `THE-BIG-ONE`
- [x] Write down the migration plan in the repo
- [ ] Confirm `nostrdb` licensing/distribution approach we are comfortable shipping
- [ ] Decide wrapper strategy: vendor Damus wrapper, build our own Swift wrapper, or bridge through C

### Phase 1: Storage Abstraction

- [x] Add protocol seams for event, profile, relay-hint, and follow-list storage
- [x] Make current SQLite/file-backed stores conform
- [x] Switch `NostrFeedService` to depend on abstractions instead of concrete stores
- [x] Build and verify no behavior change

### Phase 2: Direct Ingest Rollout

- [x] Vendor and build `nostrdb` directly in the app target
- [x] Mirror fetched events into `nostrdb` while keeping current stores live
- [ ] Add diagnostics counters for ingest success/failure
- [ ] Add a feature flag for enabling local reads from `nostrdb`

### Phase 3: High-Value Read Path Migration

- [x] Migrate event-by-id lookup for repost targets
- [x] Migrate reply-target resolution
- [x] Migrate latest profile lookup by pubkey
- [x] Migrate latest follow-list lookup by pubkey
- [x] Compare old/new results on the same inputs with targeted regression tests

### Phase 4: Timeline Query Migration

- [x] Migrate warm feed hydration to local queries first
- [x] Migrate following/home pagination reads
- [x] Migrate profile timeline reads
- [x] Migrate hashtag/search reads
- [ ] Measure before/after CPU, memory, and relay request volume

### Phase 5: Cleanup

- [ ] Remove redundant cache layers that `nostrdb` replaces
- [ ] Revisit cache TTLs and duplication
- [ ] Keep only the fallback stores we still truly need

## Immediate Next Slice

1. Measure real device/simulator CPU, memory, and relay volume before removing more legacy layers.
2. Keep the legacy stores as fallbacks while we verify the local-first timeline behavior.
3. Remove redundant cache layers only after the local-first feeds feel stable.
4. Revisit special cases like trending and any relay-scoped feeds we still want to keep remote-first.

## Progress Notes

- 2026-03-30: Created `THE-BIG-ONE` checkpoint and pushed it to GitHub.
- 2026-03-30: Starting Phase 1 with storage abstraction only.
- 2026-03-30: Added storage protocols in `Sources/Feed/FeedStorageProtocols.swift`.
- 2026-03-30: Switched `NostrFeedService` to protocol-backed storage dependencies.
- 2026-03-30: Verified abstraction pass with a successful `xcodebuild` app build.
- 2026-03-30: Vendored `nostrdb`, added a C shim + Swift wrapper, and compiled it directly into Flow.
- 2026-03-30: Switched seen-event ingest and event-by-id reads to prefer `nostrdb`, with SQLite fallback still intact.
- 2026-03-30: Switched profile and follow-list cache reads to prefer `nostrdb` local data before the legacy persisted caches.
- 2026-03-30: Added regression tests for event lookup, profile lookup, and follow-list lookup against the new local store.
- 2026-03-30: Added generic `nostrdb` filter queries through the Flow C shim and Swift wrapper.
- 2026-03-30: Switched shared timeline reads in `NostrFeedService` to local-first `nostrdb` queries with relay refill/fallback behavior.
- 2026-03-30: Verified local-first author timeline pagination and top-of-feed fallback with targeted `NostrFeedServiceTests`.
