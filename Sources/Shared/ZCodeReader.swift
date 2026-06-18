import Foundation

/// 从 ZCode 本地日志中读取最近一次 billing/balance 用量快照。
/// 纯本地解析，不读取 credentials.json，也不主动请求 ZCode API。
enum ZCodeReader {
    static func read() -> ServiceData {
        let home = FileManager.default.homeDirectoryForCurrentUser
        let roots = [
            home.appendingPathComponent(".zcode/v2/logs"),
            home.appendingPathComponent(".zcode/cli/log"),
        ]

        var candidates: [(URL, Date)] = []
        for root in roots {
            guard let urls = try? FileManager.default.contentsOfDirectory(
                at: root, includingPropertiesForKeys: [.contentModificationDateKey],
                options: [.skipsHiddenFiles]
            ) else { continue }

            for url in urls where url.pathExtension == "log" || url.pathExtension == "jsonl" {
                guard let mtime = try? url.resourceValues(forKeys: [.contentModificationDateKey])
                    .contentModificationDate
                else { continue }
                candidates.append((url, mtime))
            }
        }

        candidates.sort { $0.1 > $1.1 }
        for (url, _) in candidates {
            if let data = scan(url) { return data }
        }
        return .unavailable(messageKey: "zcode_no_data")
    }

    private static func scan(_ url: URL) -> ServiceData? {
        guard let text = try? String(contentsOf: url, encoding: .utf8) else { return nil }
        for line in text.split(separator: "\n").reversed() {
            guard line.contains("billing/balance"),
                  let data = parseBalanceLine(line)
            else { continue }
            return data
        }
        return nil
    }

    private static func parseBalanceLine(_ line: Substring) -> ServiceData? {
        guard let obj = jsonObject(from: line) else { return nil }
        let payload = obj["payload"] as? [String: Any]
        let data = payload?["data"] as? [String: Any]
        let balances = (data?["balances"] as? [[String: Any]])
            ?? (obj["balances"] as? [[String: Any]])
            ?? []

        let windows = balances.compactMap(parseBalance)
        guard !windows.isEmpty else { return nil }

        let asOf = parseLogDate(line)
            ?? CodexReader.anyDate(data?["server_time"] ?? obj["server_time"])
            ?? Date()
        return .ready(plan: planLabel(from: balances), windows: windows, asOf: asOf)
    }

    private static func parseBalance(_ balance: [String: Any]) -> WindowQuota? {
        guard let total = CodexReader.doubleValue(balance["total_units"]),
              total > 0
        else { return nil }

        let used = CodexReader.doubleValue(balance["used_units"])
            ?? (total - (CodexReader.doubleValue(balance["remaining_units"])
                         ?? CodexReader.doubleValue(balance["available_units"]) ?? total))
        let label = balance["show_name"] as? String
            ?? (balance["capabilities"] as? [String])?.first?.replacingOccurrences(of: "model:", with: "")
            ?? "ZCode"
        let rawID = (balance["entitlement_id"] as? String) ?? label

        return WindowQuota(
            id: "zcode_\(stableID(rawID))",
            windowMinutes: nil,
            labelKey: nil,
            usedPercent: max(0, min(100, used / total * 100)),
            resetsAt: CodexReader.anyDate(balance["expires_at"] ?? balance["period_end"]),
            customLabel: label
        )
    }

    private static func jsonObject(from line: Substring) -> [String: Any]? {
        guard let start = line.firstIndex(of: "{") else { return nil }
        let json = String(line[start...])
        guard let data = json.data(using: .utf8),
              let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        else { return nil }
        return obj
    }

    private static func parseLogDate(_ line: Substring) -> Date? {
        guard line.first == "[",
              let end = line.firstIndex(of: "]")
        else { return nil }
        let raw = String(line[line.index(after: line.startIndex)..<end])
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = .current
        formatter.dateFormat = "yyyy-MM-dd HH:mm:ss.SSS"
        return formatter.date(from: raw)
    }

    private static func planLabel(from balances: [[String: Any]]) -> String? {
        guard let planID = balances.compactMap({ $0["plan_id"] as? String }).first else {
            return nil
        }
        return planID.localizedCaseInsensitiveContains("start") ? "Start" : nil
    }

    private static func stableID(_ raw: String) -> String {
        raw.lowercased().map { char in
            char.isLetter || char.isNumber ? char : "_"
        }.reduce(into: "") { $0.append($1) }
    }
}
