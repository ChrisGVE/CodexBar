import Foundation

/// A unit-agnostic measure of how fast a `RateWindow` is being consumed,
/// expressed as `% per hour` of the relevant window. Provider-agnostic
/// because every provider that exposes a `usedPercent` can produce a
/// burn rate without us caring whether the underlying unit is tokens,
/// credits, requests, or anything else.
public struct BurnRate: Sendable, Equatable {
    /// Percentage of the window consumed per hour over the lookback span.
    public let percentPerHour: Double
    /// Span used to compute the rate, in seconds.
    public let lookback: TimeInterval
    /// `true` when idle intervals were excluded from the elapsed denominator.
    /// Only the short-term ring-buffer series can be idle-corrected; the
    /// long-term daily-history series cannot resolve intra-day idle gaps.
    public let isIdleCorrected: Bool
    /// Number of samples that contributed to the rate.
    public let sampleCount: Int

    public init(
        percentPerHour: Double,
        lookback: TimeInterval,
        isIdleCorrected: Bool,
        sampleCount: Int)
    {
        self.percentPerHour = percentPerHour
        self.lookback = lookback
        self.isIdleCorrected = isIdleCorrected
        self.sampleCount = sampleCount
    }
}

/// A single observation captured by the refresh-time ring buffer. Stores
/// the `usedPercent` reading for the primary and secondary windows so the
/// short-term burn rate can be computed by walking the buffer and
/// segmenting it into active intervals.
public struct BurnRateSample: Sendable, Codable, Equatable {
    public let sampledAt: Date
    public let primaryUsedPercent: Double?
    public let secondaryUsedPercent: Double?

    public init(
        sampledAt: Date,
        primaryUsedPercent: Double?,
        secondaryUsedPercent: Double?)
    {
        self.sampledAt = sampledAt
        self.primaryUsedPercent = primaryUsedPercent
        self.secondaryUsedPercent = secondaryUsedPercent
    }
}

/// Identifies which window of a `BurnRateSample` to read when computing
/// a rate. Lets a single buffer drive both primary (session) and
/// secondary (weekly/monthly) burn-rate readings.
public enum BurnRateWindowKind: String, Sendable, Codable, CaseIterable {
    case primary
    case secondary
}

/// Account-aware key for the ring-buffer store. The buffer is keyed by
/// `(provider, accountID)` from day one so the multi-Claude-account
/// feature does not need to retroactively re-key the data.
public struct BurnRateBufferKey: Sendable, Hashable, Codable {
    public let provider: UsageProvider
    public let accountID: String

    public init(provider: UsageProvider, accountID: String) {
        self.provider = provider
        self.accountID = accountID
    }
}
