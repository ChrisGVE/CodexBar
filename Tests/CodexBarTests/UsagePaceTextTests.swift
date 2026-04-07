import CodexBarCore
import Foundation
import Testing
@testable import CodexBar

struct UsagePaceTextTests {
    @Test
    func `weekly pace detail provides left right labels`() {
        let now = Date(timeIntervalSince1970: 0)
        let window = RateWindow(
            usedPercent: 50,
            windowMinutes: 10080,
            resetsAt: now.addingTimeInterval(4 * 24 * 3600),
            resetDescription: nil)

        let detail = UsagePaceText.weeklyDetail(provider: .codex, window: window, now: now)

        #expect(detail?.leftLabel == "7% in deficit")
        #expect(detail?.rightLabel == "Runs out in 3d")
    }

    @Test
    func `weekly pace detail reports lasts until reset`() {
        let now = Date(timeIntervalSince1970: 0)
        let window = RateWindow(
            usedPercent: 10,
            windowMinutes: 10080,
            resetsAt: now.addingTimeInterval(4 * 24 * 3600),
            resetDescription: nil)

        let detail = UsagePaceText.weeklyDetail(provider: .codex, window: window, now: now)

        #expect(detail?.leftLabel == "33% in reserve")
        #expect(detail?.rightLabel == "Lasts until reset")
    }

    @Test
    func `weekly pace summary formats single line text`() {
        let now = Date(timeIntervalSince1970: 0)
        let window = RateWindow(
            usedPercent: 50,
            windowMinutes: 10080,
            resetsAt: now.addingTimeInterval(4 * 24 * 3600),
            resetDescription: nil)

        let summary = UsagePaceText.weeklySummary(provider: .codex, window: window, now: now)

        #expect(summary == "Pace: 7% in deficit · Runs out in 3d")
    }

    @Test
    func `weekly pace detail hides when reset is missing`() {
        let now = Date(timeIntervalSince1970: 0)
        let window = RateWindow(
            usedPercent: 10,
            windowMinutes: 10080,
            resetsAt: nil,
            resetDescription: nil)

        let detail = UsagePaceText.weeklyDetail(provider: .codex, window: window, now: now)

        #expect(detail == nil)
    }

    @Test
    func `weekly pace detail hides when reset is in past or too far`() {
        let now = Date(timeIntervalSince1970: 0)
        let pastWindow = RateWindow(
            usedPercent: 10,
            windowMinutes: 10080,
            resetsAt: now.addingTimeInterval(-60),
            resetDescription: nil)
        let farFutureWindow = RateWindow(
            usedPercent: 10,
            windowMinutes: 10080,
            resetsAt: now.addingTimeInterval(9 * 24 * 3600),
            resetDescription: nil)

        #expect(UsagePaceText.weeklyDetail(provider: .codex, window: pastWindow, now: now) == nil)
        #expect(UsagePaceText.weeklyDetail(provider: .codex, window: farFutureWindow, now: now) == nil)
    }

    @Test
    func `weekly pace detail hides when no elapsed but usage exists`() {
        let now = Date(timeIntervalSince1970: 0)
        let window = RateWindow(
            usedPercent: 5,
            windowMinutes: 10080,
            resetsAt: now.addingTimeInterval(7 * 24 * 3600),
            resetDescription: nil)

        let detail = UsagePaceText.weeklyDetail(provider: .codex, window: window, now: now)

        #expect(detail == nil)
    }

    @Test
    func `weekly pace detail hides when too early in window`() {
        let now = Date(timeIntervalSince1970: 0)
        let window = RateWindow(
            usedPercent: 40,
            windowMinutes: 10080,
            resetsAt: now.addingTimeInterval((7 * 24 * 3600) - (60 * 60)),
            resetDescription: nil)

        let detail = UsagePaceText.weeklyDetail(provider: .codex, window: window, now: now)

        #expect(detail == nil)
    }

    @Test
    func `weekly pace detail hides when usage is depleted`() {
        let now = Date(timeIntervalSince1970: 0)
        let window = RateWindow(
            usedPercent: 100,
            windowMinutes: 10080,
            resetsAt: now.addingTimeInterval(2 * 24 * 3600),
            resetDescription: nil)

        let detail = UsagePaceText.weeklyDetail(provider: .codex, window: window, now: now)

        #expect(detail == nil)
    }

