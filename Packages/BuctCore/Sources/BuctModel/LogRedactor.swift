import Foundation

/// 日志脱敏工具：保留域名与状态码，自动掩码学号与会话凭据。
public enum LogRedactor {
    private static let studentIDRegex = try! NSRegularExpression(pattern: #"\b\d{8,12}\b"#)
    private static let secretParamRegex = try! NSRegularExpression(
        pattern: #"(?i)(password|SOURCEID_TGC|SESSION|webportal|wengine_vpn_ticket[a-z0-9_]*)=([^&\s;]+)"#
    )

    public static func redact(_ raw: String) -> String {
        var result = raw
        let secretRange = NSRange(result.startIndex..<result.endIndex, in: result)
        result = secretParamRegex.stringByReplacingMatches(
            in: result,
            range: secretRange,
            withTemplate: "$1=***"
        )
        let idRange = NSRange(result.startIndex..<result.endIndex, in: result)
        result = studentIDRegex.stringByReplacingMatches(
            in: result,
            range: idRange,
            withTemplate: "***"
        )
        return result
    }
}
