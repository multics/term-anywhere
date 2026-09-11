import Foundation
import CryptoKit

public enum AWSSigning {
    public static func sign(_ original: URLRequest, credentials: AWSCredentials, region: String, service: String, date: Date = Date()) -> URLRequest {
        var request = original
        let formatter = DateFormatter(); formatter.locale = Locale(identifier: "en_US_POSIX"); formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.dateFormat = "yyyyMMdd'T'HHmmss'Z'"
        let timestamp = formatter.string(from: date), day = String(timestamp.prefix(8))
        let url = request.url!, parts = URLComponents(url: url, resolvingAgainstBaseURL: false)!
        request.setValue(url.host!, forHTTPHeaderField: "Host")
        request.setValue(timestamp, forHTTPHeaderField: "X-Amz-Date")
        if let token = credentials.sessionToken, !token.isEmpty { request.setValue(token, forHTTPHeaderField: "X-Amz-Security-Token") }
        let headers = (request.allHTTPHeaderFields ?? [:]).map { ($0.key.lowercased(), $0.value.split(whereSeparator: { $0.isWhitespace }).joined(separator: " ")) }.sorted { $0.0 < $1.0 }
        let names = headers.map(\.0).joined(separator: ";")
        let canonicalHeaders = headers.map { "\($0.0):\($0.1)\n" }.joined()
        let queryPairs: [(String, String)] = (parts.queryItems ?? []).map { (encode($0.name), encode($0.value ?? "")) }
        let sortedPairs = queryPairs.sorted { a, b in a.0 == b.0 ? a.1 < b.1 : a.0 < b.0 }
        let query = sortedPairs.map { "\($0.0)=\($0.1)" }.joined(separator: "&")
        let path = url.path.isEmpty ? "/" : url.path.split(separator: "/", omittingEmptySubsequences: false).map { encode(String($0)) }.joined(separator: "/")
        let canonical = [request.httpMethod ?? "GET", path, query, canonicalHeaders, names, hash(request.httpBody ?? Data())].joined(separator: "\n")
        let scope = "\(day)/\(region)/\(service)/aws4_request"
        let stringToSign = "AWS4-HMAC-SHA256\n\(timestamp)\n\(scope)\n\(hash(Data(canonical.utf8)))"
        let dayKey = hmac(Data(("AWS4" + credentials.secretAccessKey).utf8), day)
        let signingKey = hmac(hmac(hmac(dayKey, region), service), "aws4_request")
        request.setValue("AWS4-HMAC-SHA256 Credential=\(credentials.accessKeyID)/\(scope), SignedHeaders=\(names), Signature=\(hex(hmac(signingKey, stringToSign)))", forHTTPHeaderField: "Authorization")
        return request
    }
    static func encode(_ s: String) -> String { s.addingPercentEncoding(withAllowedCharacters: CharacterSet(charactersIn: "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-_.~"))! }
    static func hmac(_ key: Data, _ text: String) -> Data { Data(HMAC<SHA256>.authenticationCode(for: Data(text.utf8), using: SymmetricKey(data: key))) }
    static func hash(_ data: Data) -> String { hex(Data(SHA256.hash(data: data))) }
    static func hex(_ data: Data) -> String { data.map { String(format: "%02x", $0) }.joined() }
}
