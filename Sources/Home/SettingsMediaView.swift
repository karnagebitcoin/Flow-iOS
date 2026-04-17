import SwiftUI

struct SettingsMediaView: View {
    @EnvironmentObject private var appSettings: AppSettingsStore
    @State private var mediaCacheSizeDescription = "Calculating..."
    @State private var isClearingMediaCache = false
    @State private var isShowingClearMediaCacheConfirmation = false

    var body: some View {
        ThemedSettingsForm {
            Section {
                SettingsToggleRow(
                    title: "Blur Media From People I Don't Follow",
                    isOn: Binding(
                        get: { appSettings.blurMediaFromUnfollowedAuthors },
                        set: { appSettings.blurMediaFromUnfollowedAuthors = $0 }
                    ),
                    footer: "Images and videos from accounts you don't follow stay blurred until you tap to reveal them."
                )
            } header: {
                Text("Media")
            } footer: {
                Text("This only applies while you're signed in and does not blur your own posts.")
            }

            Section {
                SettingsToggleRow(
                    title: "Media Efficiency",
                    isOn: Binding(
                        get: { appSettings.mediaEfficiencyEnabled },
                        set: { appSettings.mediaEfficiencyEnabled = $0 }
                    ),
                    footer: "Use less data and battery."
                )

                SettingsToggleRow(
                    title: "File Size Limits",
                    isOn: Binding(
                        get: { appSettings.mediaFileSizeLimitsEnabled },
                        set: { appSettings.mediaFileSizeLimitsEnabled = $0 }
                    ),
                    footer: "Ask before loading very large images."
                )
                .disabled(!appSettings.mediaEfficiencyEnabled)
                .opacity(appSettings.mediaEfficiencyEnabled ? 1 : 0.55)

                SettingsToggleRow(
                    title: "Pause Large GIFs",
                    isOn: Binding(
                        get: { appSettings.largeGIFAutoplayLimitEnabled },
                        set: { appSettings.largeGIFAutoplayLimitEnabled = $0 }
                    ),
                    footer: "Show large GIFs as still previews."
                )
                .disabled(!appSettings.mediaEfficiencyEnabled)
                .opacity(appSettings.mediaEfficiencyEnabled ? 1 : 0.55)
            } header: {
                Text("Media Efficiency")
            } footer: {
                Text("You can turn these off anytime.")
            }

            Section {
                LabeledContent("Stored Media") {
                    if isClearingMediaCache {
                        ProgressView()
                    } else {
                        Text(mediaCacheSizeDescription)
                            .foregroundStyle(.secondary)
                    }
                }

                NavigationLink {
                    SettingsMediaDiagnosticsView()
                } label: {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Diagnostics")
                            .foregroundStyle(.primary)

                        Text("Cache hit rate, source breakdown, and payload totals.")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .padding(.vertical, 2)
                }

                Button(role: .destructive) {
                    isShowingClearMediaCacheConfirmation = true
                } label: {
                    Text(isClearingMediaCache ? "Clearing..." : "Clear Media Cache")
                }
                .disabled(isClearingMediaCache)
            } header: {
                Text("Cache")
            } footer: {
                Text("Avatars and note images stay on disk so repeat visits and scrolling feel faster. Clearing this only removes cached media bytes, not your account or notes.")
            }
        }
        .navigationTitle("Media")
        .navigationBarTitleDisplayMode(.inline)
        .alert("Clear Media Cache?", isPresented: $isShowingClearMediaCacheConfirmation) {
            Button("Cancel", role: .cancel) {}
            Button("Clear", role: .destructive) {
                clearMediaCache()
            }
        } message: {
            Text("This will remove cached avatars and note images from this device. Your account and notes will not be affected.")
        }
        .task {
            await refreshMediaCacheSize()
        }
    }

