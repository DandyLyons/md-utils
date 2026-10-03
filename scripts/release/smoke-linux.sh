#!/usr/bin/env bash
set -euo pipefail
ulimit -c 0
version="${1:?Expected artifact version}"
test "$(md-utils --version)" = "$version"
md-utils --help > help.txt
grep -q 'Markdown' help.txt
md-utils agents skill > skill.md
grep -q 'markdown-utilities' skill.md
md-utils config schema > schema.json
grep -q '"properties"' schema.json
# The first Linux prerelease rejected even config init's empty rules array.
md-utils config init --root empty-config/
md-utils rules list --config empty-config/.md-utils/md-utils.json > empty-config.txt
grep -q 'No rules configured' empty-config.txt
# Exercise config loading and JSON scalar validation in the shipped release
# executable, in addition to the builder's debug test suite.
mkdir -p config-probe/.md-utils/schemas/ config-probe/notes/
cat > config-probe/.md-utils/md-utils.json <<'JSON'
{"configVersion":"0.2.0","schemaDirectory":".md-utils/schemas/","rules":[
  {"name":"required","match":{"paths":["notes/**"]},"checks":[{"type":"frontmatterSchema","schema":"note.schema.json","frontmatterRequired":true}]},
  {"name":"optional","match":{"paths":["notes/**"]},"checks":[{"type":"frontmatterSchema","schema":"note.schema.json","frontmatterRequired":false}]}
]}
JSON
cat > config-probe/.md-utils/schemas/note.schema.json <<'JSON'
{"type":"object","required":["enabled","disabled","zero","one","fraction","empty"],"properties":{
  "enabled":{"type":"boolean","const":true},"disabled":{"type":"boolean","enum":[false]},
  "zero":{"type":"integer","const":0},"one":{"type":"number","const":1},
  "fraction":{"type":"number","const":1.5},"empty":{"type":"null"}
}}
JSON
printf '%s\n' '---' 'enabled: true' 'disabled: false' 'zero: 0' 'one: 1' 'fraction: 1.5' 'empty: null' '---' '# Scalars' > config-probe/notes/scalars.md
(
    cd config-probe/
    md-utils rules list > rules.txt
    grep -q 'required' rules.txt
    grep -q 'optional' rules.txt
    md-utils rules validate --include-ok > valid.txt
    grep -q 'Validated 2 file-rule match(es)' valid.txt
    # A number must never satisfy a boolean schema.
    printf '%s\n' '---' 'enabled: 1' 'disabled: 0' 'zero: 0' 'one: 1' 'fraction: 1.5' 'empty: null' '---' '# Invalid scalars' > notes/scalars.md
    if md-utils rules validate > invalid.log 2>&1; then
        echo 'Boolean schema unexpectedly accepted numbers' >&2; exit 1
    fi
    grep -q 'boolean' invalid.log
    # A boolean must never satisfy an integer or number schema.
    printf '%s\n' '---' 'enabled: true' 'disabled: false' 'zero: false' 'one: true' 'fraction: 1.5' 'empty: null' '---' '# Invalid scalars' > notes/scalars.md
    if md-utils rules validate > invalid.log 2>&1; then
        echo 'Numeric schema unexpectedly accepted booleans' >&2; exit 1
    fi
    grep -Eq 'integer|number' invalid.log
)
mkdir notes/
printf '%s\n' '---' 'title: Smoke' '---' '# Packaged runtime' 'uniqueprobe' > notes/sample.md
md-utils body notes/sample.md > body.md
grep -q '# Packaged runtime' body.md
if grep -q 'title: Smoke' body.md; then
    echo 'Body extraction retained frontmatter' >&2; exit 1
fi
printf '%s\n' '{{ frontmatter.title | h1 }}' '{{ data.message }}' > template.knap
printf '%s\n' '{"frontmatter":{"title":"Archive template"},"data":{"message":"Knap works"}}' > data.json
md-utils template render --template template.knap --data data.json --output rendered.md
grep -q '# Archive template' rendered.md
grep -q 'Knap works' rendered.md
md-utils index update ./notes/
test -s .md-utils/index.sqlite
test "$(md-utils index query 'SELECT path FROM current_documents' --format jsonl)" = '{"path":"notes/sample.md"}'
md-utils index search enable
test "$(md-utils index query "SELECT count(*) AS matches FROM documents_fts WHERE documents_fts MATCH 'uniqueprobe'" --format jsonl)" = '{"matches":1}'
# Prove resource checks cannot succeed using a resource bundle in a build tree.
mv /opt/md-utils/md-utils_md-utils.resources /opt/md-utils/hidden-cli-resources/
if md-utils agents skill > missing-cli.log 2>&1; then
    echo 'CLI resource test unexpectedly passed without its bundle' >&2; exit 1
fi
mv /opt/md-utils/hidden-cli-resources/ /opt/md-utils/md-utils_md-utils.resources
mv /opt/md-utils/SwiftKnap_SwiftKnap.resources /opt/md-utils/hidden-knap-resources/
if md-utils template render --template template.knap --data data.json > missing-knap.log 2>&1; then
    echo 'Template test unexpectedly passed without its bundle' >&2; exit 1
fi
mv /opt/md-utils/hidden-knap-resources/ /opt/md-utils/SwiftKnap_SwiftKnap.resources
test "$(md-utils --version)" = "$version"
