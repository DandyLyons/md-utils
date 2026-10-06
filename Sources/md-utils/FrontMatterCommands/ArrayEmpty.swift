import ArgumentParser
import MarkdownUtilitiesCore

extension CLIEntry.FrontMatterCommands.ArrayCommands {
  /// Initializes missing or null top-level values while preserving existing arrays.
  struct Initialize: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
      commandName: "init",
      abstract: "Create an empty frontmatter array if the key is missing or null",
      discussion: NonMarkdownFrontMatterHelp.appending(to: """
        Creates a typed empty array at a literal top-level key. Existing arrays
        are preserved. Missing or null values become empty arrays; other
        non-array values are errors.
        Existing nonempty arrays are reported on stderr. No-op files are not written.

        Missing Markdown frontmatter is created automatically. Non-Markdown
        creation follows the usual --create-frontmatter authorization rules.
        --frontmatter-format applies only when creating the array.

        EXAMPLE:
          md-utils fm array init --key tags posts/
        """),
    )

    @OptionGroup var arguments: EmptyArrayArguments

    mutating func run() async throws {
      try arguments.run(operation: .initialize)
    }
  }

  /// Empties an existing array while retaining its key.
  struct Clear: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
      commandName: "clear",
      abstract: "Clear a frontmatter array while retaining its key",
      discussion: NonMarkdownFrontMatterHelp.appending(to: """
        Replaces a nonempty array at a literal top-level key with a typed empty
        array. Missing keys and empty arrays succeed without writing. Non-array
        values (including null) are errors. Use fm remove to delete the key.
        Missing frontmatter is left unchanged.
        --frontmatter-format applies only when clearing a nonempty array.

        EXAMPLE:
          md-utils fm array clear --key tags post.md
        """),
    )

    @OptionGroup var arguments: EmptyArrayArguments

    mutating func run() async throws {
      try arguments.run(operation: .clear)
    }
  }

  /// Shared CLI options and file processing for empty-array operations.
  struct EmptyArrayArguments: ParsableArguments {
    @OptionGroup var options: GlobalOptions
    @OptionGroup var lineCommentOptions: LineCommentFrontMatterOptions

    @Option(name: .shortAndLong, help: "The literal top-level frontmatter key")
    var key: String

    @Option(name: .long, help: "Frontmatter format for modified files (yaml, toml); no-op files are unchanged")
    var frontmatterFormat: FrontMatterFormat?

    @Flag(name: .long, help: "Process mapped non-Markdown files")
    var includeNonMD = false

    @Flag(name: .long, help: "Authorize frontmatter creation in non-Markdown files")
    var createFrontmatter = false

    enum Operation {
      case initialize
      case clear
    }

    func run(operation: Operation) throws {
      let timer = CommandTimer()
      let paths = try options.resolvedFrontMatterPaths(
        includeNonMarkdown: includeNonMD,
        lineCommentFrontmatter: lineCommentOptions.lineCommentFrontmatter,
      )
      guard !paths.isEmpty else {
        throw ValidationError("No Markdown files found to process")
      }

      var updatedCount = 0
      var unchangedCount = 0
      var failedCount = 0
      for path in paths {
        do {
          let parsed = try FrontMatterCLIMutator.parsedFile(
            at: path,
            includeNonMarkdown: includeNonMD,
            lineCommentFrontmatter: lineCommentOptions.lineCommentFrontmatter,
          )
          var doc = parsed.document
          let exists = doc.hasKey(key)
          let initializesNull = operation == .initialize && doc.getValue(forKey: key) == .null
          let array = initializesNull ? [] : try ArrayHelpers.getOrCreateArrayKey(key, in: doc, path: path)
          let message: String?
          switch operation {
          case .initialize:
            message = exists && !initializesNull
              ? "\(array.isEmpty ? "empty" : "nonempty") array already exists at key \"\(key)\"; unchanged"
              : nil
          case .clear:
            message = !exists ? "key \"\(key)\" is missing; nothing to clear"
              : array.isEmpty ? "array at key \"\(key)\" is already empty; unchanged" : nil
          }
          if let message {
            CLIStyle.writeStderr("\(CLIStyle.path(path.string)): \(message)")
            unchangedCount += 1
            continue
          }

          try FrontMatterCLIMutator.authorizeCreationIfNeeded(
            for: parsed,
            options: options,
            createFrontmatter: createFrontmatter,
          )
          if let frontmatterFormat { doc.frontMatterFormat = frontmatterFormat }
          doc.frontMatter[key] = .array([])
          try FrontMatterCLIMutator.write(doc, parsed: parsed, to: path)
          updatedCount += 1
        } catch {
          CLIStyle.writeError("\(CLIStyle.path(path.string)): \(error.localizedDescription)")
          failedCount += 1
        }
      }

      let action = operation == .initialize ? "Initialized" : "Cleared"
      timer.writeStatus("\(action) frontmatter array \"\(key)\" in \(updatedCount) file(s); \(unchangedCount) unchanged; \(failedCount) failed")
      if failedCount > 0 { throw ExitCode.failure }
    }
  }
}
