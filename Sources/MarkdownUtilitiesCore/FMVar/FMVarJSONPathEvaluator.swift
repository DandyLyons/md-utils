import DynamicJSON
import Foundation

/// Portable fm-var adapter around DynamicJSON's RFC 9535 parser and evaluator.
///
/// This type deliberately does not implement JSONPath syntax or evaluation itself. DynamicJSON is
/// authoritative for query behavior; the adapter converts the portable query argument, retains
/// source-node associations, applies host-configurable outer limits, and maps dependency outcomes
/// into fm-var's structured result vocabulary.
public struct FMVarJSONPathEvaluator: Sendable {
  /// Resource policy applied to each query.
  public let limits: FMVarJSONPathLimits
  /// Function extensions made available to DynamicJSON.
  public let availableFunctions: Set<FMVarJSONPathFunction>

  /// Creates a portable JSONPath evaluator.
  public init(
    limits: FMVarJSONPathLimits = FMVarJSONPathLimits(),
    availableFunctions: Set<FMVarJSONPathFunction> = Set(FMVarJSONPathFunction.allCases)
  ) {
    self.limits = limits
    self.availableFunctions = availableFunctions
  }

  /// Parses and evaluates an authored query against a validated fm-var query argument.
  ///
  /// Selected locations are mapped back to the original ``FMVarQueryNode`` values, preserving
  /// source scalar spelling, result order, and duplicate node identities.
  public func evaluate(
    query: String,
    argument: FMVarQueryArgument
  ) -> FMVarJSONPathEvaluation {
    let fullRange = queryRange(query)
    let queryLength = clampedUInt(query.utf8.count)
    guard queryLength <= limits.maximumQueryLength else {
      return resourceFailure(
        reason: .queryLengthLimit,
        range: fullRange,
        message: "JSONPath query exceeds the configured UTF-8 length limit.",
        limit: limits.maximumQueryLength,
        observed: queryLength
      )
    }

    guard query.first == "$" else {
      return invalidFailure(
        reason: .invalidRoot,
        range: rootRange(query),
        message: "An fm-var JSONPath query must begin with '$'."
      )
    }

    let path: JSONPath
    do {
      path = try JSONPath(query: query, strict: true)
    } catch {
      return invalidFailure(
        reason: .invalidSyntax,
        range: fullRange,
        message: "DynamicJSON rejected the JSONPath query: \(error)"
      )
    }

    let queryDepth = clampedUInt(path.segments.count)
    guard queryDepth <= limits.maximumNestingDepth else {
      return resourceFailure(
        reason: .nestingLimit,
        range: fullRange,
        message: "JSONPath query exceeds the configured nesting limit.",
        limit: limits.maximumNestingDepth,
        observed: queryDepth
      )
    }

    let environment = makeEnvironment()
    if let unavailableFunction = functionNames(in: path).first(where: { name in
      environment.functions[name] == nil
    }) {
      return unsupportedFunctionFailure(name: unavailableFunction, range: fullRange)
    }

    let conversion: DynamicJSONConversion
    do {
      conversion = try convert(
        argument.root,
        at: .root,
        depth: 0,
        maximumDepth: limits.maximumNestingDepth
      )
    } catch {
      switch error {
      case .nestingLimit(let observed):
        return resourceFailure(
          reason: .nestingLimit,
          range: fullRange,
          message: "JSONPath query argument exceeds the configured nesting limit.",
          limit: limits.maximumNestingDepth,
          observed: observed
        )
      }
    }

    let selectorCount = path.segments.reduce(UInt.zero) { partial, segment in
      saturatingAdd(partial, max(1, clampedUInt(segment.selectors.count)))
    }
    let executionWork = saturatingMultiply(
      conversion.nodeCount,
      saturatingAdd(1, saturatingAdd(queryDepth, selectorCount))
    )
    guard executionWork <= limits.maximumExecutionWork else {
      return resourceFailure(
        reason: .executionWorkLimit,
        range: fullRange,
        message: "JSONPath evaluation exceeds the configured execution-work limit.",
        limit: limits.maximumExecutionWork,
        observed: executionWork
      )
    }

    let regexCalls = regularExpressionCallCount(in: path)
    let maximumPatternLength = max(1, max(queryLength, conversion.maximumStringLength))
    let regularExpressionWork = saturatingMultiply(
      regexCalls,
      saturatingMultiply(
        executionWork,
        saturatingMultiply(max(1, conversion.maximumStringLength), maximumPatternLength)
      )
    )
    guard regularExpressionWork <= limits.maximumRegularExpressionWork else {
      return resourceFailure(
        reason: .regularExpressionWorkLimit,
        range: fullRange,
        message: "JSONPath regular-expression evaluation exceeds its configured work limit.",
        limit: limits.maximumRegularExpressionWork,
        observed: regularExpressionWork
      )
    }

    let locatedResults: [LocatedJSON]
    do {
      locatedResults = try JSONPathEvaluator(
        value: conversion.value,
        env: environment,
        strict: true
      ).query(path)
    } catch let error as JSONPathEvaluator.Error {
      if case .unknownFunction(let functionName) = error {
        return unsupportedFunctionFailure(name: functionName, range: fullRange)
      }
      return invalidFailure(
        reason: .invalidSemantics,
        range: fullRange,
        message: "DynamicJSON rejected the JSONPath query during evaluation: \(error)"
      )
    } catch {
      return invalidFailure(
        reason: .invalidSemantics,
        range: fullRange,
        message: "DynamicJSON rejected the JSONPath query during evaluation: \(error)"
      )
    }

    let resultCount = clampedUInt(locatedResults.count)
    guard resultCount <= limits.maximumResultCount else {
      return resourceFailure(
        reason: .resultCountLimit,
        range: fullRange,
        message: "JSONPath nodelist exceeds the configured result-count limit.",
        limit: limits.maximumResultCount,
        observed: resultCount
      )
    }

    var nodes: [FMVarQueryNode] = []
    nodes.reserveCapacity(locatedResults.count)
    for result in locatedResults {
      guard let node = conversion.nodesByLocation[result.location] else {
        return invalidFailure(
          reason: .invalidSemantics,
          range: fullRange,
          message: "DynamicJSON returned a location outside the converted query argument."
        )
      }
      nodes.append(node)
    }
    return FMVarJSONPathEvaluation(status: .selected, nodelist: FMVarNodelist(nodes: nodes))
  }

