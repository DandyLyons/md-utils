# Evaluating fm-var JSONPath

Apply DynamicJSON queries to portable fm-var query arguments without host I/O.

## Overview

``FMVarJSONPathEvaluator`` converts an ``FMVarQueryArgument`` to DynamicJSON, asks DynamicJSON to
parse and evaluate the authored query in strict mode, and maps every returned JSON location back to
its original ``FMVarQueryNode``. The resulting ``FMVarNodelist`` retains DynamicJSON's order and
duplicate locations exactly, including repeated selection of the same source node.

Queries must begin with `$`. Complete child, descendant, wildcard, index, slice, union, and filter
syntax is delegated to DynamicJSON rather than implemented in `MarkdownUtilitiesCore`:

```swift
let result = FMVarJSONPathEvaluator().evaluate(
  query: "$.store.book[?@.price < 10].title",
  argument: argument
)

if result.status == .selected {
  let titles = result.nodelist?.nodes ?? []
}
```

In an HTML attribute, encode characters required by the attribute syntax while preserving the
decoded JSONPath query. For example, write
`query="$.store.book[?@.price &lt; 10].title"`; the element parser supplies
`$.store.book[?@.price < 10].title` to the evaluator. Quoted member names allow dots, brackets, and
Unicode without tool-specific shorthand, such as `$['métadata']['a.b[c]']`.

Array order is stable. RFC 9535 does not define object-member enumeration order, so callers must
not depend on the relative order produced by object wildcards, descendant selection through
objects, or filters over objects. The adapter does not sort or deduplicate such results.

## Functions and Outcomes

DynamicJSON supplies `length()`, `count()`, `match()`, `search()`, and `value()`. They are available
by default and can be removed with ``FMVarJSONPathEvaluator/availableFunctions``. A query using a
removed or unknown function reports `unsupported-capability`; it is not reported as malformed.

``FMVarJSONPathEvaluation`` distinguishes:

- `selected`, including an empty nodelist for a structural mismatch;
- `invalid-query` for a missing `$`, a DynamicJSON parse failure, or a DynamicJSON evaluation/type
  failure;
- `unsupported-capability` for an unavailable function; and
- `resource-limited` for each configured resource guard.

``FMVarJSONPathFailure`` provides a stable reason, UTF-8 query range, and applicable function or
limit values. DynamicJSON 1.0.2 does not expose token offsets for parser/evaluator failures, so
those failures identify the complete query. The locally enforced root-identifier failure identifies
the first authored character.

## Resource Policy

``FMVarJSONPathLimits`` bounds query UTF-8 length, query-segment and argument-value depth, a
conservative execution-work estimate, final result count, and a conservative regular-expression
work estimate. Query length, nesting, execution, and regex guards run before evaluation. The result
count is checked after DynamicJSON returns its located nodelist because the dependency does not
offer an interruptible result callback.

The limits are deterministic counts, not elapsed-time deadlines. The execution estimate combines
query-argument node count with DynamicJSON segment and selector counts. The regex estimate combines
parsed `match()`/`search()` call count, execution work, and query-argument string sizes. Hosts should
tune the defaults for their accepted source sizes and may report the structured `limit` and
`observed` values without exposing source content.

## DynamicJSON Compatibility

DynamicJSON remains authoritative for syntax and evaluation in this implementation. The adapter
does not maintain a second RFC 9535 parser, type checker, or interpreter. Known DynamicJSON 1.0.2
differences are therefore intentionally retained:

- `length()` counts Swift extended grapheme clusters rather than Unicode scalar values;
- `match()` and `search()` use Foundation regular-expression syntax and error behavior rather than
  an independent I-Regexp implementation; and
- strict mode accepts dependency extensions including arithmetic expressions, the `pi` variable,
  and additional registered functions.

Only the five RFC functions are modeled by ``FMVarJSONPathFunction`` for host capability control;
additional DynamicJSON behavior is passed through. Compatibility changes should be made by
updating or configuring DynamicJSON, not by adding a second query implementation here.
