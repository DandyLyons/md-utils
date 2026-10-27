"""Check the skill's local links and execute its complete authoring examples.

This audit harness extracts examples from the references into isolated
project-local fixtures, then runs a built CLI against valid and invalid
documents. It checks observable authoring behavior without installing libraries
or modifying real project contracts or documents.
"""

import json
import re
import subprocess
import argparse
import atexit
import shutil
import tempfile
import hashlib
import shlex
from pathlib import Path

repo = Path(__file__).resolve().parents[1]
skill = repo / "skill/markdown-utilities/skills/markdown-utilities"
parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument("--cli", type=Path, default=repo / ".build/debug/md-utils")
cli = parser.parse_args().cli.resolve()
(repo / "tmp").mkdir(exist_ok=True)
fixture = Path(tempfile.mkdtemp(prefix="skill-examples-", dir=repo / "tmp"))
atexit.register(shutil.rmtree, fixture)


def run(*args, expected=0, input_text=None, working_directory=None):
    result = subprocess.run([str(cli), *args], cwd=working_directory or fixture, text=True, capture_output=True, input=input_text)
    if result.returncode != expected:
        raise AssertionError(f"{args}: expected {expected}, got {result.returncode}\n{result.stdout}\n{result.stderr}")
    print(f"PASS ({expected}): {' '.join(args)}")
    return result.stdout


def blocks(name, language):
    content = (skill / "references" / name).read_text()
    return re.findall(r"```" + language + r"\n(.*?)\n```", content, re.S)


# Check local links and all JSON examples before exercising native loaders.
for path in skill.rglob("*.md"):
    for target in re.findall(r"\]\(([^)]+)\)", path.read_text()):
        if "://" not in target and not target.startswith("#"):
            assert (path.parent / target.split("#")[0]).exists(), (path, target)
for name in ("rules.md", "types.md", "schemas.md"):
    for example in blocks(name, "json"):
        json.loads(example)
print("PASS: local reference links and JSON examples")
assert (skill / "SKILL.md").read_bytes() == (repo / "Sources/md-utils/Resources/AgentSkill/SKILL.md").read_bytes()

# Build the standalone project directly from the complete reference examples.
for directory in (".md-utils/types", ".md-utils/rules", ".md-utils/schemas", "Books", "Articles", "People"):
    (fixture / directory).mkdir(parents=True, exist_ok=True)
(fixture / ".md-utils/md-utils.json").write_text('{"configVersion":"0.3.0"}\n')
book = blocks("types.md", "yaml")[0]
(fixture / ".md-utils/types/book.mdtype.yaml").write_text(book + "\n")
(fixture / ".md-utils/rules/books.mdrule.json").write_text(blocks("rules.md", "json")[0] + "\n")
(fixture / ".md-utils/schemas/book.schema.json").write_text(blocks("schemas.md", "json")[0] + "\n")
(fixture / "Books/Dune.md").write_text("---\nkind: book\ntitle: Dune\n---\n# Book\n\n## Synopsis\nA desert story.\n")
run("types", "doctor")
run("types", "check", "Book", "Books/", "--format", "json")
run("rules", "matching", "Books/Dune.md", "--explain")
run("rules", "validate", "books", "--no-index", "--json")

# Reuse the shared-schema form, then confirm an invalid member fails enforcement.
book = book.replace("  schemas:\n    - inline:\n        type: object\n        required: [kind, title]\n        properties:\n          kind: {const: book}\n          title: {type: string, minLength: 1}", "  schemas:\n    - ref: ../schemas/book.schema.json")
(fixture / ".md-utils/types/book.mdtype.yaml").write_text(book + "\n")
run("types", "doctor")
run("types", "check", "Book", "Books/", "--format", "json")
(fixture / "Books/Invalid.md").write_text("---\nkind: book\ntitle: ''\n---\n# Book\n\n## Synopsis\nA story.\n")
run("rules", "validate", "books", "--no-index", "--json", expected=1)
(fixture / "Books/Invalid.md").unlink()