  private func makeEnvironment() -> JSONPathEnvironment {
    let environment = JSONPathEnvironment()
    let allowedNames = Set(availableFunctions.map(\.rawValue))
    environment.functions = environment.functions.filter { allowedNames.contains($0.key) }
    return environment
  }

  private func invalidFailure(
    reason: FMVarJSONPathFailureReason,
    range: FMVarSourceRange,
    message: String
  ) -> FMVarJSONPathEvaluation {
    FMVarJSONPathEvaluation(
      status: .invalidQuery,
      failure: FMVarJSONPathFailure(reason: reason, queryRange: range, message: message)
    )
  }

  private func unsupportedFunctionFailure(
    name: String,
    range: FMVarSourceRange
  ) -> FMVarJSONPathEvaluation {
    FMVarJSONPathEvaluation(
      status: .unsupportedCapability,
      failure: FMVarJSONPathFailure(
        reason: .unsupportedFunction,
        queryRange: range,
        message: "JSONPath function '\(name)' is not available.",
        functionName: name
      )
    )
  }

  private func resourceFailure(
    reason: FMVarJSONPathFailureReason,
    range: FMVarSourceRange,
    message: String,
    limit: UInt,
    observed: UInt
  ) -> FMVarJSONPathEvaluation {
    FMVarJSONPathEvaluation(
      status: .resourceLimited,
      failure: FMVarJSONPathFailure(
        reason: reason,
        queryRange: range,
        message: message,
        limit: limit,
        observed: observed
      )
    )
  }
}

private struct DynamicJSONConversion {
  let value: JSON
  let nodesByLocation: [JSONLocation: FMVarQueryNode]
  let nodeCount: UInt
  let maximumStringLength: UInt
}

private enum FMVarJSONPathAdapterError: Error {
  case nestingLimit(observed: UInt)
}

