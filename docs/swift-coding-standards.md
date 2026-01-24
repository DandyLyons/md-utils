# Swift Coding Standards

## Language Mode

All code uses Swift 6 features and strict concurrency.

## STRICTLY FORBIDDEN: Force Unwrapping with `!`

Force unwrapping optionals with `!` is **absolutely prohibited** in this codebase. This prevents runtime crashes and enforces safe optional handling.

### NEVER do this:

```swift
// WRONG - FORBIDDEN
let value = dictionary["key"]!
let item = array.first!
let result = someOptional!
```

### Always use safe alternatives:

#### Optional Binding

```swift
// CORRECT - Use optional binding
if let value = dictionary["key"] {
  // Use value safely
}
```

#### Guard for Early Exit

```swift
// CORRECT - Use guard for early exit
guard let value = dictionary["key"] else {
  throw MyError.missingKey
}
```

#### #require in Tests

```swift
// CORRECT - Use try #require() in tests
let value = try #require(dictionary["key"])
```

#### Nil Coalescing

```swift
// CORRECT - Use nil coalescing when appropriate
let value = dictionary["key"] ?? defaultValue
```

#### Optional Chaining

```swift
// CORRECT - Use optional chaining
someOptional?.doSomething()
```

## Swift 6 Features

Use modern Swift features including:
- Strict concurrency
- Async/await
- Sendable types
- Actor isolation