# Load the relationship example with its required target and a reciprocity policy.
article = next(value for value in blocks("types.md", "yaml") if 'name: Article' in value)
(fixture / ".md-utils/types/article.mdtype.yaml").write_text(article + "\n")
(fixture / ".md-utils/types/person.mdtype.yaml").write_text('md-utils-type-schema: "2"\nrequires: [document-relationships]\nname: Person\nversion: "1"\nfrontmatter: {}\nbody: {requirements: [], recommendations: []}\ncontext: {requirements: [], recommendations: []}\nrelationships:\n  spouse:\n    select: [spouse]\n    target: {type: person.mdtype.yaml}\n')
(fixture / ".md-utils/rules/people.mdrule.json").write_text(blocks("rules.md", "json")[3] + "\n")
(fixture / "People/Bob.md").write_text("# Bob\n")
(fixture / "Articles/Example.md").write_text("---\nwritten_by: ['[[People/Bob]]']\n---\n# Example\n")
run("types", "doctor")
run("types", "check", "Article", "Articles/", "--format", "json")
run("rules", "validate", "--no-index")

# Exercise the documented semantic schema and its separate wikilink capability.
semantic = next(value for value in blocks("schemas.md", "yaml") if "recommendedSchemas:" in value)
(fixture / ".md-utils/types/event.mdtype.yaml").write_text('md-utils-type-schema: "2"\nname: Event\nversion: "1"\n' + semantic + '\nbody: {requirements: [], recommendations: []}\ncontext: {requirements: [], recommendations: []}\n')
(fixture / "Event.md").write_text("---\npublished: null\nrelated: ['[[People/Bob]]']\n---\n")
run("types", "doctor")
run("types", "check", "Event", "Event.md", "--format", "json")
policy = next(value for value in blocks("schemas.md", "yaml") if value.startswith("type: string"))
policy_type = 'md-utils-type-schema: "2"\nrequires: [wikilink-constraints]\nname: Linked\nversion: "1"\nfrontmatter:\n  schemas:\n    - inline:\n        type: object\n        properties:\n          link:\n' + "\n".join("            " + line for line in policy.splitlines()) + '\nbody: {requirements: [], recommendations: []}\ncontext: {requirements: [], recommendations: []}\n'
(fixture / ".md-utils/types/linked.mdtype.yaml").write_text(policy_type)
(fixture / "Linked.md").write_text("---\nlink: '[[People/Bob]]'\n---\n")
run("types", "doctor")
run("types", "check", "Linked", "Linked.md", "--format", "json")
(fixture / "Linked.md").write_text("---\nlink: '[[People/Bob.md]]'\n---\n")
run("types", "check", "Linked", "Linked.md", "--format", "json", expected=1)

# Parse skill frontmatter with md-utils' own YAML implementation.
assert "markdown-utilities" in run("fm", "get", "--key", "name", str(skill / "SKILL.md"))
assert "schema authoring" in run("fm", "get", "--key", "description", str(skill / "SKILL.md"))

# Follow installed-skill workflows for batch edits, inspection, and preview/write boundaries.
(fixture / "notes").mkdir()
for name in ("one", "two"):
    (fixture / f"notes/{name}.md").write_text(f"---\ntitle: {name}\n---\n# Intro\n\nOriginal text.\n\n## Next\nMore text.\n")
run("fm", "set", "--key", "author", "--value", "Jane Doe", "notes/")
for name in ("one", "two"):
    assert "Jane Doe" in run("fm", "get", "--key", "author", f"notes/{name}.md")
