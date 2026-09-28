import XCTest
@testable import withMemento

/// Spec 021 R1/R3: what `PaywallView` shows, built from store-shaped fixtures
/// (`PaywallFixtures`, RevenueCat `TestStoreProduct`s). No SDK is configured.
@MainActor
final class PaywallPlanTests: XCTestCase {

    private func plans() -> [PaywallPlan] {
        PaywallPlan.ordered(from: PaywallFixtures.offering())
    }

    private func plan(_ kind: PaywallPlanKind) throws -> PaywallPlan {
        try XCTUnwrap(plans().first { $0.kind == kind })
    }

    // MARK: - Order (R1)

    /// The fixture lists monthly before annual; the paywall still leads with
    /// the year. Memento Pro is a subscription only: no lifetime plan.
    func testAnnualComesFirstWhateverTheOfferingOrder() {
        XCTAssertEqual(plans().map(\.kind), [.annual, .monthly])
        XCTAssertEqual(PaywallPlanKind.allCases, [.annual, .monthly])
    }

    func testNoOfferingMeansNoPlans() {
        XCTAssertTrue(PaywallPlan.ordered(from: nil).isEmpty)
    }

    // MARK: - Savings

    /// 59.99 a year against 12 × 9.99 (119.88) is a 49.96% saving, shown as
    /// 49. It rounds down, never up to "half off".
    func testSavingsRoundsDown() {
        let all = plans()
        XCTAssertEqual(
            PaywallPlan.savingsPercent(
                annual: all.first { $0.kind == .annual },
                monthly: all.first { $0.kind == .monthly }
            ),
            49
        )
    }

    func testNoSavingsWithoutAMonthlyToCompare() {
        XCTAssertNil(PaywallPlan.savingsPercent(annual: plans().first, monthly: nil))
    }

    // MARK: - Button and terms (App Review 3.1.2)

    /// No trial: the button frames Pro as an upgrade and says exactly what is
    /// charged and how often, from the store's own price.
    func testButtonNamesThePriceAndPeriod() throws {
        let annual = try plan(.annual)
        XCTAssertEqual(annual.ctaTitle, "Upgrade for \(annual.price) a year")
        let monthly = try plan(.monthly)
        XCTAssertEqual(monthly.ctaTitle, "Upgrade for \(monthly.price) a month")
    }

    func testTermsSayItRenewsAndCanBeCancelled() throws {
        XCTAssertEqual(try plan(.annual).disclosure, "Auto-renews yearly. Cancel anytime.")
        XCTAssertEqual(try plan(.monthly).disclosure, "Auto-renews monthly. Cancel anytime.")
    }

    /// The free tier is the trial. No copy may promise a free trial.
    func testNoCopyPromisesATrial() {
        let copy = plans().flatMap { [$0.ctaTitle, $0.disclosure, $0.accessibilityLabel(savingsPercent: nil)] }
            + allCopy.flatMap { [$0.title, $0.subtitle] }
        for line in copy {
            XCTAssertFalse(line.localizedCaseInsensitiveContains("trial"), line)
            XCTAssertFalse(line.localizedCaseInsensitiveContains("days free"), line)
        }
    }

    func testPlanAccessibilityLabelReadsAsOnePhrase() throws {
        let label = try plan(.annual).accessibilityLabel(savingsPercent: 49)
        XCTAssertTrue(label.hasPrefix("Yearly, "), label)
        XCTAssertTrue(label.hasSuffix("save 49 percent"), label)
    }

    // MARK: - Features (R4)

    /// DEC-013: "what they get, with memory and insights first".
    func testMemoryAndInsightsLead() {
        XCTAssertEqual(PaywallFeature.all.prefix(2).map(\.name), ["Memory across all your entries", "Insights and patterns"])
        XCTAssertEqual(PaywallFeature.proOnly.count, 4)
    }

    /// R4: journaling, reading and export are free forever. Export must
    /// never appear as Pro only.
    func testFreeForeverRowsAreFree() {
        let free = PaywallFeature.all.filter(\.inFree).map(\.name)
        XCTAssertEqual(free, ["Unlimited journaling", "Read and export every entry"])
        XCTAssertFalse(PaywallFeature.proOnly.contains { $0.name.localizedCaseInsensitiveContains("export") })
        XCTAssertEqual(PaywallFeature.all.last?.accessibilityLabel, "Read and export every entry: included free")
        XCTAssertEqual(PaywallFeature.all.first?.accessibilityLabel, "Memory across all your entries: Pro only")
    }

    // MARK: - Headline follows the action and the journal (R9, R10)

