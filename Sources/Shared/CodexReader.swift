import Foundation

/// 从 ~/.codex/sessions 的 rollout-*.jsonl 中读取最近一条 rate_limits 快照。
/// 纯本地解析，不发起任何网络请求，也不接触 auth token。
enum CodexReader {
    static func read() -> ServiceData {
        let sessions = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".codex/sessions")
        guard let enumerator = FileManager.default.enumerator(
            at: sessions,
            includingPropertiesForKeys: [.contentModificationDateKey],
            options: [.skipsHiddenFiles]
        ) else {
            return .unavailable(messageKey: "codex_no_data")
        }

        var candidates: [(URL, Date)] = []
        for case let url as URL in enumerator {
            guard url.lastPathComponent.hasPrefix("rollout-"),
                  url.pathExtension == "jsonl",
                  let mtime = try? url.resourceValues(forKeys: [.contentModificationDateKey])
                      .contentModificationDate
            else { continue }
            candidates.append((url, mtime))
        }
        candidates.sort { $0.1 > $1.1 }

        for (url, _) in candidates.prefix(8) {
            if let data = scan(url) { return data }
        }
        return .unavailable(messageKey: "codex_no_data")
    }

    private static func scan(_ url: URL) -> ServiceData? {
        guard let text = try? String(contentsOf: url, encoding: .utf8) else { return nil }
        for line in text.split(separator: "\n").reversed() {
            guard line.contains("\"rate_limits\""),
                  let lineData = line.data(using: .utf8),
                  let obj = try? JSONSerialization.jsonObject(with: lineData),
                  let rl = findDict(obj, key: "rate_limits")
            else { continue }

            var windows: [WindowQuota] = []
            for slot in ["primary", "secondary"] {
                guard let w = rl[slot] as? [String: Any],
                      let used = doubleValue(w["used_percent"])
                else { continue }
                windows.append(WindowQuota(
                    id: "codex_\(slot)",
                    windowMinutes: (w["window_minutes"] as? NSNumber)?.intValue,
                    labelKey: nil,
                    usedPercent: used,
                    resetsAt: epochDate(w["resets_at"])
                ))
            }
            guard !windows.isEmpty else { continue }

            var asOf: Date?
            if let top = obj as? [String: Any], let ts = top["timestamp"] as? String {
                asOf = parseISO(ts)
            }
            return .ready(plan: rl["plan_type"] as? String, windows: windows, asOf: asOf)
        }
        return nil
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

    static func epochDate(_ any: Any?) -> Date? {
        guard let n = (any as? NSNumber)?.doubleValue else { return nil }
        return Date(timeIntervalSince1970: n)
    }

    static func parseISO(_ s: String) -> Date? {
        let fractional = ISO8601DateFormatter()
        fractional.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let d = fractional.date(from: s) { return d }
        let plain = ISO8601DateFormatter()
        return plain.date(from: s)
    }
}