    private func refreshMediaCacheSize() async {
        let bytes = await FlowImageCache.shared.totalCacheSizeBytes()
        let description = bytes > 0
            ? ByteCountFormatter.string(fromByteCount: bytes, countStyle: .file)
            : "Empty"
        await MainActor.run {
            mediaCacheSizeDescription = description
        }
    }

    private func clearMediaCache() {
        guard !isClearingMediaCache else { return }
        isClearingMediaCache = true

        Task {
            await FlowImageCache.shared.clearAllCachedImages()
            await FlowImageCache.shared.resetDiagnostics()
            await refreshMediaCacheSize()
            await MainActor.run {
                isClearingMediaCache = false
            }
        }
    }
}

private struct SettingsMediaDiagnosticsView: View {
    @State private var diagnostics = FlowMediaCacheDiagnostics()
    @State private var flowDBDiagnostics = FlowNostrDBDiagnostics()

    var body: some View {
        ThemedSettingsForm {
            Section {
                diagnosticMetricRow(
                    title: "Cache Hit Rate",
                    value: cacheHitRateDescription
                )
                diagnosticMetricRow(
                    title: "Tracked Requests",
                    value: diagnostics.trackedRequestCount.formatted()
                )
                diagnosticMetricRow(
                    title: "Cache Hits",
                    value: diagnostics.cacheHitCount.formatted()
                )
                diagnosticMetricRow(
                    title: "Network-backed Misses",
                    value: diagnostics.cacheMissCount.formatted()
                )
            } header: {
                Text("Overview")
            } footer: {
                Text("Counts the current app session for on-demand requests that go through the shared Halo media cache. Background prefetch warmups are excluded.")
            }

            Section {
                diagnosticMetricRow(
                    title: "Image Memory Hits",
                    value: diagnostics.imageMemoryHitCount.formatted()
                )
                diagnosticMetricRow(
                    title: "Data Memory Hits",
                    value: diagnostics.dataMemoryHitCount.formatted()
                )
                diagnosticMetricRow(
                    title: "Disk Hits",
                    value: diagnostics.diskHitCount.formatted()
                )
                diagnosticMetricRow(
                    title: "URL Cache Hits",
                    value: diagnostics.urlCacheHitCount.formatted()
                )
                diagnosticMetricRow(
                    title: "Network Fetches",
                    value: diagnostics.networkFetchCount.formatted()
                )
                diagnosticMetricRow(
                    title: "Network Failures",
                    value: diagnostics.networkFailureCount.formatted()
                )
            } header: {
                Text("Request Sources")
            } footer: {
                Text("This covers the shared Halo media cache path. Some screens still use system image loading, and video playback has its own pipeline.")
            }

            Section {
                diagnosticMetricRow(
                    title: "Cached Payload",
                    value: byteDescription(diagnostics.cacheServedByteCount)
                )
                diagnosticMetricRow(
                    title: "Network Payload",
                    value: byteDescription(diagnostics.networkServedByteCount)
                )
            } header: {
                Text("Payload")
            } footer: {
                Text("Payload totals use the encoded media bytes known to the shared cache.")
            }

            Section {
                diagnosticMetricRow(
                    title: "DB Open",
                    value: flowDBDiagnostics.isOpen ? "Yes" : "No"
                )
                diagnosticMetricRow(
                    title: "DB Directory",
                    value: flowDBDiagnostics.databaseDirectoryExists ? "Present" : "Missing"
                )
                diagnosticMetricRow(
                    title: "Open Mapsize",
                    value: byteDescription(flowDBDiagnostics.openMapsizeBytes)
                )
                diagnosticMetricRow(
                    title: "Last Attempted Mapsize",
                    value: byteDescription(flowDBDiagnostics.lastAttemptedMapsizeBytes)
                )
                diagnosticMetricRow(
                    title: "Ingest Calls",
                    value: flowDBDiagnostics.ingestCallCount.formatted()
                )
                diagnosticMetricRow(
                    title: "Successful Ingests",
                    value: flowDBDiagnostics.successfulIngestCallCount.formatted()
                )
                diagnosticMetricRow(
                    title: "Persisted Events",
                    value: flowDBDiagnostics.persistedEventCount.formatted()
                )
                diagnosticMetricRow(
                    title: "Persisted Profiles",
                    value: flowDBDiagnostics.persistedProfileCount.formatted()
                )
                diagnosticMetricRow(
                    title: "Session Ingested Events",
                    value: flowDBDiagnostics.sessionIngestedEventCount.formatted()
                )
                diagnosticMetricRow(
                    title: "Session Ingested Profiles",
                    value: flowDBDiagnostics.sessionIngestedProfileCount.formatted()
                )
                diagnosticMetricRow(
                    title: "Local Event Lookups",
                    value: flowDBDiagnostics.eventLookupCount.formatted()
                )
                diagnosticMetricRow(
                    title: "Local Profile Lookups",
                    value: flowDBDiagnostics.profileLookupCount.formatted()
                )
                diagnosticMetricRow(
                    title: "Local Follow List Reads",
                    value: flowDBDiagnostics.followListLookupCount.formatted()
                )
                diagnosticMetricRow(
                    title: "Local Timeline Queries",
                    value: flowDBDiagnostics.queryCount.formatted()
                )
                diagnosticMetricRow(
                    title: "Recent Event Overlay",
                    value: flowDBDiagnostics.recentOverlayEventCount.formatted()
                )
                diagnosticMetricRow(
                    title: "Replaceable Overlay",
                    value: flowDBDiagnostics.recentReplaceableOverlayCount.formatted()
                )
                diagnosticMetricRow(
                    title: "On-Device Size",
                    value: byteDescription(flowDBDiagnostics.diskUsageBytes)
                )
            } header: {
                Text("Halo DB")
            } footer: {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Persisted values reflect what is already committed into the local nostrdb store. Session ingested values reflect what the current app run has pushed through the ingester, even if writer threads have not finished compacting everything yet.")
                    Text("Path: \(flowDBDiagnostics.databasePath)")
                    if let error = flowDBDiagnostics.lastOpenError, !error.isEmpty {
                        Text("Last open error: \(error)")
                    }
                }
            }

            Section {
                Button("Reset Session Diagnostics", role: .destructive) {
                    resetDiagnostics()
                }
            } footer: {
                Text("Reset before a fresh troubleshooting pass if you want a clean session baseline.")
            }
        }
        .navigationTitle("Diagnostics")
        .navigationBarTitleDisplayMode(.inline)
        .task {
            await refreshDiagnostics()
        }
        .refreshable {
            await refreshDiagnostics()
        }
    }

    private var cacheHitRateDescription: String {
        guard diagnostics.trackedRequestCount > 0 else { return "No data yet" }
        return diagnostics.cacheHitRate.formatted(
            .percent.precision(.fractionLength(1))
        )
    }

    @ViewBuilder
    private func diagnosticMetricRow(title: String, value: String) -> some View {
        LabeledContent(title) {
            Text(value)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.trailing)
        }
    }

    private func byteDescription(_ byteCount: Int64) -> String {
        guard byteCount > 0 else { return "0 bytes" }
        return ByteCountFormatter.string(fromByteCount: byteCount, countStyle: .file)
    }

    private func refreshDiagnostics() async {
        let snapshot = await FlowImageCache.shared.diagnosticsSnapshot()
        let flowDBSnapshot = FlowNostrDB.shared.diagnosticsSnapshot()
        await MainActor.run {
            diagnostics = snapshot
            flowDBDiagnostics = flowDBSnapshot
        }
    }

    private func resetDiagnostics() {
        Task {
            await FlowImageCache.shared.resetDiagnostics()
            FlowNostrDB.shared.resetSessionDiagnostics()
            await refreshDiagnostics()
        }
    }
}
