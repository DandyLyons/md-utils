import ArgumentParser
import Foundation
import Hummingbird
import Logging
import MarkdownUtilitiesServer
import PathKit

/// Native read-only HTTP distribution for explicitly configured Markdown resources.
@main
struct ServerEntry: AsyncParsableCommand {
  static let configuration = CommandConfiguration(
    commandName: "md-utils-server",
    abstract: "Serve configured Markdown resources through a read-only HTTP API.",
    version: "0.1.0-alpha"
  )

  @Option(
    name: .long,
    help: "Project directory containing Markdown records and .md-utils/."
  )
  var projectRoot = "."

  @Option(
    name: .long,
    help: "Server YAML path relative to --project-root (default: .md-utils/server.yaml)."
  )
  var config: String?

  @Option(name: .long, help: "Hostname or IP address to bind.")
  var hostname = "127.0.0.1"

  @Option(name: .long, help: "TCP port to bind.")
  var port = 8080

  mutating func validate() throws {
    guard (1...65_535).contains(port) else {
      throw ValidationError("--port must be between 1 and 65535")
    }
    guard hostname.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false else {
      throw ValidationError("--hostname must not be empty")
    }
  }

  mutating func run() async throws {
    #if os(macOS)
    guard #available(macOS 14.0, *) else {
      throw ValidationError("md-utils-server requires macOS 14 or later")
    }
    #endif
    try await runServer()
  }

  @available(macOS 14.0, *)
  private func runServer() async throws {
    let root = Path(projectRoot)
    let loader = MarkdownServerProjectLoader(
      projectRoot: root,
      configurationFile: config.map { Path($0) }
    )
    let runtime = try await loader.load()

    let router = Router()
    try MarkdownServerHTTPAdapter.register(
      plan: runtime.plan,
      snapshot: runtime.snapshot,
      on: router
    )

    var logger = Logger(label: "md-utils-server")
    if let configuredLevel = ProcessInfo.processInfo.environment["LOG_LEVEL"],
       let level = Logger.Level(rawValue: configuredLevel.lowercased())
    {
      logger.logLevel = level
    }
    logger.info("Loaded md-utils server project", metadata: [
      "project_root": "\(loader.projectRoot.string)",
      "configuration": "\(loader.configurationFile.string)",
      "records": "\(runtime.importedRecordCount)",
      "resources": "\(runtime.plan.resources.count)",
      "routes": "\(runtime.plan.routes.count)",
    ])
    let applicationLogger = logger

    let bindHostname = hostname
    let bindPort = port
    let app = Application(
      router: router,
      configuration: .init(
        address: .hostname(bindHostname, port: bindPort),
        serverName: "md-utils-server"
      ),
      onServerRunning: { _ in
        applicationLogger.info("md-utils server listening", metadata: [
          "hostname": "\(bindHostname)",
          "port": "\(bindPort)",
        ])
      },
      logger: applicationLogger
    )
    try await app.runService()
  }
}
