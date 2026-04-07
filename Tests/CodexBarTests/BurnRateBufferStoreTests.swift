import CodexBarCore
import Foundation
import Testing

struct BurnRateBufferStoreTests {
    private func tempBaseURL() -> URL {
        FileManager.default.temporaryDirectory.appendingPathComponent(
            "BurnRateBufferStoreTests-\(UUID().uuidString)", isDirectory: true)
    }

    @Test
    func `append and retrieve returns samples in order`() async {
        let store = BurnRateBufferStore(baseURL: self.tempBaseURL())
        let key = BurnRateBufferKey(provider: .codex, accountID: "alice")
        let now = Date(timeIntervalSince1970: 1_000_000)

        await store.append(
            BurnRateSample(
                sampledAt: now,
                primaryUsedPercent: 10,
                secondaryUsedPercent: nil),
            for: key,
            now: now)
        await store.append(
            BurnRateSample(
                sampledAt: now.addingTimeInterval(60),
                primaryUsedPercent: 20,
                secondaryUsedPercent: nil),
            for: key,
            now: now.addingTimeInterval(60))

        let samples = await store.samples(for: key)
        #expect(samples.count == 2)
        #expect(samples.first?.primaryUsedPercent == 10)
        #expect(samples.last?.primaryUsedPercent == 20)
    }

    @Test
    func `append prunes samples older than lookback window`() async {
        let store = BurnRateBufferStore(
            lookbackWindow: 3600,
            baseURL: self.tempBaseURL())
        let key = BurnRateBufferKey(provider: .codex, accountID: "alice")
        let now = Date(timeIntervalSince1970: 1_000_000)

        // Old sample (2h ago) should be evicted by the next append.
        await store.append(
            BurnRateSample(
                sampledAt: now.addingTimeInterval(-2 * 3600),
                primaryUsedPercent: 5,
                secondaryUsedPercent: nil),
            for: key,
            now: now.addingTimeInterval(-2 * 3600))
        await store.append(
            BurnRateSample(
                sampledAt: now,
                primaryUsedPercent: 50,
                secondaryUsedPercent: nil),
            for: key,
            now: now)

        let samples = await store.samples(for: key)
        #expect(samples.count == 1)
        #expect(samples.first?.primaryUsedPercent == 50)
    }

    @Test
    func `keys are isolated across providers and accounts`() async {
        let store = BurnRateBufferStore(baseURL: self.tempBaseURL())
        let codexAlice = BurnRateBufferKey(provider: .codex, accountID: "alice")
        let codexBob = BurnRateBufferKey(provider: .codex, accountID: "bob")
        let claudeAlice = BurnRateBufferKey(provider: .claude, accountID: "alice")
        let now = Date(timeIntervalSince1970: 1_000_000)

        await store.append(
            BurnRateSample(sampledAt: now, primaryUsedPercent: 1, secondaryUsedPercent: nil),
            for: codexAlice,
            now: now)
        await store.append(
            BurnRateSample(sampledAt: now, primaryUsedPercent: 2, secondaryUsedPercent: nil),
            for: codexBob,
            now: now)
        await store.append(
            BurnRateSample(sampledAt: now, primaryUsedPercent: 3, secondaryUsedPercent: nil),
            for: claudeAlice,
            now: now)

        #expect(await store.samples(for: codexAlice).first?.primaryUsedPercent == 1)
        #expect(await store.samples(for: codexBob).first?.primaryUsedPercent == 2)
        #expect(await store.samples(for: claudeAlice).first?.primaryUsedPercent == 3)
        #expect(await store.keys().count == 3)
    }

    @Test
    func `remove drops key but leaves others`() async {
        let store = BurnRateBufferStore(baseURL: self.tempBaseURL())
        let codex = BurnRateBufferKey(provider: .codex, accountID: "alice")
        let claude = BurnRateBufferKey(provider: .claude, accountID: "alice")
        let now = Date(timeIntervalSince1970: 1_000_000)

        await store.append(
            BurnRateSample(sampledAt: now, primaryUsedPercent: 1, secondaryUsedPercent: nil),
            for: codex,
            now: now)
        await store.append(
            BurnRateSample(sampledAt: now, primaryUsedPercent: 2, secondaryUsedPercent: nil),
            for: claude,
            now: now)
        await store.remove(key: codex)

        #expect(await store.samples(for: codex).isEmpty)
        #expect(await store.samples(for: claude).count == 1)
    }

    @Test
    func `persistence loads prior samples from disk`() async {
        let baseURL = self.tempBaseURL()
        let key = BurnRateBufferKey(provider: .codex, accountID: "alice")
        let now = Date(timeIntervalSince1970: 1_000_000)

        let store = BurnRateBufferStore(baseURL: baseURL)
        await store.append(
            BurnRateSample(
                sampledAt: now,
                primaryUsedPercent: 42,
                secondaryUsedPercent: nil),
            for: key,
            now: now)

        // A second store rooted at the same baseURL should see the sample.
        let reloaded = BurnRateBufferStore(baseURL: baseURL)
        let samples = await reloaded.samples(for: key)
        #expect(samples.count == 1)
        #expect(samples.first?.primaryUsedPercent == 42)
    }

    @Test
    func `clear empties all keys`() async {
        let store = BurnRateBufferStore(baseURL: self.tempBaseURL())
        let key = BurnRateBufferKey(provider: .codex, accountID: "alice")
        let now = Date(timeIntervalSince1970: 1_000_000)

        await store.append(
            BurnRateSample(sampledAt: now, primaryUsedPercent: 1, secondaryUsedPercent: nil),
            for: key,
            now: now)
        await store.clear()
        #expect(await store.keys().isEmpty)
    }
}
