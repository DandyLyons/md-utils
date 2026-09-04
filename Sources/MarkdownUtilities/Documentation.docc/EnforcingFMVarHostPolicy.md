# Enforcing fm-var Host Policy

Load local fm-var sources through an explicit, bounded filesystem policy.

## Create a Policy

``FMVarHostPolicy`` requires an existing local directory as its allowed root. It resolves the root's
symlinks during initialization and has no current-directory fallback. The default source limit is
8 MiB. The default query policy allows 4,096 UTF-8 query bytes, nesting depth 128, execution work
1,000,000, 10,000 results, and regular-expression work 1,000,000.

```swift
let policy = try FMVarHostPolicy(
  allowedRoot: URL(fileURLWithPath: "/project/content/", isDirectory: true)
)
let provider = FileFMVarResourceProvider(policy: policy)
let evaluator = policy.makeJSONPathEvaluator()
```

The evaluator exposes exactly RFC 9535's `length()`, `count()`, `match()`, `search()`, and
`value()` functions by default. A caller may disable individual standard functions. Dependency-only
functions are unavailable and produce an unsupported-query-capability result. Query work is bounded
by deterministic estimates rather than a wall-clock deadline because the synchronous evaluator
cannot be interrupted safely.

## Load Sources

Call ``FileFMVarResourceProvider/containingResource(at:)`` to obtain the containing Markdown
snapshot. This applies the same root, kind, and byte policy used for external sources and gives the
document a canonical file-URL base. Pass the successful resource and the provider to
`FMVarSourceResolver`.

The initial native policy supports `.md`, `.markdown`, `.yaml`, and `.yml` files. Same-document,
relative-path, absolute-path, and `file:` references are allowed only when the decoded normalized
path and its final symlink-resolved target remain beneath the allowed root. In-root symlinks are
permitted. Strict UTF-8 and Markdown/YAML representation decoding are enforced by
`FMVarSourceResolver` after the bounded byte snapshot is loaded.

Network schemes, file-URI authorities, credentials, URI queries, redirects, substituted resources,
directories, and other file kinds are unsupported. A URI query remains valid RFC 3986 syntax; its
rejection is host policy, not a portable source-reference error.

## Handle Failures Safely

Access failures distinguish a direct root escape, symlink escape, missing source, excessive size,
unsupported capability, denial, and ordinary read failure. `FMVarSourceResolver` preserves those
categories as stable `fm-var.source.*` diagnostic codes. None is reclassified as URI or JSONPath
syntax failure, and resolution never mutates cached Markdown children.

Provider failure messages do not include source bytes or URI query contents. Use
`FMVarResourceIdentifier.diagnosticDescription` instead of `rawValue` in logs and diagnostics;
it removes URI credentials and replaces query contents with a fixed marker.
