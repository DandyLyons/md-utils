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
mkdir notes/
printf '%s\n' '---' 'title: Smoke' '---' '# Packaged runtime' 'uniqueprobe' > notes/sample.md
md-utils body notes/sample.md > body.md
grep -q '# Packaged runtime' body.md
! grep -q 'title: Smoke' body.md
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
