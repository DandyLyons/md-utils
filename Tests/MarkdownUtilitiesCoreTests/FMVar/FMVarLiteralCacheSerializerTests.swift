import Foundation
#if canImport(FoundationXML)
import FoundationXML
#endif
import MarkdownUtilitiesCore
import Testing

@Suite("fm-var literal cache serialization")
struct FMVarLiteralCacheSerializerTests {
  @Test
  func `escapes delimiters without interpreting entities or markup`() throws {
    let input = "&<>\\`*_~[]|\"' &lt; </fm-var>"
    #expect(try FMVarLiteralCacheSerializer().serialize(input) ==
      "&amp;&lt;&gt;&#92;&#96;&#42;&#95;&#126;&#91;&#93;&#124;\"' &amp;lt; &lt;/fm-var&gt;")
  }

  @Test
  func `rejects XML forbidden scalars and embedded line endings`() throws {
    for code in Array(0...8) + Array(10...31) + [0xFFFE, 0xFFFF] {
      let scalar = try #require(Unicode.Scalar(code))
      #expect(throws: FMVarLiteralCacheError.unsupportedCharacter) {
        try FMVarLiteralCacheSerializer().serialize("before" + String(scalar) + "after")
      }
    }
    for code in [9, 32, 0xD7FF, 0xE000, 0xFFFD, 0x10000, 0x10FFFF] {
      let text = String(try #require(Unicode.Scalar(code)))
      #expect(try FMVarLiteralCacheSerializer().serialize(text).utf8.elementsEqual(text.utf8))
    }
  }

  @Test
  func `generated supported text remains literal and round trips without byte normalization`() throws {
    // Fixed deterministic corpus, including punctuation pairs that can combine into markup.
    var state: UInt64 = 120
    let alphabet = Array("&<>\\`*_~[]|\"' ;#=/!()-:+ abc\tCafé😀e\u{301}".unicodeScalars)
    for _ in 0..<300 {
      var input = ""
      for _ in 0..<40 {
        state = state &* 6364136223846793005 &+ 1442695040888963407
        input.unicodeScalars.append(alphabet[Int(state % UInt64(alphabet.count))])
      }
      let encoded = try FMVarLiteralCacheSerializer().serialize(input)
      let snapshot = try FMVarParser().parse("Text <fm-var query=\"$.v\">\(encoded)</fm-var> end")
      #expect(snapshot.isValid)
      #expect(snapshot.elements.count == 1)
      #expect(encoded.contains("<") == false)
      #expect(encoded.contains(">") == false)
      // XMLParser independently verifies entity decoding and that no child markup was injected.
      let delegate = LiteralTextDelegate()
      let parser = XMLParser(data: Data("<root>\(encoded)</root>".utf8))
      parser.delegate = delegate
      #expect(parser.parse())
      #expect(delegate.elements == ["root"])
      #expect(delegate.text.utf8.elementsEqual(input.utf8))
    }
  }
}

private final class LiteralTextDelegate: NSObject, XMLParserDelegate {
  var elements: [String] = []
  var text = ""
  func parser(_ parser: XMLParser, didStartElement elementName: String,
    namespaceURI: String?, qualifiedName qName: String?, attributes attributeDict: [String: String]) {
    elements.append(elementName)
  }
  func parser(_ parser: XMLParser, foundCharacters string: String) {
    text += string
  }
}