run("fm", "array", "init", "--key", "tags", "notes/")
assert "Intro" in run("explore", "--tree", "notes/one.md")
assert "Intro" in run("toc", "notes/one.md")
before = (fixture / "notes/one.md").read_bytes()
assert "Replacement" in run("section", "set", "--name", "Intro", "notes/one.md", input_text="Replacement\n")
assert (fixture / "notes/one.md").read_bytes() == before
run("section", "set", "--name", "Intro", "notes/one.md", "--in-place", input_text="Replacement\n")
assert b"Replacement" in (fixture / "notes/one.md").read_bytes()
assert "one" in run("fm", "search", "title == 'one'", "notes/")
assert "Replacement" in run("convert", "to-text", "notes/one.md")
run("convert", "to-csv", "notes/")
run("meta", "read", "notes/one.md")
assert "my-title" in run("slug", "My Title")
run("format", "--bullets-dashes", "notes/one.md")

# Query declarations and compare previewed link conversion with applied output.
run("rel", "out", "Articles/Example.md", "--type", "Article", "--root", "./", "--detail", "evidence", "--json")
(fixture / "notes/one.md").write_text("# Intro\n[[People/Bob]]\n")
before = (fixture / "notes/one.md").read_bytes()
run("links", "convert", "notes/one.md", "--root", "./", "--to", "wiki-link")
assert (fixture / "notes/one.md").read_bytes() == before
run("links", "convert", "notes/one.md", "--root", "./", "--to", "wiki-link", "--in-place")
assert "[[Bob]]" in (fixture / "notes/one.md").read_text()
run("links", "check", "notes/one.md", "--root", "./")
run("links", "backlinks", "People/Bob.md", "--root", "./")
run("index", "update", "notes/")
assert "notes/one.md" in run("index", "query", "SELECT path FROM current_documents")
run("index", "status")

# Render named template input and inspect an experimental OKF scaffold.
(fixture / "report.knap").write_text("{{ title | h1 }}\n")
(fixture / "data.json").write_text('{"title":"Report"}')
assert "# Report" in run("template", "render", "--template", "report.knap", "--data", "data.json")
run("config", "init", "--root", "legacy/")
run("config", "migrate", "--config", "legacy/.md-utils/md-utils.json", "--to", "0.3.0", "--dry-run")
assert json.loads((fixture / "legacy/.md-utils/md-utils.json").read_text())["configVersion"] == "0.2.0"
run("okf", "init", "knowledge/")
run("okf", "report", "knowledge/")

# Follow the durable-draft guide, including a stale-source refusal and renewed application.
# Use an independent collection: general draft mutation currently rejects loaded
# relationship contracts without collection context (tracked in the audit).
fixture = fixture / "draft-project"
for directory in (".md-utils/types", ".md-utils/rules", "notes"):
    (fixture / directory).mkdir(parents=True, exist_ok=True)
(fixture / ".md-utils/md-utils.json").write_text('{"configVersion":"0.3.0"}')
server = blocks("mutations.md", "yaml")[0]
(fixture / ".md-utils/server").mkdir()
(fixture / ".md-utils/server/server.yaml").write_text(server + "\n")
(fixture / ".md-utils/types/note.mdtype.json").write_text(json.dumps({
    "md-utils-type-schema": "1", "name": "Note", "version": "1",
    "frontmatter": {}, "body": {"requirements": [], "recommendations": []},
    "context": {"requirements": [], "recommendations": []},
}))
(fixture / ".md-utils/rules/notes.mdrule.json").write_text(json.dumps({
    "name": "notes", "match": {"paths": ["notes/**/*.md"]}, "types": "note.mdtype.json",
}))
source = "---\ntitle: Old\n---\n# Note\nBody\n"
note = fixture / "notes/one.md"
note.write_text(source)
(fixture / "edit.json").write_text('{"frontmatter":{"set":{"title":"New"}}}')
draft = json.loads(run("index", "draft", "add", "notes/one.md", "--resource", "notes",
                       "--revision", hashlib.sha256(source.encode()).hexdigest(), "--patch-file", "edit.json"))
draft_id = draft["id"]
run("index", "apply", draft_id, "--dry-run", "--format", "jsonl")
assert note.read_text() == source
note.write_text(source + "External edit\n")
run("index", "apply", draft_id, expected=1)
assert "External edit" in note.read_text()
note.write_text(source)
run("index", "apply", draft_id)
assert "title: New" in note.read_text()
run("index", "draft", "discard", draft_id)

