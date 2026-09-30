import Foundation
import Testing
@testable import MarkdownUtilitiesCore

@Suite struct DocumentProvenanceTests {
  private func evidence() -> DocumentProvenanceEvidence {
    .init(epoch: "epoch", observations: ["a.md", "b.md"].map {
      .init(path: $0, firstRevision: "hash", lastRevision: "hash", firstGeneration: 1,
        lastGeneration: 2, firstObservedAt: 1, lastObservedAt: 2, verified: true, completeScan: true)
    }, events: [])
  }
  private var candidates: [UUIDCollisionCandidate] {
    [.init(path: "a.md", revision: "hash"), .init(path: "b.md", revision: "hash")]
  }
  @Test func simultaneousDiscoveryAndEarlierObservationRemainAmbiguous() {
    var evidence = evidence()
    #expect(UUIDCollisionAssessor.assess(candidates, evidence: evidence, completeHolderSet: true).ambiguous)
    evidence.observations[0].firstGeneration = 0
    evidence.observations[0].firstObservedAt = 0
    #expect(UUIDCollisionAssessor.assess(candidates, evidence: evidence, completeHolderSet: true).ambiguous)
  }
  @Test func confirmedCopyExplainsDirectionButUncertaintyAlwaysWins() {
    var evidence = evidence()
    evidence.events = [.init(id: "copy", kind: .copy, path: "b.md", revision: "hash",
      sourcePath: "a.md", sourceRevision: "hash", observedAt: 2)]
    let result = UUIDCollisionAssessor.assess(candidates, evidence: evidence, completeHolderSet: true)
    #expect(result.originalPath == "a.md")
    #expect(result.duplicatePaths == ["b.md"])
    #expect(UUIDCollisionAssessor.assess(candidates, evidence: evidence, completeHolderSet: false).ambiguous)
    evidence.historyPruned = true
    #expect(UUIDCollisionAssessor.assess(candidates, evidence: evidence, completeHolderSet: true).ambiguous)
    evidence.historyPruned = false
    evidence.observations[1].historyGap = true
    #expect(UUIDCollisionAssessor.assess(candidates, evidence: evidence, completeHolderSet: true).ambiguous)
    evidence.observations[1].historyGap = false
    evidence.events[0].confirmation = .operatorConfirmed
    #expect(UUIDCollisionAssessor.assess(candidates, evidence: evidence, completeHolderSet: true).ambiguous)
  }
  @Test func editsMovesRestoresAndUnexplainedThirdHoldersAreAmbiguous() {
    var evidence = evidence()
    evidence.events = [.init(id: "copy", kind: .copy, path: "b.md", revision: "old",
      sourcePath: "a.md", sourceRevision: "hash", observedAt: 2)]
    #expect(UUIDCollisionAssessor.assess(candidates, evidence: evidence, completeHolderSet: true).ambiguous)
    evidence.events[0].kind = .move
    evidence.events[0].revision = "hash"
    #expect(UUIDCollisionAssessor.assess(candidates, evidence: evidence, completeHolderSet: true).ambiguous)
    evidence.events[0].kind = .copy
    #expect(UUIDCollisionAssessor.assess(candidates + [.init(path: "restored.md", revision: "hash")],
      evidence: evidence, completeHolderSet: true).ambiguous)
    evidence.observations = []
    #expect(UUIDCollisionAssessor.assess(candidates, evidence: evidence, completeHolderSet: true).ambiguous)
  }
}
