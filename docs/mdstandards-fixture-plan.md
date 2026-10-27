# Installable standards and workflow fixtures

Status: fixture-first approach approved 2026-10-25; domain definitions and runtime
contracts still require design approval. Parent #191; coordinate #192–#196.
Tracking: [#201](https://github.com/DandyLyons/md-utils/issues/201).
Recipe proposal: [community research and domain design](md-recipes-proposal.md).

## Deliverables and ordering

1. Approve a useful recipe standard and a second small independent standard.
2. Write definitions, original example data, local configurations and expected
   outcomes before implementing their workflows. Use experimental release histories
   with an initial release, identity migration, and structural migration.
3. Finalize relevant API/CLI contracts, then turn scenarios into executable Swift
   Testing fixtures. Do not freeze incidental output or manufacture passing tests
   for unsupported features. Track designed/unimplemented/verified status separately.
4. Implement approved slices and run fixtures. Publish reproducible installation
   and workflow instructions and record external application compatibility evidence.

## Scenario inventory

Each scenario records pinned definitions, initial files, requested operation,
expected staged bytes, loss and validation findings, review report, post-apply
files, and recovery state. Assertions target behavior rather than implementation.

| Scenario | Required observable expectation |
| --- | --- |
| Fresh install and direct adoption | Complete pinned dependencies; chosen local population; independent rule/data findings |
| Identity and structural migrations | Each predecessor step and full chain; source identities and unrelated content retained |
| Stronger local rules | Standard-valid input can fail local validation; no invented domain values |
| Different local shape | Directional adapters; supported semantic round trip asserted explicitly |
| Lossy import | Specific losses acknowledged before apply; no lossless round-trip claim |
| Optional versus required loss | Optional loss may permit valid export; required loss blocks it without new information |
| Relationships | Target identity survives path mapping; missing/ambiguous targets remain findings |
| Altered/missing dependencies | Refuse invalid installation/execution; no hidden fallback |
| Stale originals or staged edits | No overwrite of newer originals; edited stage requires renewed assessment/review |
| Partial apply and retry | Completed/unattempted writes recorded; staging retained until confirmed success |
| Successful apply | Reviewed bytes installed; cleanup within apply; agreed recovery/report retention honored |
| External integration | Named format/application version and supported subset; no universal compatibility claim |

All scenarios currently remain design-only. No runtime tests have been run or
passed for mdstandards. Recipe schemas wait for owner review of the proposal.
