import Foundation

public struct ServerSentEventTextParser: Sendable {
    public init() {}

    public func parse(_ data: Data) throws -> String {
        guard let stream = String(data: data, encoding: .utf8) else {
            throw ModelProviderError.responseParsingFailed(body: "", reason: "SSE 数据不是 UTF-8")
        }

        var output = ""
        for event in stream.components(separatedBy: "\n\n") {
            for line in event.split(whereSeparator: \.isNewline) {
                guard line.hasPrefix("data:") else {
                    continue
                }
                let payload = line.dropFirst(5).trimmingCharacters(in: .whitespaces)
                guard payload != "[DONE]", let payloadData = payload.data(using: .utf8) else {
                    continue
                }
                output += textDelta(from: payloadData)
            }
        }
        return output
    }

    private func textDelta(from data: Data) -> String {
        guard let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return ""
        }

        if let delta = object["delta"] as? String {
            return delta
        }

        if let delta = object["delta"] as? [String: Any],
           let text = delta["text"] as? String {
            return text
        }

        if let choices = object["choices"] as? [[String: Any]],
           let first = choices.first,
           let delta = first["delta"] as? [String: Any],
           let content = delta["content"] as? String {
            return content
        }

        if let output = object["output"] as? [[String: Any]] {
            return output
                .flatMap { ($0["content"] as? [[String: Any]]) ?? [] }
                .compactMap { $0["text"] as? String }
                .joined()
        }

        return ""
    }
}