    @Test
    func `supports session pace includes session based providers`() {
        #expect(UsagePaceText.supportsSessionPace(for: .codex))
        #expect(UsagePaceText.supportsSessionPace(for: .claude))
    }

    @Test
    func `supports session pace excludes non session providers`() {
        for provider in UsageProvider.allCases where provider != .codex && provider != .claude {
            #expect(!UsagePaceText.supportsSessionPace(for: provider))
        }
    }

    @Test
    func `session pace returns nil for non session providers`() {
        let now = Date(timeIntervalSince1970: 0)
        let window = RateWindow(
            usedPercent: 50,
            windowMinutes: 300,
            resetsAt: now.addingTimeInterval(150 * 60),
            resetDescription: nil)
        #expect(UsagePaceText.sessionPace(provider: .zai, window: window, now: now) == nil)
    }

    @Test
    func `session pace returns nil when window depleted`() {
        let now = Date(timeIntervalSince1970: 0)
        let window = RateWindow(
            usedPercent: 100,
            windowMinutes: 300,
            resetsAt: now.addingTimeInterval(150 * 60),
            resetDescription: nil)
        #expect(UsagePaceText.sessionPace(provider: .codex, window: window, now: now) == nil)
    }

    @Test
    func `session pace returns nil before minimum elapsed`() {
        // Less than 10% of a 5h window has elapsed (~25 min) so pace is suppressed.
        let now = Date(timeIntervalSince1970: 0)
        let window = RateWindow(
            usedPercent: 5,
            windowMinutes: 300,
            resetsAt: now.addingTimeInterval((300 - 25) * 60),
            resetDescription: nil)
        #expect(UsagePaceText.sessionPace(provider: .codex, window: window, now: now) == nil)
    }

    @Test
    func `session pace returns pace after minimum elapsed`() {
        // ~50% elapsed in a 5h window (150 min in), well past the 10% guard.
        let now = Date(timeIntervalSince1970: 0)
        let window = RateWindow(
            usedPercent: 50,
            windowMinutes: 300,
            resetsAt: now.addingTimeInterval(150 * 60),
            resetDescription: nil)
        let pace = UsagePaceText.sessionPace(provider: .codex, window: window, now: now)
        #expect(pace != nil)
        #expect(pace?.actualUsedPercent == 50)
        #expect(pace?.expectedUsedPercent == 50)
    }

    @Test
    func `session pace supports claude`() {
        let now = Date(timeIntervalSince1970: 0)
        let window = RateWindow(
            usedPercent: 40,
            windowMinutes: 300,
            resetsAt: now.addingTimeInterval(150 * 60),
            resetDescription: nil)
        #expect(UsagePaceText.sessionPace(provider: .claude, window: window, now: now) != nil)
    }

    @Test
    func `session detail provides labels`() {
        // 50% elapsed in a 5h window, 70% used → 20% deficit
        let now = Date(timeIntervalSince1970: 0)
        let window = RateWindow(
            usedPercent: 70,
            windowMinutes: 300,
            resetsAt: now.addingTimeInterval(150 * 60),
            resetDescription: nil)
        let detail = UsagePaceText.sessionDetail(provider: .codex, window: window, now: now)
        #expect(detail?.leftLabel == "20% in deficit")
        #expect(detail?.rightLabel != nil)
    }

    @Test
    func `session detail returns nil for unsupported provider`() {
        let now = Date(timeIntervalSince1970: 0)
        let window = RateWindow(
            usedPercent: 50,
            windowMinutes: 300,
            resetsAt: now.addingTimeInterval(150 * 60),
            resetDescription: nil)
        #expect(UsagePaceText.sessionDetail(provider: .zai, window: window, now: now) == nil)
    }

    @Test
    func `session summary formats single line text`() {
        let now = Date(timeIntervalSince1970: 0)
        let window = RateWindow(
            usedPercent: 70,
            windowMinutes: 300,
            resetsAt: now.addingTimeInterval(150 * 60),
            resetDescription: nil)
        let summary = UsagePaceText.sessionSummary(provider: .codex, window: window, now: now)
        #expect(summary?.hasPrefix("Pace: 20% in deficit") == true)
    }
}
