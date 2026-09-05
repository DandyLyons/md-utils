# Coercing fm-var Scalars

Interpret selected YAML scalar content and produce locale-independent default output.

## Overview

``FMVarScalarCoercer`` consumes an identified ``FMVarQueryNode`` after YAML projection and JSONPath
selection. Coercion always uses the node's retained ``FMVarSourceScalar/content`` rather than its
projected JSON type. Quoted and unquoted YAML scalars therefore follow the same explicit `type` or
`item-type` instruction.

The coercer returns ``FMVarScalarCoercionResult`` without throwing. A success contains an
``FMVarCoercedScalar`` with a structured ``FMVarScalarValue``, the retained source content, and its
default serialization. A failure contains ``FMVarScalarCoercionFailure`` with a stable reason and
diagnostic code. Callers can add element source ranges and presentation-specific context later.

```swift
let projection = FMVarYAMLProjector().project(yaml: "price: 1.2300")
guard let argument = projection.argument else { return }

let selection = FMVarJSONPathEvaluator().evaluate(query: "$.price", argument: argument)
guard let node = selection.nodelist?.nodes.first else { return }

let result = FMVarScalarCoercer().coerce(node, as: .number)
result.scalar?.defaultSerialization  // "1.2300"
```

## Portable Types

| Declared type | Accepted source content | Default serialization |
| --- | --- | --- |
| `string` | Any supported scalar text, including empty text | Unchanged |
| `boolean` | Case-insensitive `true` or `false` | `TRUE` or `FALSE` |
| `integer` | Optional sign and ASCII base-10 digits within ±9007199254740991 | Ungrouped normalized base 10 |
| `number` | Finite YAML Core decimal syntax representable as binary64 | Original decimal spelling |
| `date` | RFC 3339 `YYYY-MM-DD` | Validated source date |
| `datetime` | RFC 3339 date and partial time without an offset | ISO-style local date-time |
| `timestamp` | RFC 3339 date-time with `Z` or `±HH:MM` | ISO-style timestamp retaining offset semantics |

Temporal parsing validates Gregorian calendar dates and fixed-width time components. Seconds may
be `60` as permitted by the RFC 3339 grammar. Fractional seconds retain every authored digit.
Default temporal output canonicalizes `t` and `z` to uppercase while preserving whether the source
used `Z`, `+00:00`, `-00:00`, or another numeric offset.

Hexadecimal and octal YAML integers are not accepted as declared `integer` or `number` values.
This makes explicit coercion independent of YAML type inference and keeps the portable lexical
contract decimal-only.

## Unsupported Values

Null, sequence, and mapping nodes are not scalar-coercion inputs. A scalar also fails when its YAML
source association is missing. Successful values must contain only XML 1.0 characters and must not
contain CR or LF line breaks. XML-valid tabs and ordinary Unicode, including supplementary-plane
characters, are supported.

Coercion does not apply `default-zero` or `default-null`, locale-sensitive formatting, escaping,
list formatting, or cache edits. Those stages consume the typed scalar and default serialization
without modifying the authoritative YAML value.

## Topics

### Coercion

- ``FMVarScalarCoercer``
- ``FMVarScalarCoercionResult``
- ``FMVarCoercedScalar``
- ``FMVarScalarValue``
- ``FMVarScalarCoercionFailure``
- ``FMVarScalarCoercionFailureReason``

### Temporal Values

- ``FMVarDateValue``
- ``FMVarTimeValue``
- ``FMVarDateTimeValue``
- ``FMVarTimestampValue``
- ``FMVarUTCOffset``
- ``FMVarUTCOffsetSign``
