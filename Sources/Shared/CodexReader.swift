import Foundation

/// 从 ~/.codex/sessions 的 rollout-*.jsonl 中读取最近一条 rate_limits 快照。
/// 纯本地解析，不发起任何网络请求，也不接触 auth token。
enum CodexReader {
    private static let scanTailByteLimit: UInt64 = 2 * 1024 * 1024

    static func read() -> ServiceData {
        let home = FileManager.default.homeDirectoryForCurrentUser
        let roots = [
            home.appendingPathComponent(".codex/sessions"),
            home.appendingPathComponent(".codex/archived_sessions"),
        ]

        var candidates: [(URL, Date)] = []
        for root in roots {
            guard let enumerator = FileManager.default.enumerator(
                at: root,
                includingPropertiesForKeys: [.contentModificationDateKey],
                options: [.skipsHiddenFiles]
            ) else { continue }

            for case let url as URL in enumerator {
                guard url.lastPathComponent.hasPrefix("rollout-"),
                      url.pathExtension == "jsonl",
                      let mtime = try? url.resourceValues(forKeys: [.contentModificationDateKey])
                          .contentModificationDate
                else { continue }
                candidates.append((url, mtime))
            }
        }

        guard !candidates.isEmpty else {
            return .unavailable(messageKey: "codex_no_data")
        }
        candidates.sort { $0.1 > $1.1 }

        for (url, _) in candidates {
            guard let parsed = scan(url) else { continue }
            return parsed.data
        }
        return .unavailable(messageKey: "codex_no_data")
    }

    private struct ParsedSnapshot {
        let data: ServiceData
        let asOf: Date?
    }

    private static func scan(_ url: URL) -> ParsedSnapshot? {
        guard let text = tailText(url) else { return nil }
        for line in text.split(separator: "\n").reversed() {
            guard line.contains("\"rate_limits\""),
                  let lineData = line.data(using: .utf8),
                  let obj = try? JSONSerialization.jsonObject(with: lineData),
                  let rl = findDict(obj, key: "rate_limits")
            else { continue }

            var windows: [WindowQuota] = []
            for slot in ["primary", "secondary"] {
                guard let w = rl[slot] as? [String: Any],
                      let used = usedPercent(w)
                else { continue }
                windows.append(WindowQuota(
                    id: "codex_\(slot)",
                    windowMinutes: intValue(w["window_minutes"]),
                    labelKey: nil,
                    usedPercent: used,
                    resetsAt: anyDate(w["resets_at"] ?? w["reset_at"])
                ))
            }
            guard !windows.isEmpty else { continue }

            var asOf: Date?
            if let top = obj as? [String: Any], let ts = top["timestamp"] as? String {
                asOf = parseISO(ts)
            }
            return ParsedSnapshot(
                data: .ready(plan: rl["plan_type"] as? String, windows: windows, asOf: asOf),
                asOf: asOf
            )
        }
        return nil
    }

    private static func tailText(_ url: URL) -> String? {
        guard let handle = try? FileHandle(forReadingFrom: url),
              let size = try? handle.seekToEnd()
        else { return nil }
        let offset = size > scanTailByteLimit ? size - scanTailByteLimit : 0
        guard (try? handle.seek(toOffset: offset)) != nil,
              let data = try? handle.readToEnd()
        else {
            try? handle.close()
            return nil
        }
        try? handle.close()
        return String(decoding: data ?? Data(), as: UTF8.self)
    }

    // MARK: - JSON helpers

    static func findDict(_ any: Any, key: String) -> [String: Any]? {
        if let dict = any as? [String: Any] {
            if let v = dict[key] as? [String: Any] { return v }
            for v in dict.values {
                if let r = findDict(v, key: key) { return r }
            }
        } else if let arr = any as? [Any] {
            for v in arr {
                if let r = findDict(v, key: key) { return r }
            }
        }
        return nil
    }

    static func doubleValue(_ any: Any?) -> Double? {
        (any as? NSNumber)?.doubleValue
    }

    static func intValue(_ any: Any?) -> Int? {
        (any as? NSNumber)?.intValue
    }

    static func usedPercent(_ dict: [String: Any]) -> Double? {
        if let used = doubleValue(dict["used_percent"] ?? dict["usedPercentage"]) {
            return max(0, min(100, used))
        }
        if let remaining = doubleValue(dict["remaining_percent"] ?? dict["remainingPercentage"]) {
            return max(0, min(100, 100 - remaining))
        }
        if let remaining = doubleValue(dict["remaining_fraction"] ?? dict["remainingFraction"]) {
            return max(0, min(100, 100 - remaining * 100))
        }
        return nil
    }

    static func epochDate(_ any: Any?) -> Date? {
        guard let n = (any as? NSNumber)?.doubleValue else { return nil }
        return Date(timeIntervalSince1970: n > 1e12 ? n / 1000 : n)
    }

    static func anyDate(_ any: Any?) -> Date? {
        if let s = any as? String { return parseISO(s) }
        return epochDate(any)
    }

    static func parseISO(_ s: String) -> Date? {
        let fractional = ISO8601DateFormatter()
        fractional.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let d = fractional.date(from: s) { return d }
        let plain = ISO8601DateFormatter()
        return plain.date(from: s)
    }
}
