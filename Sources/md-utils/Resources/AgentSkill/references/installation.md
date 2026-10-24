# Installing and exporting the skill

Install the md-utils CLI separately. The skill is documentation, not the executable.
`md-utils agents install` prints instructions without installing anything.

```bash
# Create only the parent, then export a new complete skill directory.
mkdir -p ~/.claude/skills/
md-utils agents skill --output-directory ~/.claude/skills/markdown-utilities/
```

Use your assistant's own skill parent directory if different. Export includes
`SKILL.md` and every file under `references/`, preserving relative links. The parent
must exist and the destination must not exist, even if empty. Existing installations
and symlinks are not overwritten. Export has no network dependency and uses the
CLI's bundled version. On I/O failure, inspect any partial output and retry at a
new path. To upgrade, export to a fresh directory, compare, and deliberately replace
the old installation after preserving any local customization.

Without options, `md-utils agents skill` prints only the entrypoint. Saving that
output alone is insufficient for installation. For project knowledge systems,
export first, then upload the entrypoint plus relevant reference files. If the
system does not preserve folders/relative links, load references by filename.

From a repository checkout, copy the complete
`skill/markdown-utilities/skills/markdown-utilities/` folder. A skills-directory
installer must likewise retain references. Verify that opening a reference from
the installed entrypoint succeeds. Third-party installer availability is not a
guarantee supplied by md-utils; the bundled export is the supported offline path.

`agents printConfigSchema` prints the bundled default project-config schema; it
does not print a user frontmatter schema or infer a config version from disk.
