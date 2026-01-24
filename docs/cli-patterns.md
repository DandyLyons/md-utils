# CLI Patterns

## CLI Pattern (Following FrontRange)

- Each subcommand is a struct conforming to `AsyncParsableCommand`
- Uses `@OptionGroup var options: GlobalOptions` pattern for shared options
- GlobalOptions handles common flags like `--recursive`, `--include-hidden`, `--extensions`

## Adding CLI Commands

Pattern to follow (based on FrontRange):

1. Create Sources/md-utils/Commands/ directory (when needed)
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
  @Flag(name: [.short, .long], help: "Process directories recursively")
  var recursive: Bool = true

  @Flag(name: .customShort("i"), help: "Include hidden files")
  var includeHidden: Bool = false

  @Option(help: "File extensions to process")
  var extensions: [String] = [".md"]
}
```
