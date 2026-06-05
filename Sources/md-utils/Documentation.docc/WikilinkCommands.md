# Wikilink Commands

Inspect Obsidian-style wikilinks in Markdown files.

## Overview

The `links` command group scans Markdown content for wikilinks, resolves them against a vault root, reports broken or ambiguous links, and finds backlinks to a target note.

Resolution is based on Markdown file names and paths inside the vault. Commands that check link health are intended for automation and can fail when broken or ambiguous links are found.
