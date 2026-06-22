import MarkdownUtilities

extension ExploreRenderer {
  func renderMarkdown(includeCollapsedStubs: Bool) -> String {
    let expansion = makeExpansion(treeTargets: TreeTargets(sectionIds: [], warnings: []))
    var blocks: [String] = []

    if expandFrontmatter, let frontmatter = document.frontmatter {
      blocks.append(document.sourceText(in: frontmatter.lineRange))
    }

    if expandPreamble, let preamble = document.preamble {
      blocks.append(document.sourceText(in: preamble.lineRange))
    }

    for section in document.sections {
      renderMarkdownSection(
        section,
        topLevel: nil,
        expansion: expansion,
        includeCollapsedStubs: includeCollapsedStubs,
        into: &blocks
      )
    }

    return blocks.joined(separator: "\n") + (blocks.isEmpty ? "" : "\n")
  }

  func renderMarkdownSection(
    _ section: ExploreSection,
    topLevel: Int?,
    expansion: Expansion,
    includeCollapsedStubs: Bool,
    into blocks: inout [String]
  ) {
    guard shouldRender(section, topLevel: topLevel, expansion: expansion) else {
      return
    }

    let isExpanded = expansion.expandedIds.contains(section.id)
    let isAncestor = expansion.ancestorIds.contains(section.id)
    guard includeCollapsedStubs || isExpanded || isAncestor else {
      return
    }

    blocks.append(section.headingMarkdown)
    if isExpanded || isAncestor {
      if let bodyLineRange = section.bodyLineRange, isExpanded {
        let body = document.sourceText(in: bodyLineRange)
        if body.isEmpty == false {
          blocks.append(body)
        }
      }

      for child in section.children {
        renderMarkdownSection(
          child,
          topLevel: child.level,
          expansion: expansion,
          includeCollapsedStubs: includeCollapsedStubs,
          into: &blocks
        )
      }
    }
  }

  func shouldRender(_ section: ExploreSection, topLevel: Int?, expansion: Expansion) -> Bool {
    topLevel == nil
      || section.level == topLevel
      || expansion.expandedIds.contains(section.id)
      || expansion.ancestorIds.contains(section.id)
  }
}
