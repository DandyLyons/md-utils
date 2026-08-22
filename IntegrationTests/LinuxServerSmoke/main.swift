import Foundation
import Hummingbird
import HummingbirdTesting
import MarkdownUtilitiesCore
import MarkdownUtilitiesServer

enum LinuxServerSmokeError: Error {
  case unexpectedStatus(HTTPResponse.Status)
  case unexpectedRecord(GenericMarkdownRecord)
  case unexpectedOpenAPIVersion(String?)
}

@main
enum LinuxServerSmoke {
  static func main() async throws {
    #if os(macOS)
    guard #available(macOS 14.0, *) else { return }
    #endif
    try await run()
  }

  @available(macOS 14.0, *)
  private static func run() async throws {
    let typeRegistry = try MarkdownTypeRegistry(definitions: [])
    let rule = MarkdownRuleDefinition(
      name: "books",
      applicability: MarkdownRuleApplicability(paths: ["books/**"])
    )
    let ruleRegistry = try MarkdownRuleCompiler(typeRegistry: typeRegistry).compile([rule])
    let plan = try EndpointPlanCompiler(
      ruleRegistry: ruleRegistry,
      typeRegistry: typeRegistry
    ).compile(MarkdownServerConfiguration(resources: [
      MarkdownResourceConfiguration(
        name: "books",
        route: "/books",
        operations: [.list, .get],
        selection: .rule(name: rule.name),
        identityPolicy: MarkdownRecordIdentityPolicy(source: .existingIdentity)
      )
    ]))
    let store = try InMemoryRecordStore(records: [
      MarkdownRecord(
        identity: MarkdownRecordIdentity(rawValue: "dune"),
        content: "# Book\nDune",
        context: MarkdownRecordContext(path: try MarkdownRecordPath("books/dune.md"))
      )
    ])
    let snapshot = try await MarkdownServerReadSnapshotBuilder(
      store: store,
      plan: plan,
      ruleRegistry: ruleRegistry,
      typeRegistry: typeRegistry
    ).build()
    let router = Router()
    try MarkdownServerHTTPAdapter.register(plan: plan, snapshot: snapshot, on: router)
    let app = Application(router: router)

    try await app.test(.router) { client in
      try await client.execute(uri: "/books/dune", method: .get) { response in
        guard response.status == .ok else {
          throw LinuxServerSmokeError.unexpectedStatus(response.status)
        }
        let record = try JSONDecoder().decode(
          GenericMarkdownRecord.self,
          from: Data(response.body.readableBytesView)
        )
        guard record.canonicalIdentity?.rawValue == "dune",
              record.logicalPath?.rawValue == "books/dune.md"
        else {
          throw LinuxServerSmokeError.unexpectedRecord(record)
        }
      }
      try await client.execute(uri: "/openapi.json", method: .get) { response in
        guard response.status == .ok else {
          throw LinuxServerSmokeError.unexpectedStatus(response.status)
        }
        let value = try JSONDecoder().decode(
          JSONValue.self,
          from: Data(response.body.readableBytesView)
        )
        let version = value.objectValue?["openapi"]?.stringValue
        guard version == "3.1.1" else {
          throw LinuxServerSmokeError.unexpectedOpenAPIVersion(version)
        }
      }
    }
  }
}
