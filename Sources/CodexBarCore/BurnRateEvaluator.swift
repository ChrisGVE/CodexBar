import Foundation

/// Pure functions that turn a `[BurnRateSample]` series into a `BurnRate`
/// reading. Kept free of any actor or storage so the same evaluator can
/// be unit-tested directly without going through `BurnRateBufferStore`.
public enum BurnRateEvaluator {
    /// Minimum number of samples required to produce a short-term reading.
    public static let minimumShortTermSamples: Int = 3

    /// Computes an idle-corrected `BurnRate` for the requested window
    /// kind from a sample list.
    ///
    /// The samples must be sorted oldest-first (which is what
    /// `BurnRateBufferStore.samples(for:)` already returns).
    ///
    /// **Idle correction**: the time series is segmented into "active
    /// intervals" of consecutive sample pairs where `usedPercent`
    /// strictly increased. Idle gaps (no change or a decrease, e.g. on
    /// window reset) are excluded from both the numerator and the
    /// denominator. This means stepping away from the machine for an
    /// hour does NOT drag the reported rate toward zero — the rate
    /// reflects "how fast you burn while you are actually burning".
    ///
    /// Returns `nil` when there are not enough samples, when none of the
    /// samples expose a value for the requested window, or when the
    /// series contains no positive deltas at all.
    public static func shortTerm(
        samples: [BurnRateSample],
        window: BurnRateWindowKind,
        lookback: TimeInterval,
        now: Date = .init()) -> BurnRate?
    {
        let cutoff = now.addingTimeInterval(-lookback)
        let series = Self.percentSeries(from: samples, window: window, cutoff: cutoff)
        guard series.count >= Self.minimumShortTermSamples else { return nil }

        var deltaTotal: Double = 0
        var activeDuration: TimeInterval = 0
        for i in 1..<series.count {
            let prev = series[i - 1]
            let curr = series[i]
            let delta = curr.percent - prev.percent
            guard delta > 0 else { continue } // idle or reset, skip
            let duration = curr.date.timeIntervalSince(prev.date)
            guard duration > 0 else { continue }
            deltaTotal += delta
            activeDuration += duration
        }

        guard activeDuration > 0, deltaTotal > 0 else { return nil }
        let percentPerHour = (deltaTotal / activeDuration) * 3600
        return BurnRate(
            percentPerHour: percentPerHour,
            lookback: lookback,
            isIdleCorrected: true,
            sampleCount: series.count)
    }

    /// Extracts the (date, percent) pairs for the requested window kind,
    /// dropping samples that are missing a value or that fall outside
    /// the lookback cutoff.
    private static func percentSeries(
        from samples: [BurnRateSample],
        window: BurnRateWindowKind,
        cutoff: Date) -> [PercentPoint]
    {
        samples.compactMap { sample in
            guard sample.sampledAt >= cutoff else { return nil }
            let value: Double? = switch window {
            case .primary: sample.primaryUsedPercent
            case .secondary: sample.secondaryUsedPercent
            }
            guard let value else { return nil }
            return PercentPoint(date: sample.sampledAt, percent: value)
        }
    }

    private struct PercentPoint {
        let date: Date
        let percent: Double
    }
}
