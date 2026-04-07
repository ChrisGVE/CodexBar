import CodexBarCore
import Foundation
import Testing

struct BurnRateTypesTests {
    @Test
    func `burn rate stores all properties`() {
        let rate = BurnRate(
            percentPerHour: 12.5,
            lookback: 3600,
            isIdleCorrected: true,
            sampleCount: 8)
        #expect(rate.percentPerHour == 12.5)
        #expect(rate.lookback == 3600)
        #expect(rate.isIdleCorrected == true)
        #expect(rate.sampleCount == 8)
    }

    @Test
    func `burn rate equatable`() {
        let a = BurnRate(percentPerHour: 5, lookback: 60, isIdleCorrected: false, sampleCount: 2)
        let b = BurnRate(percentPerHour: 5, lookback: 60, isIdleCorrected: false, sampleCount: 2)
        let c = BurnRate(percentPerHour: 6, lookback: 60, isIdleCorrected: false, sampleCount: 2)
        #expect(a == b)
        #expect(a != c)
    }

    @Test
    func `burn rate sample codable round trip`() throws {
        let sample = BurnRateSample(
            sampledAt: Date(timeIntervalSince1970: 1_234_567),
            primaryUsedPercent: 42.5,
            secondaryUsedPercent: nil)
        let encoded = try JSONEncoder().encode(sample)
        let decoded = try JSONDecoder().decode(BurnRateSample.self, from: encoded)
        #expect(decoded == sample)
    }

    @Test
    func `burn rate window kind has all cases`() {
        #expect(BurnRateWindowKind.allCases == [.primary, .secondary])
    }

    @Test
    func `burn rate buffer key hashable uses provider and account`() {
        let a = BurnRateBufferKey(provider: .codex, accountID: "alice")
        let b = BurnRateBufferKey(provider: .codex, accountID: "alice")
        let c = BurnRateBufferKey(provider: .codex, accountID: "bob")
        let d = BurnRateBufferKey(provider: .claude, accountID: "alice")
        #expect(a == b)
        #expect(a != c)
        #expect(a != d)

        var seen: Set<BurnRateBufferKey> = []
        seen.insert(a)
        #expect(seen.contains(b))
        #expect(!seen.contains(c))
    }

    @Test
    func `burn rate buffer key codable round trip`() throws {
        let key = BurnRateBufferKey(provider: .claude, accountID: "work")
        let encoded = try JSONEncoder().encode(key)
        let decoded = try JSONDecoder().decode(BurnRateBufferKey.self, from: encoded)
        #expect(decoded == key)
    }
}
