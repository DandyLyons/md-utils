# Survey verification matrix

This maps the implemented survey contract to behavioral tests and shared runtime
guarantees. It does not claim future snapshot contract projections or extended
relationship hosts/configuration are implemented; those remain proposals in
`survey-extension-proposals.md`. The historical compound budget requirement is
made concrete as the limits the current CLI/runtime actually publish.

## Scope and execution

| Requirement | Evidence |
| --- | --- |
| Registration/defaults, metric replacement, flags, output formats | `SurveyCommandsTests.focusedCommandsAreDiscoverable`, `vanillaSurveySelectsOverview`, `surveyOutputFormatsAreConsistent`, `unrelatedSubcommandOptionsAreRejected` |
| Recursive union/deduplication, exclusions, LF/NUL lists, confinement | `recursiveTextScopeDeduplicatesAndExplainsExclusions`, `fileListOnlyDoesNotAddWorkingDirectory`, `nulListsExclusionsAndConfinement` |
| Hidden entries, symlinks including an ancestor, explicit missing/unreadable paths | `SurveyVerificationTests.hiddenFilesAndSymlinkAncestorsAreSkippedVisibly`; `SurveyCommandsTests.malformedIsSuccessfulWhileMissingInputIsIncomplete`, `unreadableTextDoesNotHideReadableSiblings`, `permissionDeniedInputsRemainVisibleAndDoNotHideSiblings` |
| Selected-text count and oversized source budget | `budgetExhaustionIsNotAnUnreadableFile`, `largeNonTextAttachmentsDoNotStopKeySurvey`, `SurveyVerificationTests.oversizedTextIsBudgetExhaustionBeforeReadingItsContents` |
| Snapshot budgets respect Markdown filtering and non-text skips | `SurveyVerificationTests.snapshotBudgetCountsSelectedTextRatherThanSkippedEvidence` (both source modes) |
| Shared computation limits retain partial results/coverage | `CollectionRelationshipQueryTests`: `record budget returns available results and unknown type selection remains incomplete`, `candidate and occurrence budgets return partial envelopes` |
| Malformed findings versus execution failure; cancellation | `malformedIsSuccessfulWhileMissingInputIsIncomplete`, `standardsAreExplicitlyUnsupported`, `ruleSurveyAnalyzesEachRecordOnceWithoutChangingSelection`; `SurveyVerificationTests.cancelledCacheRefreshDoesNotFallBackToSources` |

## Statistics and contracts

| Requirement | Evidence |
| --- | --- |
| Parsed kinds, YAML/TOML/host mapping, missing/null, literal/pointer paths, frequencies and outliers | `MarkdownSurveyTests` (11 portable tests); CLI `keyPrevalenceUsesAssessableFilesAndHandlesZeroDenominator`, `mixedKeyKindsOfferFocusedInvestigation`, `compactAndPrettySurveyJSONContainIdenticalData` |
| Selection is independent of conformance; unknown selection is not uncovered | `ruleSelectionDoesNotRequireConformanceAndOverlapsRemainInformational`, `ruleSurveyAnalyzesEachRecordOnceWithoutChangingSelection` |
| No rules differs from invalid configuration | `SurveyVerificationTests.absentRulesAndInvalidConfigurationHaveDifferentResults`; `missingExplicitConfigurationIsNotNoRules` |
| Referenced/local/unreferenced definitions and explicit matching hint | `ruleSelectionDoesNotRequireConformanceAndOverlapsRemainInformational`, `typeInventoryHasAnActionableMatchingHint` |
| Recursive type conformance, including targets outside source selection | `SurveyVerificationTests.typeMatchingReassessesRecursiveTargetsOutsideSelection`: pass/fail/unavailable outcomes and re-evaluation after target repair; direct collection-aware checker oracle |
| Changed definitions are not stale cached conformance | `SurveyVerificationTests.changedDefinitionsChangeTypeAssessmentsAfterIndexRefresh` |
| Named self-links, ordinary/outgoing edges, selection boundary, truncation | `SurveyVerificationTests.relationshipSummaryPreservesSelfLinksAndSelectionBoundaries`; `relationshipsAreSummarizedAndLimited`, `relationshipGroupsPreserveTypeAndRelationIdentity` |
| Standards placeholder is explicit and does no scan | `standardsAreExplicitlyUnsupported`, including mixed requests and unmeasured coverage |

Ordinary body self-references are excluded by the shared link scanner. Named
self-links are retained separately. The boundary fixture exercises that existing
distinction; it does not redefine ordinary link discovery.

