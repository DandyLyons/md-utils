# ``MarkdownUtilitiesTemplates``

Generate Markdown from a Stencil body template and explicit structured frontmatter.

## Overview

Use the `md-utils template render` command or the Swift rendering API. Stencil
renders the body; Yams serializes YAML frontmatter. The current feature is a
single-document prototype for native platforms, with no WebAssembly integration.

## Topics

### User guide

- <doc:RenderingMarkdownWithStencil>

### Rendering API

- ``MarkdownTemplateRenderer``
- ``MarkdownTemplateInput``
- ``MarkdownTemplateLimits``
- ``RenderedMarkdownTemplate``
- ``MarkdownTemplateError``