    /// A spread of journal states: empty, one entry, a few, rich, very
    /// large; quiet and busy weeks; Sunday or not.
    private var contexts: [PaywallContext] {
        var all: [PaywallContext] = []
        for count in [0, 1, 2, 4, 5, 9, 10, 57, 1_234] {
            for week in [0, 1, 2, 7, 99, 150] where week <= max(count, 150) {
                for sunday in [false, true] {
                    all.append(PaywallContext(entryCount: count, entriesThisWeek: week, isSunday: sunday))
                }
            }
        }
        return all
    }

    /// Every headline and description, in every context.
    private var allCopy: [(title: String, subtitle: String)] {
        contexts.flatMap { context in
            PaywallTrigger.allCases.map { ($0.title(in: context), $0.subtitle(in: context)) }
        }
    }

    /// Headlines fit two serif lines; descriptions are one short line.
    func testCopyStaysShortInEveryContext() {
        for (title, subtitle) in allCopy {
            XCTAssertLessThanOrEqual(title.count, 30, title)
            XCTAssertLessThanOrEqual(subtitle.count, 60, subtitle)
        }
    }

    /// Headlines and descriptions never show a number. Context only chooses
    /// the phrase.
    func testCopyNeverShowsANumber() {
        for (title, subtitle) in allCopy {
            XCTAssertNil(title.rangeOfCharacter(from: .decimalDigits), title)
            XCTAssertNil(subtitle.rangeOfCharacter(from: .decimalDigits), subtitle)
        }
    }

    /// Headlines are complete, declarative lines: each ends in a full stop
    /// or a question mark.
    func testHeadlinesAreCompleteLines() {
        for (title, _) in allCopy {
            XCTAssertTrue(title.hasSuffix(".") || title.hasSuffix("?"), title)
        }
    }

    /// In any one context, each entry point has its own headline.
    func testEveryTriggerHasItsOwnHeadlineInEveryContext() {
        for context in contexts {
            let titles = PaywallTrigger.allCases.map { $0.title(in: context) }
            XCTAssertEqual(Set(titles).count, titles.count, "two triggers share a headline in \(context)")
        }
    }

    func testOpenedFromSettings() {
        XCTAssertEqual(PaywallTrigger.settings.title(in: .unknown), "Your journal, remembered.")
        XCTAssertEqual(
            PaywallTrigger.settings.subtitle(in: .unknown),
            "Pro brings memory to every entry. Your writing stays free."
        )
    }

    /// "Every entry" only once there is more than one.
    func testAskHeadlineMatchesTheJournal() {
        let ask = PaywallTrigger.askWholeJournal
        XCTAssertEqual(ask.title(in: PaywallContext(entryCount: 1, entriesThisWeek: 1, isSunday: false)), "A chat that remembers.")
        XCTAssertEqual(ask.title(in: PaywallContext(entryCount: 30, entriesThisWeek: 1, isSunday: false)), "Every entry. One conversation.")
    }

    /// The weekly copy speaks to this week only when there's something to
    /// recap, and says "today" only on Sunday.
    func testWeeklyCopyMatchesTheWeek() {
        let weekly = PaywallTrigger.weeklyReview
        let busySunday = PaywallContext(entryCount: 20, entriesThisWeek: 4, isSunday: true)
        XCTAssertEqual(weekly.title(in: busySunday), "Your week, in focus.")
        XCTAssertEqual(weekly.subtitle(in: busySunday), "Pro turns this week's writing into today's recap.")
        let quietTuesday = PaywallContext(entryCount: 20, entriesThisWeek: 1, isSunday: false)
        XCTAssertEqual(weekly.title(in: quietTuesday), "One week at a time.")
        XCTAssertEqual(weekly.subtitle(in: quietTuesday), "Pro writes a short recap of your week, every Sunday.")
    }

    /// Patterns are promised only once there's enough writing to find them.
    func testPatternsCopyMatchesTheHistory() {
        let patterns = PaywallTrigger.patterns
        XCTAssertEqual(patterns.title(in: PaywallContext(entryCount: 3, entriesThisWeek: 0, isSunday: false)), "Patterns take time.")
        XCTAssertEqual(patterns.title(in: PaywallContext(entryCount: 40, entriesThisWeek: 0, isSunday: false)), "See what repeats.")
    }

