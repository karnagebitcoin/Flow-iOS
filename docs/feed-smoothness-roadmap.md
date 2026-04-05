# Feed Smoothness Roadmap

## Goal

Make Halo's feed feel much closer to Primal's:

- no visible "loading in" while scrolling
- no layout shift when cards, replies, or metadata arrive
- faster first paint for feed rows
- keep freshness high and avoid stale-cache bugs

This plan assumes we keep Nostr correctness and live behavior intact. We are not replacing relays or Flow DB. We are reducing how much work happens after a row is already on screen.

## Working Thesis

The current gap is not mainly that Halo lacks a cache.

The current gap is that Halo often has the raw event at paint time, but not all of the derived presentation state required for a fully finished row:

- author profile state
- repost / quote display context
- reply target context
- reaction aggregates
- media sizing and thumbnails
- link preview metadata
- mention / custom emoji resolution

Primal likely feels smoother because more of this work is already done before the client paints the row.

## What We Have Today

### Existing strengths

- Flow DB already stores a large local event corpus.
- Many timeline queries are already local-first.
- Recent feed snapshots exist.
- Image caching, link preview caching, and profile caching already exist in pieces.

### Current bottlenecks

- feed items are hydrated in multiple passes
- visible rows still trigger async enrichment
- some shared services invalidate broad parts of the feed
- website cards and other rich content do not reserve their final layout
- feed rows can visibly upgrade after first render

## Strategy

Use a staged approach:

1. Improve the current local-first architecture first.
2. Add a denormalized local presentation cache for feed-ready rows.
3. Only after that, decide whether a self-hosted indexing service is still needed.

This avoids jumping straight into a backend system before we know how far local improvements can take us.

## Phase 1: Low-Risk Local Improvements

### Objective

Reduce scroll-time work without changing the architecture.

### Work

- move more synchronous row work off the render path
- reduce broad feed invalidation from shared observable services
- precompute reply counts, reaction display state, and other aggregates earlier
- reserve stable layout for website cards and other async cards
- add skeleton states only where final layout is already known

### Specific targets

- website link cards
- quoted note cards
- reaction count updates
- reply count calculation
- media layout sizing

### Expected outcome

- fewer tiny hitches during scroll
- less visible layout shift
- better perceived polish

### Risk

Low to medium.

Main risk is regressions in feed rendering logic, but freshness model stays the same.

## Phase 2: Local Feed-Ready Presentation Cache

### Objective

Make Flow DB plus local caches behave more like a lightweight on-device indexer.

### Key idea

Do not only store raw Nostr events.

Also store a bounded, rebuildable cache of derived presentation state for recent feed rows.

### What to cache

- author display snapshot
- repost / display event snapshot
- reply target summary
- reaction aggregate snapshot
- media metadata
  - width
  - height
  - aspect ratio
  - preview readiness
- website preview snapshot
  - title
  - summary
  - host
  - preview image state
- resolved mention labels if available

### What not to do

- do not treat this as permanent truth
- do not make it the only source of live state
- do not try to cache the entire network forever

### Shape of the cache

Use a bounded derived cache:

- LRU or recency-based eviction
- scoped to recent feeds and recently viewed content
- rebuildable from raw events when necessary

### Expected outcome

- more rows ready at first paint
- less row upgrading during scroll
- more consistent feed feel even without a backend indexer

### Risk

Medium.

The main challenge is invalidation and keeping snapshots fresh enough.

## Phase 3: Hybrid Freshness Overlay

### Objective

Prevent stale-cache bugs while still painting instantly.

### Model

Treat the cached feed-ready row as the fast base state.

Then apply live updates from relays on top:

- new notes
- new replies
- new reactions
- latest profiles

### Rules

- initial paint should prefer local feed-ready cache
- live subscriptions should patch freshness after first paint
- recent writes by the current user should always win locally
- stale snapshots should degrade gracefully, not break navigation or content

### Expected outcome

- fast paint without sacrificing freshness

### Risk

Medium.

This is mostly correctness and invalidation work.

## Phase 4: Decide on a Self-Hosted Indexed Feed Service

### Objective

Only introduce backend indexing if local improvements still fall short.

### When it is worth it

- if we still see visible row upgrades after local presentation caching
- if we want Primal-like feed-ready responses across devices
- if we want deeper discovery feeds without heavy client joins

### What the backend should do

Only accelerate feed assembly:

- precompute feed pages
- pre-join author and reply context
- precompute reaction aggregates
- precompute preview metadata where possible

### What the backend should not replace

- normal relay writes
- live subscriptions
- local write-after-read correctness
- the on-device event store

### Best architecture

Server index = fast base feed assembly

Client local state + relays = freshness overlay

### Risk

Medium to high.

Operational complexity rises sharply:

- backend uptime
- schema versioning
- cache invalidation
- multi-device consistency
- privacy / telemetry concerns

## Recommendation

Recommended order:

1. Phase 1: local render-path cleanup
2. Phase 2: local feed-ready presentation cache
3. Phase 3: hybrid freshness overlay
4. Re-evaluate
5. Only then consider Phase 4 backend indexing

This is the safest path to get much closer to Primal without overcommitting to backend complexity too early.

## Why Not Jump Straight to a Primal-Style Backend

Because the backend is not the only reason Primal feels smooth.

We still have clear client-side opportunities:

- fewer post-render upgrades
- more stable layouts
- narrower feed invalidation
- richer local presentation caching

If we skip these and jump to a backend too early, we risk:

- still having jank from the client
- adding staleness and ops complexity on top
- making debugging much harder

## Freshness Guardrails

To avoid "cache always breaks something," keep these rules:

- raw Nostr events remain the canonical source of truth
- derived feed-ready caches are always disposable
- local recent writes always override stale cached server or local snapshots
- live relay data patches cached rows after paint
- cache entries should include revision / timestamp metadata
- cache failures should fall back to raw rendering, not blank states

## Success Metrics

Measure before and after:

- dropped frames during sustained feed scroll
- time to first visible feed row
- time to fully stable row after paint
- count of row re-renders while scrolling
- number of async post-render content upgrades per 20 visible rows
- perceived layout shift for website cards and quoted notes

## Definition of Done

We are "close to Primal" when:

- feed rows appear fully shaped before they enter view
- website cards do not pop in or resize noticeably
- quoted notes rarely late-load in the main timeline
- reaction and reply counts feel already present, not catching up
- scrolling feels continuous even on media-rich feeds

## Immediate Next Step

Start with a scoped audit and implementation pass focused on:

- website card skeleton + reserved layout
- quote/reply context stabilization
- reaction and reply aggregate precomputation
- reducing broad feed invalidation during scroll

This is the highest-leverage, lowest-risk starting point.
