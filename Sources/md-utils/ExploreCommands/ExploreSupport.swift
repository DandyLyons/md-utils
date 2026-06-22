import ArgumentParser

struct Expansion {
  let expandedIds: Set<Int>
  let ancestorIds: Set<Int>
  let warnings: [String]
}

struct TreeTargets {
  let sectionIds: Set<Int>
  let warnings: [String]
}

struct ExpandLineValue: ExpressibleByArgument, Equatable {
  let values: [Int]

  init?(argument: String) {
    guard argument.contains(" ") == false else {
      return nil
    }

    let parts = argument.split(separator: ",", omittingEmptySubsequences: false)
    guard parts.isEmpty == false else {
      return nil
    }

    var parsedValues: [Int] = []
    for part in parts {
      guard let value = Int(part), value > 0 else {
        return nil
      }
      parsedValues.append(value)
    }

    self.values = parsedValues
  }
}
