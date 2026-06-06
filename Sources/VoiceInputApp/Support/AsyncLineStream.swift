import Foundation

public struct AsyncLineStream: AsyncSequence {
    public typealias Element = String

    private let lines: [String]

    public init(_ text: String) {
        self.lines = text.split(separator: "\n").map(String.init)
    }

    public func makeAsyncIterator() -> Iterator {
        Iterator(lines: lines)
    }

    public struct Iterator: AsyncIteratorProtocol {
        private let lines: [String]
        private var index: Int

        fileprivate init(lines: [String]) {
            self.lines = lines
            self.index = lines.startIndex
        }

        public mutating func next() async -> String? {
            if index >= lines.endIndex {
                return nil
            }
            let line = lines[index]
            index += 1
            return line
        }
    }
}
