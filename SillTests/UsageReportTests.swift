import Foundation
import Testing

@testable import Sill

/// Reading `GET /usage` of `codexbar serve`, from a response captured from CodexBar 0.74.0 without its account fields.
struct UsageReportTests {
    private static let response = #"""
        [
          {
            "provider": "codex",
            "source": "oauth",
            "pace": {
              "secondary": {"deltaPercent": -5, "expectedUsedPercent": 7, "stage": "slightlyBehind", "willLastToReset": true}
            },
            "rateWindowLabels": {"secondary": "Weekly"},
            "resetCredits": {"available": 3, "nextExpiresAt": "2026-10-22T20:21:40Z"},
            "usage": {
              "loginMethod": "prolite",
              "primary": null,
              "secondary": {"resetsAt": "2026-10-18T04:10:45Z", "usedPercent": 2, "windowMinutes": 10080},
              "tertiary": null,
              "providerCost": {"currencyCode": "Credits", "limit": 0, "period": "Extra usage", "used": 0}
            }
          },
          {
            "provider": "claude",
            "source": "web",
            "pace": {
              "primary": {"deltaPercent": -72, "expectedUsedPercent": 82, "stage": "farBehind", "willLastToReset": true},
              "secondary": {"deltaPercent": 3, "etaSeconds": 400100, "expectedUsedPercent": 10, "stage": "slightlyAhead", "willLastToReset": false}
            },
            "usage": {
              "loginMethod": "Claude Max 20x",
              "primary": {"resetsAt": "2026-10-11T17:30:00Z", "usedPercent": 10, "windowMinutes": 300},
              "secondary": {"resetsAt": "2026-10-18T00:00:00Z", "usedPercent": 13, "windowMinutes": 10080},
              "extraRateWindows": [
                {"id": "claude-weekly-scoped-fable", "title": "Fable only",
                 "window": {"resetsAt": "2026-10-18T00:00:00Z", "usedPercent": 0, "windowMinutes": 10080}}
              ],
              "providerCost": {"balance": 0, "currencyCode": "USD", "limit": 40, "period": "Monthly cap", "used": 0},
              "details": [
                {"rows": [{"label": "Limit Reset Credits", "secondaryValue": "Expires Oct 23 at 1:00 AM", "value": "1 available"}]}
              ]
            }
          }
        ]
        """#

    @Test func readsServicesInTheWidgetsOrder() throws {
        let report = try UsageReport(from: Data(Self.response.utf8))
        #expect(report.services.map(\.service) == [.claude, .codex])
    }

    @Test func pairsEachWindowWithItsPace() throws {
        let claude = try #require(try UsageReport(from: Data(Self.response.utf8)).services.first)
        #expect(claude.windows.map(\.window.windowMinutes) == [300, 10080])
        #expect(claude.windows.map { $0.pace?.deltaPercent } == [-72, 3])
        #expect(claude.windows[1].pace?.etaSeconds == 400100)
        #expect(claude.usage.loginMethod == "Claude Max 20x")
        #expect(claude.usage.extraRateWindows?.map(\.title) == ["Fable only"])
        #expect(claude.usage.details?.first?.rows?.first?.value == "1 available")
    }

    @Test func showsExtraUsageOnlyWhenTheAccountHasIt() throws {
        let services = try UsageReport(from: Data(Self.response.utf8)).services
        #expect(services[0].usage.providerCost?.isInUse == true)
        // Codex reports 0 of 0 credits for an account without extra usage.
        #expect(services[1].usage.providerCost?.isInUse == false)
    }

    @Test func readsCodexResetCreditsAndItsOnlyWindow() throws {
        let codex = try #require(try UsageReport(from: Data(Self.response.utf8)).services.last)
        #expect(codex.windows.map(\.window.windowMinutes) == [10080])
        #expect(codex.resetCredits?.available == 3)
    }

    @Test func leavesOutAServiceThatFailed() throws {
        let response = #"""
            [{"provider": "codex", "source": "oauth", "error": {"code": 1, "message": "boom", "kind": "provider"}},
             {"provider": "claude", "usage": {"primary": {"usedPercent": 5, "windowMinutes": 300}}}]
            """#
        let report = try UsageReport(from: Data(response.utf8))
        #expect(report.services.map(\.service) == [.claude])
    }

    @Test func leavesOutAServiceWithoutWindows() throws {
        let response = #"[{"provider": "claude", "usage": {"primary": null, "secondary": null}}]"#
        #expect(try UsageReport(from: Data(response.utf8)).services.isEmpty)
    }

    @Test func readsDatesWithFractionalSeconds() throws {
        let response = #"""
            [{"provider": "claude", "usage": {"primary": {"usedPercent": 5, "resetsAt": "2026-10-12T01:02:03.456Z"}}}]
            """#
        let window = try #require(try UsageReport(from: Data(response.utf8)).services.first?.windows.first?.window)
        let resetsAt = try #require(window.resetsAt)
        #expect(abs(resetsAt.timeIntervalSince1970 - 1_791_766_923.456) < 0.001)
    }

    @Test func failsOnTheOldCommandsOutput() {
        let output = #"{"claude": {"primary": {"pct": 10, "reset": "2h"}}}"#
        #expect(throws: DecodingError.self) { try UsageReport(from: Data(output.utf8)) }
    }

    @Test func hidesAResetThatHasPassed() throws {
        let window = UsageWindow(usedPercent: 10, windowMinutes: 300, resetsAt: Date(timeIntervalSince1970: 100))
        #expect(window.resetText(now: Date(timeIntervalSince1970: 200)) == nil)
        #expect(window.resetDateText(now: Date(timeIntervalSince1970: 200)) == nil)
    }

    @Test func roundsDurationsDown() {
        // The unit names depend on the language, so only the numbers are compared.
        #expect(compactDuration(400_100).hasPrefix("4"))
        #expect(compactDuration(5_399).hasPrefix("1"))
        #expect(compactDuration(400_100, maximumUnitCount: 2).filter(\.isNumber) == "415")
    }
}
