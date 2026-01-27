# ``MarkdownUtilities``

A Swift library for parsing and manipulating Markdown files with YAML frontmatter support.

## Overview

MarkdownUtilities provides a comprehensive set of tools for working with Markdown documents in Swift. Whether you're building a static site generator, a documentation tool, or a content management system, MarkdownUtilities offers the functionality you need to parse, manipulate, and generate Markdown content.

Key capabilities include:

- **Markdown Parsing**: Convert Markdown text to an abstract syntax tree (AST) using swift-markdown
- **Frontmatter Management**: Full CRUD operations for YAML frontmatter
- **Table of Contents Generation**: Automatically generate TOCs from document headings
- **Format Conversion**: Convert Markdown to plain text with customizable formatting
- **Round-trip Editing**: Parse, modify, and render Markdown while preserving structure

MarkdownUtilities is built with Swift 6.2 and supports macOS 13+, iOS 16+, and other Apple platforms.

## Topics

### Essentials

- <doc:GettingStarted>
- <doc:IntegrationGuide>
- <doc:MarkdownDocument>

### Working with Frontmatter

- <doc:FrontMatter/FrontMatterOverview>
- <doc:FrontMatter/CRUDOperations>

### Table of Contents

- <doc:TableOfContents/TOCOverview>
- <doc:TableOfContents/GeneratingTOC>

### Format Conversion

- <doc:FormatConversion/PlainTextConversion>

### Core Types

- ``MarkdownDocument``
- ``FrontMatter``
- ``TableOfContents``
- ``TOCEntry``

### Plain Text Conversion

- ``PlainTextOptions``
