import MarkdownUtilities

extension ExploreRenderer {
  func renderTerminal() -> String {
    if tree {
      return renderDocumentTree()
    }

    let treeTargets = makeTreeTargets()
    let expansion = makeExpansion(treeTargets: treeTargets)
    var lines = [CLIStyle.hint("Hint: expand by title (-e), title contains (-C), path (-P), line (-l), frontmatter (-F), or preamble (-p).")]
    lines.append(contentsOf: expansion.warnings)
    lines.append(contentsOf: treeTargets.warnings)

    if let frontmatter = document.frontmatter {
      if expandFrontmatter {
        lines.append("▼ \(CLIStyle.exploreLabel("Frontmatter"))")
        lines.append(document.sourceText(in: frontmatter.lineRange))
      } else {
        let frontmatterMetadata = CLIStyle.muted(metadata([plural(frontmatter.fieldCount, "field")]))
        lines.append("► \(CLIStyle.exploreLabel("Frontmatter")) \(frontmatterMetadata)")
      }
    }

    if let preamble = document.preamble {
      if expandPreamble {
        lines.append("▼ \(CLIStyle.exploreLabel("Preamble"))")
        lines.append(document.sourceText(in: preamble.lineRange))
      } else {
        let preambleMetadata = CLIStyle.muted(
          metadata([plural(preamble.wordCount, "word"), plural(preamble.lineCount, "line")])
        )
        lines.append("► \(CLIStyle.exploreLabel("Preamble")) \(preambleMetadata)")
      }
    }

    for section in document.sections {
      renderTerminalSection(section, topLevel: nil, expansion: expansion, treeTargets: treeTargets, into: &lines)
    }

    return lines.joined(separator: "\n") + "\n"
  }

  func renderDocumentTree() -> String {
    var lines: [String] = []
    if hasExpansionOptions {
      lines.append("Warning: expansion options are ignored when --tree is used")
    }

    lines.append("Tree: \(sourceName ?? "Document") \(metadata(documentTreeMetadata()))")

    let childCount = document.sections.count
      + (document.frontmatter == nil ? 0 : 1)
      + (document.preamble == nil ? 0 : 1)
    var renderedChildCount = 0
    if let frontmatter = document.frontmatter {
      renderedChildCount += 1
      let connector = renderedChildCount == childCount ? "└─" : "├─"
      lines.append(
        "\(connector) \(CLIStyle.frontmatterLabel("Frontmatter")) \(metadata(frontmatterMetadata(frontmatter)))"
      )
    }

    if let preamble = document.preamble {
      renderedChildCount += 1
      let connector = renderedChildCount == childCount ? "└─" : "├─"
      lines.append("\(connector) \(CLIStyle.preambleLabel("Preamble")) \(metadata(preambleMetadata(preamble)))")
    }

    for section in document.sections {
      renderedChildCount += 1
      renderTreeSection(
        section,
        prefix: "",
        isLast: renderedChildCount == childCount,
        into: &lines
      )
    }

    return lines.joined(separator: "\n") + "\n"
  }

  func renderTerminalSection(
    _ section: ExploreSection,
    topLevel: Int?,
    expansion: Expansion,
    treeTargets: TreeTargets,
    into lines: inout [String]
  ) {
    guard shouldRender(section, topLevel: topLevel, expansion: expansion) else {
      return
    }

    if treeTargets.sectionIds.contains(section.id) {
      lines.append("Tree: \(section.title) \(metadata(treeSectionMetadata(section)))")
      for (index, child) in section.children.enumerated() {
        renderTreeSection(
          child,
          prefix: "",
          isLast: index == section.children.count - 1,
          into: &lines
        )
      }
      return
    }

    if expansion.expandedIds.contains(section.id) || expansion.ancestorIds.contains(section.id) {
      lines.append("▼ \(styledHeading(section)) \(CLIStyle.muted(metadata(["line \(section.headingLine)"])))")
      if expansion.expandedIds.contains(section.id), let bodyLineRange = section.bodyLineRange {
        let body = document.sourceText(in: bodyLineRange)
        if body.isEmpty == false {
          lines.append(body)
        }
      }

      for child in section.children {
        renderTerminalSection(child, topLevel: child.level, expansion: expansion, treeTargets: treeTargets, into: &lines)
      }
    } else {
      let collapsedMetadata = CLIStyle.muted(metadata(sectionMetadata(section)))
      lines.append("► \(styledHeading(section)) \(collapsedMetadata)")
    }
  }

  func renderTreeSection(
    _ section: ExploreSection,
    prefix: String,
    isLast: Bool,
    into lines: inout [String]
  ) {
    let connector = isLast ? "└─" : "├─"
    lines.append("\(prefix)\(connector) \(section.title) \(metadata(treeSectionMetadata(section)))")

    let childPrefix = prefix + (isLast ? "   " : "│  ")
    for (index, child) in section.children.enumerated() {
      renderTreeSection(
        child,
        prefix: childPrefix,
        isLast: index == section.children.count - 1,
        into: &lines
      )
    }
  }

  func styledHeading(_ section: ExploreSection) -> String {
    CLIStyle.markdownHeading(section.headingMarkdown, level: section.level)
  }
}
