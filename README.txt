md-utils

A collection of utilities for working with Markdown files.

  MarkdownUtilities, A Swift module for parsing and manipulating Markdown content.

  md-utils, A command-line tool, built on top of MarkdownUtilities, for performing various operations on Markdown files.

  markdown-utilities, An Agent Skill that instructs LLMs to utilize the md-utils command-line tool for Markdown file operations.

Status

This project is currently in early development. Features and APIs may change. Many functionalities are yet to be implemented.

Features

  Generate Table of Contents (TOC) for Markdown files.

  Promote/Demote headings: Adjusts the hierarchical level of a heading and all its nested subheadings while maintaining their relative structure.

  Reorder sections: Move a section (a heading and its content) up or down within the document.

  Extract/Inject sections: Extract a section into a separate Markdown file or inject content from another Markdown file into a specified section.

  Select Content:

    Select by heading: Extract content under a specific heading.

    Select by line range: Extract content based on specified line numbers.

  Validation:

    Validate links: Check for broken links within the Markdown file.

    Validate markdown flavors: Ensure the Markdown content adheres to specific flavor guidelines (e.g., GitHub Flavored Markdown, CommonMark, Obsidian Flavored Markdown).

  Convert: Convert into and from various formats including HTML, plain text, rich text, and XML.

  File metadata handling: Read and write file metadata such as creation date, modification date, and custom attributes.

  YAML Front Matter Handling [COMING SOON]: I have already created FrontRange, a Swift package for parsing, mutating, serializing, and deserializing text documents with YAML front matter. FrontRange will be ported directly into md-utils to provide robust front matter handling capabilities, including CRUD operations on front matter metadata, batch operations, structured data extraction, and many other features! Stay tuned!

Architecture

  Swift 6.2

  All testing is done using native Swift Testing framework.

Dependencies

  MarkdownSyntax - Swift Markdown parsing and syntax tree

  swift-parsing - Parser combinators

  swift-argument-parser - CLI argument parsing

  PathKit - File path handling

  Yams - YAML parsing and serialization

Contributing

The project is still in its early stages, and is not yet open for contributions. If you have a suggestion, please open an issue to discuss it.