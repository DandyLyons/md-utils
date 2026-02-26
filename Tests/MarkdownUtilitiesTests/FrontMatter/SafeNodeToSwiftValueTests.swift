//
//  SafeNodeToSwiftValueTests.swift
//  MarkdownUtilitiesTests
//

import Testing
import Yams
@testable import MarkdownUtilities

@Suite("YAMLConversion.safeNodeToSwiftValue")
struct SafeNodeToSwiftValueTests {

  @Test
  func `valid all-string-key mapping returns String keyed dictionary`() throws {
    let node = Yams.Node.mapping(.init([
      (.scalar(.init("title")), .scalar(.init("Hello"))),
      (.scalar(.init("draft")), .scalar(.init("true"))),
    ]))

    let result = try YAMLConversion.safeNodeToSwiftValue(node)

    let dict = try #require(result as? [String: Any])
    #expect(dict["title"] as? String == "Hello")
    #expect(dict["draft"] as? Bool == true)
  }

  @Test
  func `integer-tagged scalar key is represented as string without error`() throws {
    // Scalar keys with non-string tags (e.g. !!int 123) are representable as strings
    // and do NOT cause a crash or throw — they're stringified to "123".
    let intKeyNode = Yams.Node.scalar(.init("123", Tag(.int)))
    let node = Yams.Node.mapping(.init([
      (intKeyNode, .scalar(.init("value"))),
    ]))

    let result = try YAMLConversion.safeNodeToSwiftValue(node)
    let dict = try #require(result as? [String: Any])
    #expect(dict["123"] != nil)
  }

  @Test
  func `mapping used as key throws nonStringKey`() throws {
    // A YAML complex key whose *key node* is itself a mapping — this is what
    // causes the force-unwrap crash in `Yams.Constructor.any()`.
    let keyMapping = Yams.Node.mapping(.init([
      (.scalar(.init("a")), .scalar(.init("b"))),
    ]))
    let node = Yams.Node.mapping(.init([
      (keyMapping, .scalar(.init("value"))),
    ]))

    #expect(throws: YAMLConversionError.nonStringKey("")) {
      _ = try YAMLConversion.safeNodeToSwiftValue(node)
    }
  }

  @Test
  func `sequence used as key throws nonStringKey`() throws {
    // A YAML complex key whose *key node* is a sequence.
    let keySequence = Yams.Node.sequence(.init([
      .scalar(.init("1")),
      .scalar(.init("2")),
    ]))
    let node = Yams.Node.mapping(.init([
      (keySequence, .scalar(.init("value"))),
    ]))

    #expect(throws: YAMLConversionError.nonStringKey("")) {
      _ = try YAMLConversion.safeNodeToSwiftValue(node)
    }
  }

  @Test
  func `nested mapping with mapping key throws nonStringKey`() throws {
    let keyMapping = Yams.Node.mapping(.init([
      (.scalar(.init("x")), .scalar(.init("y"))),
    ]))
    let innerMapping = Yams.Node.mapping(.init([
      (keyMapping, .scalar(.init("nested value"))),
    ]))
    let node = Yams.Node.mapping(.init([
      (.scalar(.init("outer")), innerMapping),
    ]))

    #expect(throws: YAMLConversionError.nonStringKey("")) {
      _ = try YAMLConversion.safeNodeToSwiftValue(node)
    }
  }

  @Test
  func `sequence containing mapping with complex key throws nonStringKey`() throws {
    let keySequence = Yams.Node.sequence(.init([.scalar(.init("k"))]))
    let badMapping = Yams.Node.mapping(.init([
      (keySequence, .scalar(.init("bad"))),
    ]))
    let node = Yams.Node.sequence(.init([badMapping]))

    #expect(throws: YAMLConversionError.nonStringKey("")) {
      _ = try YAMLConversion.safeNodeToSwiftValue(node)
    }
  }

  @Test
  func `scalar node returns native Swift value`() throws {
    let node = Yams.Node.scalar(.init("hello"))
    let result = try YAMLConversion.safeNodeToSwiftValue(node)
    #expect(result as? String == "hello")
  }

  @Test
  func `sequence of scalars returns array`() throws {
    let node = Yams.Node.sequence(.init([
      .scalar(.init("a")),
      .scalar(.init("b")),
    ]))
    let result = try YAMLConversion.safeNodeToSwiftValue(node)
    let array = try #require(result as? [Any])
    #expect(array.count == 2)
  }
}