    func testContextCountsThisWeekAndSunday() throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "America/Chicago")!
        calendar.firstWeekday = 1
        let iso = ISO8601DateFormatter()
        let sunday = try XCTUnwrap(iso.date(from: "2026-09-27T10:00:00-05:00"))
        let entries = [
            Entry(createdAt: try XCTUnwrap(iso.date(from: "2026-09-27T08:00:00-05:00"))),
            Entry(createdAt: try XCTUnwrap(iso.date(from: "2026-09-26T08:00:00-05:00"))),
        ]
        let context = PaywallContext(entries: entries, now: sunday, calendar: calendar)
        XCTAssertEqual(context.entryCount, 2)
        XCTAssertEqual(context.entriesThisWeek, 1, "Saturday belongs to last week when weeks start on Sunday")
        XCTAssertTrue(context.isSunday)
    }

    /// Placements are spec 021 R9's table, plus Settings.
    func testPlacementsMatchTheReOfferTable() {
        let placements = Set(PaywallTrigger.allCases.map(\.placement))
        XCTAssertEqual(placements, [
            "settings", "onboarding", "second_chat", "daily_limit",
            "clear_chat", "chat_summary", "weekly_review", "locked_surface",
        ])
    }

    /// Every `.proGated("…")` maps to its own trigger, so the paywall a lock
    /// card opens always speaks to that surface.
    func testEveryGatedSurfaceHasATrigger() throws {
        let root = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("withMemento")
        let gate = try NSRegularExpression(pattern: #"\.proGated\("([^"]+)"\)"#)
        var found = 0
        let files = FileManager.default.enumerator(at: root, includingPropertiesForKeys: nil)?
            .compactMap { $0 as? URL }
            .filter { $0.pathExtension == "swift" } ?? []
        for file in files {
            let text = try String(contentsOf: file, encoding: .utf8)
            for match in gate.matches(in: text, range: NSRange(text.startIndex..., in: text)) {
                let name = (text as NSString).substring(with: match.range(at: 1))
                found += 1
                XCTAssertNotNil(PaywallTrigger(gate: name), "\(file.lastPathComponent) gates \"\(name)\", which has no PaywallTrigger")
            }
        }
        XCTAssertGreaterThan(found, 0, "scan found no gated surfaces — path wrong?")
    }

    // MARK: - Model

    func testPreviewModelSelectsAnnualAndNeverPurchases() async {
        let model = PaywallModel.preview()
        XCTAssertEqual(model.selected?.kind, .annual)
        XCTAssertEqual(model.savingsPercent, 49)
        let purchased = await model.purchase()
        XCTAssertFalse(purchased)
        EntitlementStore.shared.lastError = nil
    }

    // MARK: - R1: no price literal

    /// Spec 021 R1 verification: no price literal in the paywall module.
    /// Every price comes from the store. Checks the text of string literals
    /// only, with interpolations removed, so `$0` closures and "\($0)" don't
    /// count and a literal like "$9.99" does.
    func testNoPriceLiteralsInThePaywallModule() throws {
        let folder = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("withMemento/Views/Purchases")
        let files = try FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: nil)
            .filter { $0.pathExtension == "swift" }
        XCTAssertFalse(files.isEmpty, "scan found no paywall files — path wrong?")
        let stringLiteral = try NSRegularExpression(pattern: #""(?:[^"\\\n]|\\.)*""#)
        let interpolation = try NSRegularExpression(pattern: #"\\\([^)]*\)"#)
        let priceLiteral = try NSRegularExpression(pattern: #"\$[0-9]"#)
        for file in files {
            let text = try String(contentsOf: file, encoding: .utf8)
            for match in stringLiteral.matches(in: text, range: NSRange(text.startIndex..., in: text)) {
                let literal = (text as NSString).substring(with: match.range)
                let stripped = interpolation.stringByReplacingMatches(
                    in: literal, range: NSRange(literal.startIndex..., in: literal), withTemplate: ""
                )
                XCTAssertNil(
                    priceLiteral.firstMatch(in: stripped, range: NSRange(stripped.startIndex..., in: stripped)),
                    "\(file.lastPathComponent) has a price literal: \(literal)"
                )
            }
        }
    }

    /// The scan itself: catches a literal, ignores closures and interpolation.
    func testPriceLiteralScanPattern() throws {
        let priceLiteral = try NSRegularExpression(pattern: #"\$[0-9]"#)
        let interpolation = try NSRegularExpression(pattern: #"\\\([^)]*\)"#)
        func flags(_ literal: String) -> Bool {
            let stripped = interpolation.stringByReplacingMatches(
                in: literal, range: NSRange(literal.startIndex..., in: literal), withTemplate: ""
            )
            return priceLiteral.firstMatch(in: stripped, range: NSRange(stripped.startIndex..., in: stripped)) != nil
        }
        XCTAssertTrue(flags(#""Only $9.99 a month""#))
        XCTAssertFalse(flags(#""\($0) per month""#))
    }
}
