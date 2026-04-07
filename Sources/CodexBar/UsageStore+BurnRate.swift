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
