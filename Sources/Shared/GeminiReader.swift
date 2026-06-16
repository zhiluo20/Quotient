import Foundation

/// 读取 Gemini CLI 的本地登录态。
///
/// 说明：Gemini（个人 OAuth / Code Assist 免费层）不提供"剩余额度百分比"——
/// 本地不记录用量，官方也没有可提前查询余量的接口，配额数字只在超额 429 错误里才返回。
/// 因此这里只反映登录状态：已登录且持有可续期的凭据为绿灯，未登录为灰。
/// 纯本地读取，不发起网络请求，也不接触任何 token 明文以外的东西。
enum GeminiReader {
    static func read() -> ServiceData {
        let url = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".gemini/oauth_creds.json")
        guard let data = try? Data(contentsOf: url),
              let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        else {
            return .unavailable(messageKey: "gemini_not_logged_in")
        }
        let refresh = obj["refresh_token"] as? String
        let access = obj["access_token"] as? String
        guard (refresh?.isEmpty == false) || (access?.isEmpty == false) else {
            return .unavailable(messageKey: "gemini_not_logged_in")
        }
        // 持有 refresh_token → Gemini CLI 可自动续期，视为持续可用（绿）
        return .status(led: .green, textKey: "status_active", asOf: Date())
    }
}