# Record the audit's known relationship-context limitation without weakening contracts.
shutil.copyfile(fixture.parent / ".md-utils/types/person.mdtype.yaml",
                fixture / ".md-utils/types/person.mdtype.yaml")
baseline = note.read_bytes()
draft = json.loads(run("index", "draft", "add", "notes/one.md", "--resource", "notes",
                       "--revision", hashlib.sha256(baseline).hexdigest(), "--patch-file", "edit.json"))
diagnostics = run("index", "apply", draft["id"], "--dry-run", "--format", "jsonl", expected=1)
assert "relationship.context.unavailable" in diagnostics
assert note.read_bytes() == baseline
run("index", "draft", "discard", draft["id"])

# Exercise the survey workflow independently of validation findings. Explicit
# index publication may fail on malformed input while still retaining queryable
# extraction evidence; snapshot surveying must not read the removed sources.
survey_notes = fixture / "survey-notes"
survey_notes.mkdir()
(survey_notes / "one.md").write_text("---\nstatus: draft\ntags: [swift, swift]\n---\n")
(survey_notes / "two.txt").write_text("---\nstatus: published\n---\n")
(survey_notes / "bad.md").write_text("---\ntags: [broken\n---\n")
survey = json.loads(run("survey", "survey-notes/", "--metrics", "coverage,keys", "--format", "json", "--no-index"))
assert survey["complete"] and survey["coverage"]["files"] == 3
assert survey["coverage"]["malformed"] == 1
values = json.loads(run("survey", "values", "status", "survey-notes/", "--format", "json"))
assert values["metrics"]["values"]["total"] == 2
run("survey", "malformed-fm", "survey-notes/", "--fm-format", "yaml")
run("survey", "types", "survey-notes/")
run("survey", "standards", "survey-notes/", expected=1)
run("index", "update", "survey-notes/", "--include-non-md", expected=1)
shutil.rmtree(survey_notes)
snapshot = json.loads(run("survey", "malformed-fm", "survey-notes/", "--index-only", "--format", "json"))
assert snapshot["complete"] and snapshot["coverage"]["malformed"] == 1

# Verify the discovery reference's actual commands in a separate collection.
# Outputs must supply the names/paths for the next step, and targeted exploration
# must reveal the relevant section without exposing unrelated body content.
discovery = fixture / "discovery"
for directory in [".md-utils/types", ".md-utils/rules", "notes"]:
    (discovery / directory).mkdir(parents=True, exist_ok=True)
(discovery / ".md-utils/md-utils.json").write_text('{"configVersion":"0.3.0"}')
(discovery / ".md-utils/types/book.mdtype.json").write_text(json.dumps({
    "md-utils-type-schema": "1", "name": "Book", "version": "1",
    "frontmatter": {"presence": "required", "schemas": [{"inline": {
        "type": "object", "required": ["title", "Status"],
        "properties": {"Status": {"type": "string", "enum": ["Draft", "Read"]}},
    }}]},
    "body": {"requirements": [], "recommendations": []},
    "context": {"requirements": [], "recommendations": []},
}))
(discovery / ".md-utils/rules/books.mdrule.json").write_text(json.dumps({
    "name": "books", "match": {"paths": ["notes/**"]}, "types": "book.mdtype.json",
}))
(discovery / "notes/example.md").write_text(
    "---\ntitle: Example\nStatus: Read\n$md-utils:\n  typeHints: [Book]\n---\n"
    "# Example\n\nSee [[missing]].\n\n## Lifecycle\n\n"
    "Draft means reading is unfinished. Read means reading is complete.\n\n"
    "### History\n\nA previous status.\n\n## Other material\n\n"
    "This section is unrelated to the lifecycle question.\n"
)
(discovery / "notes/draft.md").write_text("---\nStatus: Draft\n---\n# Unfinished\n")
discovery_before = {path: path.read_bytes() for path in discovery.rglob("*") if path.suffix in {".md", ".json"}}
discovery_outputs = {}
for block in blocks("discovery-workflows.md", "sh"):
    for line in block.splitlines():
        if not line.startswith("md-utils "):
            continue
        arguments = shlex.split(line)[1:]
        status = 1 if arguments[:2] in [["types", "check"], ["links", "check"]] else 0
        discovery_outputs[tuple(arguments)] = run(*arguments, expected=status, working_directory=discovery)