## Cache, publication, and outputs

| Requirement | Evidence |
| --- | --- |
| Typed direct/cache equivalence; add/change/delete; no unrelated scans | `SurveyVerificationTests.refreshChangesAndDeletionsPreserveTypedStatisticsWithoutScanningOtherFolders`; `directAndCachedCoverageAgreeForBinaryAndMalformedFiles`, `existingIndexRefreshesAndSnapshotSurvivesDeletedSources` |
| Hash verification and definition changes | `hashVerificationDetectsStatPreservingChanges`; new definition-refresh test above; `CollectionIndexerTests` fingerprint invalidation tests |
| No implicit index creation, corrupt-cache fallback, cancellation | `recursiveTextScopeDeduplicatesAndExplainsExclusions`, `brokenCacheFallsBackWithoutChangingFindings`, `SurveyVerificationTests.cancelledCacheRefreshDoesNotFallBackToSources` |
| Snapshot read-only, missing/removed sources/config, missing projections | `SurveyVerificationTests.snapshotQueriesIgnoreDeletedConfigurationAndSourcesWithoutMutatingDatabase`; `snapshotModeNeverFallsBackWhenDatabaseMissing`; inspection of the snapshot-only branch and `SurveyIndexSnapshot.read` confirms only published SQLite evidence is consumed |
| Atomic publication, incomplete scopes, independent readers, generation supersession | `cancelledPublicationCannotExposeNewExtraction`; `CollectionIndexerTests`: `independent readers see published content rather than staged batches`, `cancelled staged batches are discarded without publishing partial content`, `selective deletion and fingerprint changes invalidate other scopes`, `superseded scan cannot overwrite a newer generation` |
| Versioned JSON, exact compact/pretty data, statuses and stderr separation | `compactAndPrettySurveyJSONContainIdenticalData`, `jsonRetainsSelectionAndMetricParameters`, process-boundary non-text/value-hint tests |
| Concise text uses the same report; styling preserves content | `focusedSummariesLeadWithFindings`, `typeMatchSummaryKeepsCountsAndBoundsExamples`, `textReportsRenderValuesAndNestedFindingsWithoutJSONEnvelopes`; parameterized `CLIStyleTests` for all survey metrics |
| Scoped/quoted executable hints, broader rule scope | `keyPresenceHintsSurveyTheFolderWithALiteralKey`, `valueHintsDescribeAFrontmatterPipelineAndRespectRestrictedScope`, `unassessableFilesHaveBoundedReasonsAndInvestigationHints`, rule/relationship hint regressions; installed agent example script |
| Actual help and canonical/bundled skill | `CLIHelpTests`, `AgentCommandsTests`, `check-agent-skill.py`, `verify-agent-skill-examples.py` |

## Defects found and corrected by this pass

1. Snapshot `maxFiles` counted non-text observations, and Markdown-only scope was
   filtered too late. Direct discovery also tied its metadata-entry guard too
   closely to small text-file limits. A valid one-text-file survey could exhaust
   a budget before reaching that file. Budgeting now follows the selected text
   population while retaining skipped-file coverage. The separate metadata guard
   has a floor of 100,000 visited entries and remains bounded independently.
2. Relationship-aware type matching passed an unrevisioned discovery record into
   a collection-aware checker. It now uses the exact snapshot source after checking
   its UTF-8 bytes still match discovery (including canonically equivalent Unicode
   strings). Recursive target outcomes are preserved; a changed source remains
   unavailable instead of being silently substituted.
3. Snapshot-only relationship queries could ignore an explicit unsupported
   configuration override. They now report that mode as unavailable without
   probing the config or substituting the conventional configuration's results.

## Limits of this verification

Verification on 2026-10-27: the complete native suite passed **1,947 tests across
eight products**, exit 0. Evidence is in `tmp/survey-matrix-full-final.log`.
Final focused checks also cover the heading-sensitive local-type oracle and
current help/skill guidance. Snapshot-budget and local-parse-budget red logs
capture the failures before their respective fixes.

These are regression and shared-backend checks, not a proof of a fixed total RSS
or wall-clock bound. File/evidence byte limits and relationship-engine limits are
explicit; ordinary rule/type work is still proportional to selected files and
definitions. No independent CLI budget for rule/type pairs is claimed. All-output
requests deliberately retain more evidence. Linux remains CI-only; WASM is
deferred by project policy. Multi-process stress/performance campaigns beyond the
existing independent-reader/generation tests are not claimed.
