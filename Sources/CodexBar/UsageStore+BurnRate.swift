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
}
