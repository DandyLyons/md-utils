import Foundation
import MarkdownUtilitiesCore
import MarkdownUtilitiesIndex

struct IndexQueryJSONValue: Encodable {
    var value: IndexQueryValue

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        switch value {
        case .null: try container.encodeNil()
        case .integer(let value): try container.encode(value)
        case .real(let value): try container.encode(value)
        case .text(let value): try container.encode(value)
        case .blob(let value): try container.encode(["base64": value.base64EncodedString()])
        }
    }
}
