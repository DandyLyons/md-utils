# ``MarkdownUtilitiesTemplates``

Generate Markdown from a Knap body template and explicit structured frontmatter.

## Overview

Use the `md-utils template render` command or the Swift rendering API. SwiftKnap
renders the body; Yams serializes YAML frontmatter. The current feature is a
single-document renderer for native platforms, with no WebAssembly integration.

## Topics

### User guide

- <doc:RenderingMarkdownWithKnap>

### Rendering API

- ``MarkdownTemplateRenderer``
- ``MarkdownTemplateInput``
- ``MarkdownTemplateLimits``
- ``RenderedMarkdownTemplate``
- ``MarkdownTemplateError``
