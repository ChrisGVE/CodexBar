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
}
