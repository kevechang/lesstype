public struct RecognitionPreviewBuffer: Sendable {
    public let limit: Int
    public private(set) var values: [String] = []

    public init(limit: Int = 20) {
        self.limit = max(1, limit)
    }

    public mutating func append(_ value: String) {
        values.append(value)
        if values.count > limit {
            values.removeFirst(values.count - limit)
        }
    }

    public mutating func removeAll() {
        values.removeAll()
    }
}
