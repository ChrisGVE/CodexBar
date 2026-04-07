import Foundation

/// In-memory + on-disk ring buffer that holds recent `BurnRateSample`
/// observations per `(provider, accountID)` key. The buffer is the data
/// source for the **short-term** burn-rate computation; the long-term
/// rate reads from the existing daily history store and does not touch
/// this buffer.
///
/// Storage characteristics:
/// - Bounded in time: samples older than `lookbackWindow` (24h by default)
///   are dropped on every append.
/// - Bounded in count: a hard cap (`maxSamplesPerKey`) protects against
///   pathological refresh rates.
/// - Append-only from the caller's point of view; eviction is internal.
/// - Persisted as a single JSON document under the CodexBar Application
///   Support directory (or an injectable override for tests).
public actor BurnRateBufferStore {
    public static let defaultLookbackWindow: TimeInterval = 24 * 3600
    public static let maxSamplesPerKey: Int = 2000

    private var entries: [BurnRateBufferKey: [BurnRateSample]] = [:]
    private let storageURL: URL?
    private let lookbackWindow: TimeInterval

    /// Creates a store rooted at the default Application Support
    /// location. Loads any existing buffer from disk synchronously.
    public init(
        lookbackWindow: TimeInterval = BurnRateBufferStore.defaultLookbackWindow,
        baseURL: URL? = nil)
    {
        self.lookbackWindow = lookbackWindow
        self.storageURL = Self.storageURL(baseURL: baseURL)
        if let storageURL, let data = try? Data(contentsOf: storageURL) {
            if let decoded = try? JSONDecoder().decode(PersistenceFormat.self, from: data) {
                self.entries = decoded.toEntries()
            }
        }
    }

    /// Appends a sample to the buffer for the given key. Prunes any
    /// samples older than `lookbackWindow` and enforces the
    /// `maxSamplesPerKey` cap by dropping the oldest entries first.
    public func append(_ sample: BurnRateSample, for key: BurnRateBufferKey, now: Date = .init()) {
        var list = self.entries[key] ?? []
        list.append(sample)
        list.sort(by: { $0.sampledAt < $1.sampledAt })
        list = Self.prune(list, now: now, lookbackWindow: self.lookbackWindow)
        self.entries[key] = list
        self.persist()
    }

    /// Returns the current samples for a key, oldest first.
    public func samples(for key: BurnRateBufferKey) -> [BurnRateSample] {
        self.entries[key] ?? []
    }

    /// All keys currently held by the buffer.
    public func keys() -> [BurnRateBufferKey] {
        Array(self.entries.keys)
    }

    /// Removes a single key (and all its samples) from the buffer.
    public func remove(key: BurnRateBufferKey) {
        if self.entries.removeValue(forKey: key) != nil {
            self.persist()
        }
    }

    /// Removes all samples from every key.
    public func clear() {
        self.entries.removeAll()
        self.persist()
    }

    private static func prune(
        _ list: [BurnRateSample],
        now: Date,
        lookbackWindow: TimeInterval) -> [BurnRateSample]
    {
        let cutoff = now.addingTimeInterval(-lookbackWindow)
        var pruned = list.filter { $0.sampledAt >= cutoff }
        if pruned.count > Self.maxSamplesPerKey {
            pruned = Array(pruned.suffix(Self.maxSamplesPerKey))
        }
        return pruned
    }

    private func persist() {
        guard let storageURL else { return }
        let payload = PersistenceFormat(entries: self.entries)
        do {
            let data = try JSONEncoder().encode(payload)
            try FileManager.default.createDirectory(
                at: storageURL.deletingLastPathComponent(),
                withIntermediateDirectories: true)
            try data.write(to: storageURL, options: .atomic)
        } catch {
            // Best-effort persistence; the in-memory buffer is still valid.
        }
    }

    private static func storageURL(baseURL: URL?) -> URL? {
        if let baseURL {
            return baseURL.appendingPathComponent("burn-rate-buffer.json")
        }
        let fm = FileManager.default
        guard let support = fm.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
        else {
            return nil
        }
        return support
            .appendingPathComponent("CodexBar", isDirectory: true)
            .appendingPathComponent("burn-rate-buffer.json")
    }
}

/// On-disk wire format. Keys are flattened to `"<provider>|<accountID>"`
/// strings so the document is a plain JSON object.
private struct PersistenceFormat: Codable {
    let entries: [String: [BurnRateSample]]

    init(entries: [BurnRateBufferKey: [BurnRateSample]]) {
        var flat: [String: [BurnRateSample]] = [:]
        for (key, samples) in entries {
            flat[Self.encode(key)] = samples
        }
        self.entries = flat
    }

    func toEntries() -> [BurnRateBufferKey: [BurnRateSample]] {
        var result: [BurnRateBufferKey: [BurnRateSample]] = [:]
        for (raw, samples) in self.entries {
            if let key = Self.decode(raw) {
                result[key] = samples
            }
        }
        return result
    }

    private static func encode(_ key: BurnRateBufferKey) -> String {
        "\(key.provider.rawValue)|\(key.accountID)"
    }

    private static func decode(_ raw: String) -> BurnRateBufferKey? {
        guard let pipe = raw.firstIndex(of: "|") else { return nil }
        let providerRaw = String(raw[..<pipe])
        let accountID = String(raw[raw.index(after: pipe)...])
        guard let provider = UsageProvider(rawValue: providerRaw) else { return nil }
        return BurnRateBufferKey(provider: provider, accountID: accountID)
    }
}