private func convert(
  _ node: FMVarQueryNode,
  at location: JSONLocation,
  depth: UInt,
  maximumDepth: UInt
) throws(FMVarJSONPathAdapterError) -> DynamicJSONConversion {
  guard depth <= maximumDepth else {
    throw FMVarJSONPathAdapterError.nestingLimit(observed: depth)
  }

  var nodesByLocation = [location: node]
  var nodeCount: UInt = 1
  var maximumStringLength: UInt = 0
  let value: JSON
  switch node.value {
  case .null:
    value = .null
  case .boolean(let boolean):
    value = .boolean(boolean)
  case .integer(let integer):
    value = .integer(integer)
  case .number(let number):
    value = .float(number)
  case .string(let string):
    value = .string(string)
    maximumStringLength = clampedUInt(string.utf16.count)
  case .array(let nodes):
    var values: [JSON] = []
    values.reserveCapacity(nodes.count)
    for (index, child) in nodes.enumerated() {
      let childConversion = try convert(
        child,
        at: location.select(index: index),
        depth: saturatingAdd(depth, 1),
        maximumDepth: maximumDepth
      )
      values.append(childConversion.value)
      nodesByLocation.merge(childConversion.nodesByLocation) { _, replacement in replacement }
      nodeCount = saturatingAdd(nodeCount, childConversion.nodeCount)
      maximumStringLength = max(maximumStringLength, childConversion.maximumStringLength)
    }
    value = .array(values)
  case .object(let members):
    var values: [String: JSON] = [:]
    values.reserveCapacity(members.count)
    for member in members {
      let childConversion = try convert(
        member.node,
        at: location.select(member: member.name),
        depth: saturatingAdd(depth, 1),
        maximumDepth: maximumDepth
      )
      values[member.name] = childConversion.value
      nodesByLocation.merge(childConversion.nodesByLocation) { _, replacement in replacement }
      nodeCount = saturatingAdd(nodeCount, childConversion.nodeCount)
      maximumStringLength = max(maximumStringLength, childConversion.maximumStringLength)
    }
    value = .object(values)
  }
  return DynamicJSONConversion(
    value: value,
    nodesByLocation: nodesByLocation,
    nodeCount: nodeCount,
    maximumStringLength: maximumStringLength
  )
}

private func regularExpressionCallCount(in path: JSONPath) -> UInt {
  path.segments.reduce(UInt.zero) { count, segment in
    segment.selectors.reduce(count) { selectorCount, selector in
      guard case .filter(let expression) = selector else { return selectorCount }
      return saturatingAdd(selectorCount, regularExpressionCallCount(in: expression))
    }
  }
}

private func functionNames(in path: JSONPath) -> [String] {
  path.segments.flatMap { segment in
    segment.selectors.flatMap { selector -> [String] in
      guard case .filter(let expression) = selector else { return [] }
      return functionNames(in: expression)
    }
  }
}

private func functionNames(in expression: JSONPath.Expression) -> [String] {
  switch expression {
  case .call(let name, let arguments):
    return [name] + arguments.flatMap(functionNames(in:))
  case .prefix(_, let argument):
    return functionNames(in: argument)
  case .operation(let lhs, _, let rhs):
    return functionNames(in: lhs) + functionNames(in: rhs)
  case .query(let nestedPath), .singularQuery(let nestedPath):
    return functionNames(in: nestedPath)
  case .null, .true, .false, .integer, .float, .string, .variable:
    return []
  }
}

private func regularExpressionCallCount(in expression: JSONPath.Expression) -> UInt {
  switch expression {
  case .call(let name, let arguments):
    let ownCount: UInt = name == FMVarJSONPathFunction.match.rawValue
      || name == FMVarJSONPathFunction.search.rawValue ? 1 : 0
    return arguments.reduce(ownCount) { count, argument in
      saturatingAdd(count, regularExpressionCallCount(in: argument))
    }
  case .prefix(_, let argument):
    return regularExpressionCallCount(in: argument)
  case .operation(let lhs, _, let rhs):
    return saturatingAdd(
      regularExpressionCallCount(in: lhs),
      regularExpressionCallCount(in: rhs)
    )
  case .query(let nestedPath), .singularQuery(let nestedPath):
    return regularExpressionCallCount(in: nestedPath)
  case .null, .true, .false, .integer, .float, .string, .variable:
    return 0
  }
}

private func queryRange(_ query: String) -> FMVarSourceRange {
  let sourceMap = FMVarSourceMap(source: query)
  do {
    return try sourceMap.range(fromUTF8Offset: 0, toUTF8Offset: sourceMap.utf8Count)
  } catch {
    preconditionFailure("FMVarSourceMap rejected its own complete source range: \(error)")
  }
}

private func rootRange(_ query: String) -> FMVarSourceRange {
  let sourceMap = FMVarSourceMap(source: query)
  let end = min(sourceMap.utf8Count, query.first.map { String($0).utf8.count } ?? 0)
  do {
    return try sourceMap.range(fromUTF8Offset: 0, toUTF8Offset: end)
  } catch {
    preconditionFailure("FMVarSourceMap rejected the query root range: \(error)")
  }
}

private func clampedUInt(_ value: Int) -> UInt {
  UInt(clamping: value)
}

private func saturatingAdd(_ lhs: UInt, _ rhs: UInt) -> UInt {
  let (result, overflow) = lhs.addingReportingOverflow(rhs)
  return overflow ? UInt.max : result
}

private func saturatingMultiply(_ lhs: UInt, _ rhs: UInt) -> UInt {
  let (result, overflow) = lhs.multipliedReportingOverflow(by: rhs)
  return overflow ? UInt.max : result
}
