import MarkdownUtilitiesCore

extension ExploreRenderer {
  func makeExpansion(treeTargets: TreeTargets) -> Expansion {
    let allSections = document.allSections
    var explicitIds: Set<Int> = []
    var warnings: [String] = []

    for title in expandedTitles {
      let matches = allSections.filter { $0.title == title }
      if matches.isEmpty {
        warnings.append(contentsOf: warningLines(
          option: "--expand",
          value: title,
          suggestion: suggestedTitle(for: title, in: allSections)
        ))
      }
      explicitIds.formUnion(matches.map(\.id))
    }

    for path in expandedPaths {
      let matches = allSections.filter { $0.path.joined(separator: "/") == path }
      if matches.isEmpty {
        warnings.append(contentsOf: warningLines(
          option: "--expand-path",
          value: path,
          suggestion: suggestedPath(for: path, in: allSections)
        ))
      }
      explicitIds.formUnion(matches.map(\.id))
    }

    for line in expandedLines {
      let matches = allSections.filter { $0.headingLine == line }
      if matches.isEmpty {
        warnings.append("Warning: no heading matched --expand-line \(line)")
      }
      explicitIds.formUnion(matches.map(\.id))
    }

    for titleSubstring in expandedTitleContains {
      let normalizedSubstring = titleSubstring.lowercased()
      let matches = allSections.filter { $0.title.lowercased().contains(normalizedSubstring) }
      if matches.isEmpty {
        warnings.append("Warning: no heading matched --expand-title-contains \"\(titleSubstring)\"")
      }
      explicitIds.formUnion(matches.map(\.id))
    }

    var expandedIds = explicitIds
    if recursive {
      for section in allSections where explicitIds.contains(section.id) {
        expandedIds.formUnion(section.descendants.map(\.id))
      }
    }

    var ancestorIds: Set<Int> = []
    for targetId in expandedIds {
      ancestorIds.formUnion(ancestorIdsForSection(id: targetId, in: document.sections))
    }

    for targetId in treeTargets.sectionIds {
      ancestorIds.formUnion(ancestorIdsForSection(id: targetId, in: document.sections))
    }

    return Expansion(expandedIds: expandedIds, ancestorIds: ancestorIds, warnings: warnings)
  }

  func makeTreeTargets() -> TreeTargets {
    let allSections = document.allSections
    var sectionIds: Set<Int> = []
    var warnings: [String] = []

    for title in treeSectionTitles {
      let matches = allSections.filter { $0.title == title }
      if matches.isEmpty {
        warnings.append(contentsOf: warningLines(
          option: "--tree-section-title",
          value: title,
          suggestion: suggestedTitle(for: title, in: allSections)
        ))
      }
      sectionIds.formUnion(matches.map(\.id))
    }

    for line in treeSectionLines {
      let matches = allSections.filter { $0.headingLine == line }
      if matches.isEmpty {
        warnings.append("Warning: no heading matched --tree-section-line \(line)")
      }
      sectionIds.formUnion(matches.map(\.id))
    }

    return TreeTargets(sectionIds: sectionIds, warnings: warnings)
  }

  func warningLines(option: String, value: String, suggestion: String?) -> [String] {
    var lines = ["Warning: no heading matched \(option) \"\(value)\""]
    if let suggestion {
      lines.append("Did you mean: \(suggestion)")
    }
    return lines
  }

  func suggestedTitle(for target: String, in sections: [ExploreSection]) -> String? {
    suggestedValue(for: target, candidates: sections.map(\.title))
  }

  func suggestedPath(for target: String, in sections: [ExploreSection]) -> String? {
    suggestedValue(for: target, candidates: sections.map { $0.path.joined(separator: "/") })
  }

  func suggestedValue(for target: String, candidates: [String]) -> String? {
    let normalizedTarget = target.lowercased()
    if let exact = candidates.first(where: { $0.lowercased() == normalizedTarget }) {
      return exact
    }
    if let prefix = candidates.first(where: { $0.lowercased().hasPrefix(normalizedTarget) }) {
      return prefix
    }
    return candidates.first(where: { $0.lowercased().contains(normalizedTarget) })
  }

  func ancestorIdsForSection(id: Int, in sections: [ExploreSection]) -> Set<Int> {
    for section in sections {
      if section.id == id {
        return []
      }

      let childAncestors = ancestorIdsForSection(id: id, in: section.children)
      if childAncestors.isEmpty == false || section.children.contains(where: { $0.id == id }) {
        return childAncestors.union([section.id])
      }
    }

    return []
  }
}
