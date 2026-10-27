# Help and discovery

## Source basis

Adapted from [CLI Help pages](https://bettercli.org/design/cli-help-page/), the
repository's `content/design/example-help.txt`, and the glossary's
[man page](https://bettercli.org/glossary/manpage/) and
[terminal pagers](https://bettercli.org/glossary/terminal-pagers/) entries.
The autocomplete how-to and framework list are unfinished upstream; implementation
advice for those below is an extension, not a surveyed recipe.

## Make the first screen useful

Answer what the command does, where a newcomer can begin, and where to learn more.
Lead with a concise purpose and explain prerequisite accounts, services, inputs,
or setup. Do not assume users already know the surrounding product.

Use this adaptable order: name/version and purpose; usage; practical examples;
subcommands; options; configuration; further help. A small leaf command may need
only a few sections. Explain the selected command's actual task rather than
repeating the root description on every page.

Generate syntax and option inventories from parser definitions where possible.
Author explanations and examples deliberately, then validate them against the
executable. Generated help cannot guarantee that hand-written descriptions,
defaults, or examples remain correct. Connect short terminal help to longer
tutorials and manuals instead of loading everything into one screen.

## Invocation and mistakes

- Provide conventional help flags and discoverable subcommand help. Explicit help
  should print to stdout and avoid doing work. Better CLI recommends honoring help
  despite other flags; check parser behavior before promising that every malformed
  invocation displays help successfully.
- No-argument invocation may show introductory help or perform a meaningful primary
  action. Preserve an intentional default; showing help is not universal.
- On invalid usage, identify the error first, then offer relevant syntax, nearby
  valid spellings, and more help. Avoid burying a useful hint beneath a full manual.
- Choose strictness consciously. Silent acceptance of misspelled flags can look
  like ignoring intent; overvalidation can reject legitimate unfamiliar paths.
  Suggestions need not execute a guessed command.
- Avoid surprising pager entry. If using a pager, explain navigation and quitting.
  Extension: provide a bypass and keep redirected help free of interactive paging.

## Adaptable example

This fictional interface illustrates structure rather than a specific tool's syntax.
Replace it with verified commands and defaults. Unlike the upstream example, it
has neither an unrelated framework description nor an empty example section.

```text
catalog 1.2.0 — Find documents by title.

USAGE
  catalog find QUERY [--root DIRECTORY] [--json]

EXAMPLES
  catalog find "release notes"
  catalog find "design" --root ./notes/ --json

OPTIONS
  --root DIRECTORY  Search this directory recursively (default: ./).
  --json            Write matching records as JSON to stdout.
  -h, --help        Show help without searching.

CONFIGURATION
  CATALOG_ROOT supplies the root when --root is absent.

MORE HELP
  catalog --help lists commands.
```

Explain mutation/preview behavior, formats, recursive scope, aliases, or prerequisites
where relevant. Do not document features simply because this template has room.

## Verification and supporting formats

Inspect actual root, parent, and changed leaf help after rebuilding when necessary.
Run examples against isolated fixtures. Check narrow terminal wrapping and help
captured to a file. Record observed behavior, not just the intended wording.

Extension: derive completion and generated manpages from the same command model
where supported. Test the advertised shells and treatment of hidden, deprecated,
and value-taking options. Consult current framework documentation; Better CLI's
empty completion how-to supplies no installation recipe.
