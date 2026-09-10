import Foundation
import TableProPluginKit
import Testing

@Suite("Spanner type mapper")
struct SpannerTypeMapperTests {
    @Test("Scalar rows become text and bytes")
    func flattenScalarRows() {
        let fields = [
            SpannerField(name: "id", type: SpannerType(code: "INT64", arrayElementType: nil, structType: nil, typeAnnotation: nil)),
            SpannerField(name: "flag", type: SpannerType(code: "BOOL", arrayElementType: nil, structType: nil, typeAnnotation: nil)),
            SpannerField(name: "blob", type: SpannerType(code: "BYTES", arrayElementType: nil, structType: nil, typeAnnotation: nil)),
            SpannerField(name: "empty", type: SpannerType(code: "STRING", arrayElementType: nil, structType: nil, typeAnnotation: nil))
        ]
        let payload = Data("hi".utf8).base64EncodedString()
        let rows: [[SpannerJSONValue]] = [[
            .string("12"),
            .bool(true),
            .string(payload),
            .null
        ]]
        let cells = SpannerTypeMapper.flattenRows(rows, fields: fields)
        #expect(cells.count == 1)
        #expect(cells[0][0] == .text("12"))
        #expect(cells[0][1] == .text("true"))
        #expect(cells[0][2] == .bytes(Data("hi".utf8)))
        #expect(cells[0][3] == .null)
    }

    @Test("ARRAY and STRUCT type names include members")
    func typeDisplayNames() {
        let arrayType = SpannerType(
            code: "ARRAY",
            arrayElementType: SpannerType(code: "STRING", arrayElementType: nil, structType: nil, typeAnnotation: nil),
            structType: nil,
            typeAnnotation: nil
        )
        #expect(arrayType.displayName() == "ARRAY<STRING>")

        let structType = SpannerType(
            code: "STRUCT",
            arrayElementType: nil,
            structType: SpannerStructType(fields: [
                SpannerField(
                    name: "n",
                    type: SpannerType(code: "INT64", arrayElementType: nil, structType: nil, typeAnnotation: nil)
                )
            ]),
            typeAnnotation: nil
        )
        #expect(structType.displayName() == "STRUCT<n INT64>")
    }
}
