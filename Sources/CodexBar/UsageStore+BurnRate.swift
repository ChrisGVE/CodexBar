import CodexBarCore
import Foundation

@MainActor
extension UsageStore {
    /// Captures a `BurnRateSample` from the freshly fetched snapshot and
    /// appends it to the ring buffer for `(provider, accountID)`. Called
    /// from the refresh success path so the buffer reflects every
    /// successful observation.
    ///
    /// The accountID is derived from the snapshot's identity (the account
    /// email when present, otherwise an empty string). This keeps the
    /// buffer forward-compatible with the multi-Claude-account feature
    /// without requiring that feature's storage changes today.
    func recordBurnRateSample(provider: UsageProvider, snapshot: UsageSnapshot) async {
        let accountID = self.burnRateAccountID(for: provider, snapshot: snapshot)
        let key = BurnRateBufferKey(provider: provider, accountID: accountID)
        let sample = BurnRateSample(
            sampledAt: snapshot.updatedAt,
            primaryUsedPercent: snapshot.primary?.usedPercent,
            secondaryUsedPercent: snapshot.secondary?.usedPercent)
        await self.burnRateBufferStore.append(sample, for: key, now: snapshot.updatedAt)

        // Recompute the cached short-term and long-term rates so synchronous
        // menu rendering can read them without going through the actor each time.
        let samples = await self.burnRateBufferStore.samples(for: key)
        self.primaryBurnRates[provider] = BurnRateEvaluator.shortTerm(
            samples: samples,
            window: .primary,
            now: snapshot.updatedAt)
        self.secondaryBurnRates[provider] = BurnRateEvaluator.shortTerm(
            samples: samples,
            window: .secondary,
            now: snapshot.updatedAt)
        self.primaryLongTermBurnRates[provider] = BurnRateEvaluator.longTerm(
            samples: samples,
            window: .primary,
            now: snapshot.updatedAt)
        self.secondaryLongTermBurnRates[provider] = BurnRateEvaluator.longTerm(
            samples: samples,
            window: .secondary,
            now: snapshot.updatedAt)
    }

    /// Sync accessor for the cached short-term primary-window rate.
    func primaryBurnRate(for provider: UsageProvider) -> BurnRate? {
        self.primaryBurnRates[provider]
    }

    /// Sync accessor for the cached short-term secondary-window rate.
    func secondaryBurnRate(for provider: UsageProvider) -> BurnRate? {
        self.secondaryBurnRates[provider]
    }

    /// Sync accessor for the cached long-term primary-window rate.
    func primaryLongTermBurnRate(for provider: UsageProvider) -> BurnRate? {
        self.primaryLongTermBurnRates[provider]
    }

    /// Sync accessor for the cached long-term secondary-window rate.
    func secondaryLongTermBurnRate(for provider: UsageProvider) -> BurnRate? {
        self.secondaryLongTermBurnRates[provider]
    }

    /// Formats a short-term `BurnRate` plus an optional long-term peer
    /// for comparison. Returns `nil` when no short-term rate exists.
    /// When a long-term rate is also present the label appends a small
    /// trend hint, e.g. `12.4 %/h (vs 5.1 %/h 24h)`. Both lines are
    /// idle-corrected — see BurnRateEvaluator for the asymmetry note.
    static func burnRateLabel(short: BurnRate?, long: BurnRate? = nil) -> String? {
        guard let short else { return nil }
        let shortText = String(format: "%.1f %%/h", short.percentPerHour)
        guard let long else { return shortText }
        let longText = String(format: "%.1f", long.percentPerHour)
        return "\(shortText) (vs \(longText) 24h)"
    }

    private func burnRateAccountID(for provider: UsageProvider, snapshot: UsageSnapshot) -> String {
        snapshot.identity?.accountEmail?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
    }

    /// Account-aware key for the burn-rate buffer derived from the
    /// currently held snapshot. Returns `nil` if no snapshot exists yet.
    private func burnRateKey(for provider: UsageProvider) -> BurnRateBufferKey? {
        guard let snapshot = self.snapshots[provider] else { return nil }
        return BurnRateBufferKey(
            provider: provider,
            accountID: self.burnRateAccountID(for: provider, snapshot: snapshot))
    }

    /// Reads the short-term (idle-corrected) burn rate for the given
    /// provider/window from the ring buffer. Returns `nil` if there is
    /// no current snapshot or not enough samples to compute a rate.
    func shortTermBurnRate(
        provider: UsageProvider,
        window: BurnRateWindowKind,
        now: Date = .init()) async -> BurnRate?
    {
        guard let key = self.burnRateKey(for: provider) else { return nil }
        let samples = await self.burnRateBufferStore.samples(for: key)
        return BurnRateEvaluator.shortTerm(samples: samples, window: window, now: now)
    }

    /// Reads the long-term (idle-corrected) burn rate for the given
    /// provider/window from the same ring buffer with a longer lookback.
    func longTermBurnRate(
        provider: UsageProvider,
        window: BurnRateWindowKind,
        now: Date = .init()) async -> BurnRate?
    {
        guard let key = self.burnRateKey(for: provider) else { return nil }
        let samples = await self.burnRateBufferStore.samples(for: key)
        return BurnRateEvaluator.longTerm(samples: samples, window: window, now: now)
    }
}
