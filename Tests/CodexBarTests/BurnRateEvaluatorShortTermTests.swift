import CodexBarCore
import Foundation
import Testing

struct BurnRateEvaluatorShortTermTests {
    private let baseTime = Date(timeIntervalSince1970: 1_000_000)

    private func sample(
        offset: TimeInterval,
        primary: Double? = nil,
        secondary: Double? = nil) -> BurnRateSample
    {
        BurnRateSample(
            sampledAt: self.baseTime.addingTimeInterval(offset),
            primaryUsedPercent: primary,
            secondaryUsedPercent: secondary)
    }

    @Test
    func `returns nil when sample count below minimum`() {
        let samples = [
            self.sample(offset: 0, primary: 10),
            self.sample(offset: 60, primary: 20),
        ]
        let rate = BurnRateEvaluator.shortTerm(
            samples: samples,
            window: .primary,
            lookback: 3600,
            now: self.baseTime.addingTimeInterval(120))
        #expect(rate == nil)
    }

    @Test
    func `returns nil when window has no values`() {
        let samples = (0..<5).map { i in
            self.sample(offset: TimeInterval(i * 60), primary: Double(i))
        }
        let rate = BurnRateEvaluator.shortTerm(
            samples: samples,
            window: .secondary,
            lookback: 3600,
            now: self.baseTime.addingTimeInterval(600))
        #expect(rate == nil)
    }

    @Test
    func `computes steady rate`() {
        // 5 samples, +10% every 60s — steady 10%/min = 600%/h
        let samples = (0..<5).map { i in
            self.sample(offset: TimeInterval(i * 60), primary: Double(i * 10))
        }
        let rate = BurnRateEvaluator.shortTerm(
            samples: samples,
            window: .primary,
            lookback: 3600,
            now: self.baseTime.addingTimeInterval(600))
        #expect(rate != nil)
        #expect(abs((rate?.percentPerHour ?? 0) - 600) < 0.01)
        #expect(rate?.isIdleCorrected == true)
        #expect(rate?.sampleCount == 5)
    }

    @Test
    func `excludes idle interval from denominator`() {
        // 4 samples: two early (active), big idle gap, then two more (active).
        // Each active interval: +10% over 60s = 10%/min = 600%/h
        // The 1h idle gap between them must NOT pull the rate down.
        let samples = [
            self.sample(offset: 0, primary: 0),
            self.sample(offset: 60, primary: 10),
            self.sample(offset: 60 + 3600, primary: 10), // idle for 1h
            self.sample(offset: 60 + 3600 + 60, primary: 20),
        ]
        let rate = BurnRateEvaluator.shortTerm(
            samples: samples,
            window: .primary,
            lookback: 24 * 3600,
            now: self.baseTime.addingTimeInterval(7200))
        #expect(rate != nil)
        // delta total = 20, active duration = 120s → 600%/h
        #expect(abs((rate?.percentPerHour ?? 0) - 600) < 0.01)
        #expect(rate?.isIdleCorrected == true)
    }

    @Test
    func `returns nil when all samples are idle`() {
        let samples = [
            self.sample(offset: 0, primary: 50),
            self.sample(offset: 60, primary: 50),
            self.sample(offset: 120, primary: 50),
            self.sample(offset: 180, primary: 50),
        ]
        let rate = BurnRateEvaluator.shortTerm(
            samples: samples,
            window: .primary,
            lookback: 3600,
            now: self.baseTime.addingTimeInterval(180))
        #expect(rate == nil)
    }

    @Test
    func `ignores window reset decrease`() {
        // Window resets in the middle of the series (e.g. session restart).
        // The decrease must be treated as idle, not as a negative burn.
        let samples = [
            self.sample(offset: 0, primary: 80),
            self.sample(offset: 60, primary: 90),
            self.sample(offset: 120, primary: 0), // reset
            self.sample(offset: 180, primary: 5),
            self.sample(offset: 240, primary: 15),
        ]
        let rate = BurnRateEvaluator.shortTerm(
            samples: samples,
            window: .primary,
            lookback: 3600,
            now: self.baseTime.addingTimeInterval(240))
        #expect(rate != nil)
        // active deltas: +10 (60s), +5 (60s), +10 (60s) = 25 over 180s = 500%/h
        #expect(abs((rate?.percentPerHour ?? 0) - 500) < 0.01)
    }

    @Test
    func `drops samples outside lookback`() {
        let samples = [
            self.sample(offset: -7200, primary: 0), // 2h ago — outside 1h lookback
            self.sample(offset: -7140, primary: 100),
            self.sample(offset: 0, primary: 0),
            self.sample(offset: 60, primary: 10),
            self.sample(offset: 120, primary: 20),
        ]
        let rate = BurnRateEvaluator.shortTerm(
            samples: samples,
            window: .primary,
            lookback: 3600,
            now: self.baseTime.addingTimeInterval(120))
        #expect(rate != nil)
        // Only the last 3 samples count: +10 over 60s twice = 20 / 120s = 600%/h
        #expect(rate?.sampleCount == 3)
        #expect(abs((rate?.percentPerHour ?? 0) - 600) < 0.01)
    }

    @Test
    func `computes secondary window separately`() {
        let samples = [
            self.sample(offset: 0, primary: 0, secondary: 10),
            self.sample(offset: 60, primary: 50, secondary: 11),
            self.sample(offset: 120, primary: 100, secondary: 12),
        ]
        let primary = BurnRateEvaluator.shortTerm(
            samples: samples,
            window: .primary,
            lookback: 3600,
            now: self.baseTime.addingTimeInterval(120))
        let secondary = BurnRateEvaluator.shortTerm(
            samples: samples,
            window: .secondary,
            lookback: 3600,
            now: self.baseTime.addingTimeInterval(120))
        #expect(primary != nil)
        #expect(secondary != nil)
        // primary: 100/120s = 3000%/h
        #expect(abs((primary?.percentPerHour ?? 0) - 3000) < 0.01)
        // secondary: 2/120s = 60%/h
        #expect(abs((secondary?.percentPerHour ?? 0) - 60) < 0.01)
    }
}
