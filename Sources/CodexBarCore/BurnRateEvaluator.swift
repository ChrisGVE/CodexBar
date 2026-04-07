import Foundation

/// Pure functions that turn a `[BurnRateSample]` series into a `BurnRate`
/// reading. Kept free of any actor or storage so the same evaluator can
/// be unit-tested directly without going through `BurnRateBufferStore`.
public enum BurnRateEvaluator {
    /// Minimum number of samples required to produce a short-term reading.
    public static let minimumShortTermSamples: Int = 3

    /// Default lookback for the short-term reading: the last hour.
    public static let defaultShortTermLookback: TimeInterval = 3600

    /// Default lookback for the long-term reading: the full 24h held by
    /// `BurnRateBufferStore`. Both lines on the trend chart come from the
    /// same ring buffer; only the lookback differs. The PRD originally
    /// proposed reading the long-term series from a percent-based daily
    /// history store, but the project's existing daily history is in
    /// tokens / cost terms and does not expose `usedPercent`, so a unit-
    /// agnostic `% per hour` long-term rate is not derivable from it.
    /// Reading both series from the buffer keeps the trend chart
    /// meaningful (recent rate vs typical recent rate, both idle-
    /// corrected) and removes the need for a new history schema.
    public static let defaultLongTermLookback: TimeInterval = 24 * 3600

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
        lookback: TimeInterval = 3600,
        now: Date = .init()) -> BurnRate?
    {
        self.compute(samples: samples, window: window, lookback: lookback, now: now)
    }

    /// Computes an idle-corrected `BurnRate` over a longer lookback than
    /// `shortTerm`. Reads from the same ring buffer with the same idle-
    /// correction algorithm; the only difference is the default lookback.
    /// The intent is to produce the second line on the trend chart so the
    /// user can compare "rate over the last hour" against "rate over the
    /// last 24h" of active burning.
    public static func longTerm(
        samples: [BurnRateSample],
        window: BurnRateWindowKind,
        lookback: TimeInterval = 24 * 3600,
        now: Date = .init()) -> BurnRate?
    {
        self.compute(samples: samples, window: window, lookback: lookback, now: now)
    }

    private static func compute(
        samples: [BurnRateSample],
        window: BurnRateWindowKind,
        lookback: TimeInterval,
        now: Date) -> BurnRate?
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
            case .primary:
                sample.primaryUsedPercent
            case .secondary:
                sample.secondaryUsedPercent
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
