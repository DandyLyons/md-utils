# CLI Patterns

## CLI Pattern

- Each subcommand is a struct conforming to `AsyncParsableCommand`
- Uses `@OptionGroup var options: GlobalOptions` pattern for shared options
- GlobalOptions handles common flags like `--recursive`, `--include-hidden`, `--extensions`

## Adding CLI Commands

Pattern to follow:

1. Create `Sources/md-utils/Commands/` directory (when needed)
2. Each command is a struct conforming to `ParsableCommand`
3. Use `@OptionGroup var options: GlobalOptions` for shared options
4. Register in CLIEntry.configuration.subcommands array

## Example Command Structure

```swift
import ArgumentParser

struct MyCommand: AsyncParsableCommand {
  static let configuration = CommandConfiguration(
    commandName: "mycommand",
    abstract: "Brief description"
  )

  @OptionGroup var options: GlobalOptions

  @Argument(help: "The file to process")
  var file: String

  func run() async throws {
    // Implementation
  }
}
```

## Global Options Pattern

Shared options across commands:

```swift
struct GlobalOptions: ParsableArguments {
  @Argument(help: "Paths to Markdown files or directories to process",
            completion: .file(), transform: { Path($0) })
  var paths: [Path] = []

  @Flag(name: [.customLong("recursive"), .customShort("r")],
        inversion: .prefixedNo,
        help: "Process directories recursively (use --no-recursive to disable)")
  var recursive: Bool = true

  @Flag(name: [.customLong("include-hidden"), .customShort("i")],
        help: "Include hidden files and directories (starting with '.')")
  var includeHidden: Bool = false

  @Option(name: .long,
          help: "File extensions to process (comma-separated, default: md,markdown)")
  var extensions: String = "md,markdown"

  @Flag(name: .customLong("no-sort"),
        help: "Disable alphabetical sorting of file paths")
  var noSort: Bool = false
}
```

Key details:
- `paths` defaults to current directory when empty
- `extensions` is a comma-separated string (not an array)
- `recursive` supports `--no-recursive` via `inversion: .prefixedNo`
- Use `resolvedPaths()` to expand directories and apply filters

## OKF Command Pattern

`md-utils okf` currently targets the Open Knowledge Format v0.1 draft. The draft spec is readable at https://github.com/GoogleCloudPlatform/knowledge-catalog/blob/main/okf/SPEC.md.

OKF commands should keep hard validation aligned with the draft conformance rules. Optional quality checks should be labeled as advisory. Directory paths in CLI help, examples, and output should use explicit trailing slashes, except for bare `.`, `..`, and `~`.

`okf type set` must not guess concept types. It should write only an explicit user-provided `--type` value and should default to recursively scanning the current directory when `--dir` is omitted.
