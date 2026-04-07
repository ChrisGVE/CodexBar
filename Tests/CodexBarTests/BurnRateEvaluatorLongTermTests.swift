import CodexBarCore
import Foundation
import Testing

struct BurnRateEvaluatorLongTermTests {
    private let baseTime = Date(timeIntervalSince1970: 1_000_000)

    private func sample(offset: TimeInterval, primary: Double? = nil) -> BurnRateSample {
        BurnRateSample(
            sampledAt: self.baseTime.addingTimeInterval(offset),
            primaryUsedPercent: primary,
            secondaryUsedPercent: nil)
    }

    @Test
    func `long term defaults to24 hours`() {
        // Build samples spanning 12h with steady 1%/min burn during the
        // first hour, then idle. Long-term lookback (24h) and short-term
        // lookback (1h) should both see the same single active interval
        // and produce the same rate (60%/h).
        var samples: [BurnRateSample] = []
        for i in 0...6 {
            samples.append(self.sample(offset: TimeInterval(i * 600), primary: Double(i * 10)))
        }
        // Idle stretch out to 12h.
        samples.append(self.sample(offset: 12 * 3600, primary: 60))

        let now = self.baseTime.addingTimeInterval(12 * 3600)
        let short = BurnRateEvaluator.shortTerm(samples: samples, window: .primary, now: now)
        let long = BurnRateEvaluator.longTerm(samples: samples, window: .primary, now: now)
        #expect(short == nil) // active samples are >1h ago, outside short lookback
        #expect(long != nil)
        // Long-term sees the active hour: 60% over 60min = 60%/h
        #expect(abs((long?.percentPerHour ?? 0) - 60) < 0.5)
        #expect(long?.isIdleCorrected == true)
        let longLookback = long?.lookback ?? 0
        #expect(longLookback == BurnRateEvaluator.defaultLongTermLookback)
    }

    @Test
    func `long term and short term differ on recent burst`() {
        // Build a 24h history: steady slow burn for 22h (~1%/h), then a
        // sharp burst in the last hour (~30%/h). Short-term should see
        // the burst, long-term should see the average.
        var samples: [BurnRateSample] = []
        // Slow burn: 22 samples, +1% each, 1h apart.
        for i in 0...21 {
            samples.append(self.sample(offset: TimeInterval(i * 3600), primary: Double(i)))
        }
        // Burst: 6 samples in the last hour, +5% each, 10min apart.
        var burstPercent: Double = 22
        for i in 1...6 {
            burstPercent += 5
            samples.append(
                self.sample(
                    offset: TimeInterval(22 * 3600 + i * 600),
                    primary: burstPercent))
        }

        let now = self.baseTime.addingTimeInterval(23 * 3600)
        let short = BurnRateEvaluator.shortTerm(samples: samples, window: .primary, now: now)
        let long = BurnRateEvaluator.longTerm(samples: samples, window: .primary, now: now)

        #expect(short != nil)
        #expect(long != nil)
        // Short-term picks up the burst: 30% over 60min = 30%/h
        #expect(abs((short?.percentPerHour ?? 0) - 30) < 1)
        // Long-term averages slow + burst over 23h of active intervals:
        // 22% slow over 22h + 30% burst over 1h = 52% / 23h ≈ 2.26%/h
        #expect((long?.percentPerHour ?? 0) < 5)
        #expect((long?.percentPerHour ?? 0) > 1)
    }

    @Test
    func `long term returns nil with insufficient samples`() {
        let samples = [
            self.sample(offset: 0, primary: 0),
            self.sample(offset: 3600, primary: 5),
        ]
        let rate = BurnRateEvaluator.longTerm(
            samples: samples,
            window: .primary,
            now: self.baseTime.addingTimeInterval(7200))
        #expect(rate == nil)
    }

    @Test
    func `long term accepts custom lookback`() {
        // 6h of samples, +5% each hour. With a 3h lookback only the
        // last 4 samples (and 3 active intervals) should count.
        var samples: [BurnRateSample] = []
        for i in 0...6 {
            samples.append(self.sample(offset: TimeInterval(i * 3600), primary: Double(i * 5)))
        }

        let now = self.baseTime.addingTimeInterval(6 * 3600)
        let rate = BurnRateEvaluator.longTerm(
            samples: samples,
            window: .primary,
            lookback: 3 * 3600,
            now: now)
        #expect(rate != nil)
        // 15% over 3h of active intervals = 5%/h
        #expect(abs((rate?.percentPerHour ?? 0) - 5) < 0.01)
        let lookback = rate?.lookback ?? 0
        #expect(lookback == 10800)
    }
}