assert all(word in discovery_outputs[("survey", "notes/")] for word in ["Status", "Book", "books"])
assert "Read" in discovery_outputs[("survey", "values", "Status", "notes/")]
assert "example.md: true" in discovery_outputs[("fm", "has", "--key", "Status", "notes/", "--include-non-md")]
assert "Book" in discovery_outputs[("types", "verify", "notes/example.md", "--include-confirmed")]
assert "draft.md" in discovery_outputs[("survey", "type-matches", "notes/", "--type", "Book")]
assert "title" in discovery_outputs[("types", "check", "Book", "notes/draft.md")]
assert "books" in discovery_outputs[("rules", "matching", "notes/example.md", "--explain")]
expanded = discovery_outputs[("explore", "notes/example.md", "--expand", "Lifecycle")]
assert "Draft means reading is unfinished" in expanded
assert "This section is unrelated" not in expanded
assert "unresolved" in discovery_outputs[("rel", "out", "notes/example.md", "--root", ".", "--detail", "evidence", "--json")]
for arguments in [
    ["survey", "keys", "notes/"], ["survey", "uncovered", "notes/"],
    ["survey", "overlaps", "notes/"], ["survey", "coverage", "notes/"],
    ["survey", "malformed-fm", "notes/"], ["survey", "notes/", "--format", "json"],
    ["survey", "notes/", "--format", "json-pretty"],
    ["explore", "notes/example.md", "--tree-section-title", "Lifecycle"],
    ["explore", "notes/example.md", "--expand-frontmatter"],
]:
    run(*arguments, working_directory=discovery)
run("rules", "validate", "books", expected=1, working_directory=discovery)
heading_line = next(index for index, line in enumerate((discovery / "notes/example.md").read_text().splitlines(), 1) if line == "## Lifecycle")
assert "Draft means" in run("explore", "notes/example.md", "--expand-line", str(heading_line), working_directory=discovery)
assert all(path.read_bytes() == content for path, content in discovery_before.items())
assert not (discovery / ".md-utils/index.sqlite").exists()

# Export from bundled resources, with no dependence on canonical files at the destination.
run("agents", "skill", "--output-directory", "installed/")
expected = {p.relative_to(skill): p.read_bytes() for p in skill.rglob("*") if p.is_file()}
installed = fixture / "installed"
actual = {p.relative_to(installed): p.read_bytes() for p in installed.rglob("*") if p.is_file()}
assert actual == expected
run("agents", "skill", "--output-directory", "installed/", expected=1)
assert run("agents", "skill") == (skill / "SKILL.md").read_text()

# Relocate the binary and its resource bundles. A marker in the relocated bundle
# proves lookup uses installed resources instead of an absolute build-tree fallback.
runtime = fixture / "runtime"
runtime.mkdir()
shutil.copy2(cli, runtime / "md-utils")
for resource in cli.parent.iterdir():
    if resource.is_dir() and resource.suffix in (".bundle", ".resources"):
        shutil.copytree(resource, runtime / resource.name)
installed_entry = next(runtime.rglob("AgentSkill/SKILL.md"))
installed_entry.write_text(installed_entry.read_text() + "\nRelocated bundle probe.\n")
cli = runtime / "md-utils"
assert "Relocated bundle probe." in run("agents", "skill")
run("agents", "skill", "--output-directory", "relocated-export/")
assert "Relocated bundle probe." in (fixture / "relocated-export/SKILL.md").read_text()
assert (fixture / "relocated-export/references/rules.md").read_bytes() == expected[Path("references/rules.md")]
print("All installed-skill example workflows passed")
