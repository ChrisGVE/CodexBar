import CodexBarCore
import Foundation
import Testing
@testable import CodexBar

@MainActor
struct UsageStoreBurnRateRecordingTests {
    private func makeStore() -> UsageStore {
        let settings = SettingsStore(
            configStore: testConfigStore(suiteName: "UsageStoreBurnRateRecordingTests-\(UUID().uuidString)"),
            zaiTokenStore: NoopZaiTokenStore(),
            syntheticTokenStore: NoopSyntheticTokenStore())
        let tempBaseURL = FileManager.default.temporaryDirectory.appendingPathComponent(
            "UsageStoreBurnRateRecordingTests-\(UUID().uuidString)", isDirectory: true)
        let buffer = BurnRateBufferStore(baseURL: tempBaseURL)
        return UsageStore(
            fetcher: UsageFetcher(),
            browserDetection: BrowserDetection(cacheTTL: 0),
            settings: settings,
            burnRateBufferStore: buffer)
    }

    @Test
    func `record burn rate sample appends for known identity`() async {
        let store = self.makeStore()
        let buffer = store.burnRateBufferStore
        let uniqueAccount = "alice-\(UUID().uuidString)@example.com"
        let key = BurnRateBufferKey(provider: .codex, accountID: uniqueAccount)
        await buffer.remove(key: key)

        let now = Date(timeIntervalSince1970: 1_000_000)
        let identity = ProviderIdentitySnapshot(
            providerID: .codex,
            accountEmail: uniqueAccount,
            accountOrganization: nil,
            loginMethod: nil)
        let snapshot = UsageSnapshot(
            primary: RateWindow(
                usedPercent: 25,
                windowMinutes: 300,
                resetsAt: now.addingTimeInterval(225 * 60),
                resetDescription: nil),
            secondary: RateWindow(
                usedPercent: 10,
                windowMinutes: 10080,
                resetsAt: now.addingTimeInterval(6 * 24 * 3600),
                resetDescription: nil),
            updatedAt: now,
            identity: identity)

        await store.recordBurnRateSample(provider: .codex, snapshot: snapshot)

        let samples = await buffer.samples(for: key)
        #expect(samples.count == 1)
        let primaryPct = samples.first?.primaryUsedPercent ?? -1
        #expect(primaryPct == 25)
        let secondaryPct = samples.first?.secondaryUsedPercent ?? -1
        #expect(secondaryPct == 10)
    }

    @Test
    func `record burn rate sample uses empty account ID when identity missing`() async {
        let store = self.makeStore()
        let buffer = store.burnRateBufferStore
        let key = BurnRateBufferKey(provider: .zai, accountID: "")
        await buffer.remove(key: key)

        let now = Date(timeIntervalSince1970: 1_000_000)
        let snapshot = UsageSnapshot(
            primary: RateWindow(
                usedPercent: 5,
                windowMinutes: 300,
                resetsAt: now.addingTimeInterval(285 * 60),
                resetDescription: nil),
            secondary: nil,
            tertiary: nil,
            updatedAt: now)

        await store.recordBurnRateSample(provider: .zai, snapshot: snapshot)

        let samples = await buffer.samples(for: key)
        #expect(samples.count == 1)
    }
}
