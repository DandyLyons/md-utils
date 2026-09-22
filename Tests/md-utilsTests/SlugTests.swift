import Testing

struct SlugTests {
  @Test func outputContract() throws {
    let result = try CLIProcessTestHelper.run(["slug", "Café, World!"])
    #expect(result.status == 0)
    #expect(result.standardOutput == "café-world\n")
    #expect(result.standardError.isEmpty)
    let preserved = try CLIProcessTestHelper.run(["slug", "--policy", "preserve", "--", "--Hello World"])
    #expect(preserved.status == 0)
    #expect(preserved.standardOutput == "Hello-World\n")
  }

  @Test(arguments: [
    ["slug", "!!!"],
    ["slug", "--policy", "strictASCII", "Café"],
    ["slug", "--policy", "unknown", "Title"],
  ])
  func failure(arguments: [String]) throws {
    let result = try CLIProcessTestHelper.run(arguments)
    #expect(result.status != 0)
    #expect(result.standardOutput.isEmpty)
    #expect(!result.standardError.isEmpty)
  }
}
