import Foundation

/// Bounded iterative graph algorithms avoid recursion depth and exponential cycle enumeration.
package struct MarkdownPolicyGraph {
  struct Edge: Hashable {
    var source: String
    var target: String
    var relation: MarkdownPolicyRelation
    var occurrence: Int
  }
  struct Budget {
    var remaining: Int
    mutating func spend() throws {
      try Task.checkCancellation()
      guard remaining > 0 else { throw Exhausted() }
      remaining -= 1
    }
  }
  struct Exhausted: Error {}
  var edges: [Edge]

  /// Appends witnesses as they are established, so later exhaustion cannot erase a violation.
  func cycles(mode: MarkdownCycleWitnessMode, budget: inout Budget, witnesses: inout [[Int]]) throws {
    var outgoing: [String: [Edge]] = [:]
    var incoming: [String: [String]] = [:]
    var vertices: Set<String> = []
    for edge in edges {
      try budget.spend()
      outgoing[edge.source, default: []].append(edge)
      incoming[edge.target, default: []].append(edge.source)
      vertices.formUnion([edge.source, edge.target])
    }
    if mode == .first {
      if let cycle = try witness(vertices: vertices, outgoing: outgoing, budget: &budget) { witnesses.append(cycle) }
      return
    }
    // Kosaraju finishing order, using explicit frames rather than the Swift call stack.
    var visited: Set<String> = []
    var finished: [String] = []
    for root in vertices.sorted() where visited.insert(root).inserted {
      var stack: [(String, Int)] = [(root, 0)]
      while let (node, offset) = stack.last {
        try budget.spend()
        let adjacent = outgoing[node] ?? []
        if offset < adjacent.count {
          stack[stack.count - 1].1 += 1
          let target = adjacent[offset].target
          if visited.insert(target).inserted { stack.append((target, 0)) }
        } else {
          finished.append(node)
          stack.removeLast()
        }
      }
    }
    visited = []
    for root in finished.reversed() where visited.insert(root).inserted {
      var component: Set<String> = [root]
      var queue = [root]
      while let node = queue.popLast() {
        try budget.spend()
        for source in incoming[node] ?? [] {
          try budget.spend()
          if visited.insert(source).inserted { component.insert(source); queue.append(source) }
        }
      }
      if component.count > 1 || outgoing[root]?.contains(where: { $0.target == root }) == true,
        let cycle = try witness(vertices: component, outgoing: outgoing, budget: &budget) {
        witnesses.append(cycle)
      }
    }
  }

  private func witness(vertices: Set<String>, outgoing: [String: [Edge]], budget: inout Budget) throws -> [Int]? {
    var done: Set<String> = []
    var active: [String: Int] = [:]
    for root in vertices.sorted() where !done.contains(root) {
      var stack: [(String, Int)] = [(root, 0)]
      var path: [Int] = []
      active[root] = 0
      while let (node, offset) = stack.last {
        try budget.spend()
        let adjacent = outgoing[node] ?? []
        if offset == adjacent.count {
          done.insert(node)
          active.removeValue(forKey: node)
          stack.removeLast()
          if !path.isEmpty { path.removeLast() }
          continue
        }
        stack[stack.count - 1].1 += 1
        let edge = adjacent[offset]
        guard vertices.contains(edge.target) else { continue }
        if let start = active[edge.target] { return Array(path.dropFirst(start)) + [edge.occurrence] }
        if !done.contains(edge.target) {
          active[edge.target] = stack.count
          path.append(edge.occurrence)
          stack.append((edge.target, 0))
        }
      }
    }
    return nil
  }
}
