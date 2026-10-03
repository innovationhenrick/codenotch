import Foundation

/// The documented Notion Agent Insights response for the personal agent.
/// This is premium-credit usage for the current billing window, not the
/// included six-hour/monthly Notion AI allowance or raw model-token counts.
enum NotionAIUsage {
    static let agentID = "notion_ai"

    struct Reading: Equatable {
        let creditsUsed: Double
        let creditLimit: Double?
        let runsCompleted: Int

        var usedFraction: Double? {
            guard let creditLimit, creditLimit > 0 else { return nil }
            return creditsUsed / creditLimit
        }
    }

    static func reading(from data: Data) throws -> Reading {
        guard let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let credits = number(root["total_credits_used"]), credits.isFinite, credits >= 0,
              let runsRaw = number(root["runs_completed"]), runsRaw.isFinite,
              runsRaw >= 0, runsRaw.rounded() == runsRaw,
              let runs = Int(exactly: runsRaw)
        else { throw UsageProviderError.badResponse(status: 0) }

        let limitValue = root["credit_limit"]
        let limit: Double?
        if limitValue == nil || limitValue is NSNull {
            limit = nil
        } else if let parsed = number(limitValue), parsed.isFinite, parsed >= 0 {
            limit = parsed > 0 ? parsed : nil
        } else if let marker = limitValue as? String, marker == "hidden" {
            // Notion deliberately hides an agent's cap from callers without
            // full access. Its credit count remains useful, but the ring would
            // have no honest denominator.
            limit = nil
        } else {
            throw UsageProviderError.badResponse(status: 0)
        }

        return Reading(creditsUsed: credits, creditLimit: limit, runsCompleted: runs)
    }

    static func windows(from data: Data) throws -> [LimitWindow] {
        let reading = try reading(from: data)
        let amount = credits(reading.creditsUsed)
        let runs = reading.runsCompleted
        let detail = String(format: L10n.t("%@ credits · %d runs"), amount, runs)
        return [LimitWindow(
            id: "premium-credits",
            label: L10n.t("Premium AI credits"),
            usedFraction: reading.usedFraction,
            used: Int(exactly: reading.creditsUsed.rounded()),
            usedText: String(format: L10n.t("%@ credits"), amount),
            detail: detail
        )]
    }

    static func credits(_ value: Double) -> String {
        let formatter = NumberFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.numberStyle = .decimal
        formatter.usesGroupingSeparator = true
        formatter.groupingSeparator = ","
        formatter.decimalSeparator = "."
        formatter.minimumFractionDigits = 0
        formatter.maximumFractionDigits = 2
        return formatter.string(from: NSNumber(value: value))
            ?? String(format: "%.2f", locale: Locale(identifier: "en_US_POSIX"), value)
    }

    private static func number(_ value: Any?) -> Double? {
        if let number = value as? NSNumber { return number.doubleValue }
        if let text = value as? String { return Double(text) }
        return nil
    }
}
