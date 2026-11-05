#!/usr/bin/env python3
"""Execute the skill's template tutorial and syntax examples with a built CLI.

This standard-library-only harness extracts the published Markdown examples into
an isolated project under tmp/, runs their creation and rendering commands, and
checks saved contents, conformance, defaults and refusal behavior. It also renders
the syntax reference's snippets to catch unsupported syntax or filter names.
Fixtures are removed on exit; real project definitions and documents are untouched.
"""

import argparse
import json
from pathlib import Path
import re
import shlex
import subprocess
import tempfile


ROOT = Path(__file__).resolve().parents[1]
REFERENCES = ROOT / "skill/markdown-utilities/skills/markdown-utilities/references"


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--cli", type=Path, required=True)
    args = parser.parse_args()
    cli = args.cli.resolve()
    tutorial = (REFERENCES / "templates.md").read_text()
    syntax = (REFERENCES / "knap-syntax.md").read_text()
    (ROOT / "tmp").mkdir(exist_ok=True)

    with tempfile.TemporaryDirectory(prefix="skill-templates-", dir=ROOT / "tmp") as temporary:
        project = Path(temporary)

        def run(*arguments, succeeds=True):
            result = subprocess.run([str(cli), *arguments], cwd=project, text=True, capture_output=True)
            assert (result.returncode == 0) == succeeds, (arguments, result.returncode, result.stdout, result.stderr)
            return result.stdout

        def example(heading, language):
            section = tutorial.split(heading + "\n", 1)[1]
            return re.search(r"```" + language + r"\n(.*?)\n```", section, re.S).group(1) + "\n"

        def write(path, content):
            destination = project / path
            destination.parent.mkdir(parents=True, exist_ok=True)
            destination.write_text(content)

        def commands(heading):
            # Execute the actual documented arguments without invoking a shell.
            for line in example(heading, "sh").splitlines():
                if line.startswith("md-utils "):
                    yield shlex.split(line)[1:]

        # Build the project directly from the tutorial, keeping names and refs intact.
        (project / "Books").mkdir()
        write(".md-utils/md-utils.json", example("### 1. Enable standalone rules", "json"))
        write(".md-utils/types/book.mdtype.yaml", example("### 2. Define the Book type and its template input", "yaml"))
        write(".md-utils/types/book.knap", example("### 3. Write the Knap document template", "knap"))
        write(".md-utils/rules/books.mdrule.json", example("### 4. Define the books rule and destination", "json"))
        write("inputs/dune.json", example("### 5. Supply JSON", "json"))
        for command in commands("### 6. Check definitions, preview, create and validate"):
            output = run(*command)
            if "--dry-run" in command:
                assert not list((project / "Books").iterdir())
                assert "Would create" in output and "conforms" in output
        saved = project / "Books/Dune.md"
        original = saved.read_bytes()
        assert "# Dune" in saved.read_text() and "Not reviewed yet." in saved.read_text()
        assert "science-fiction" in run("fm", "get", "--key", "tags", "Books/Dune.md")
        print("PASS: extracted first-use workflow creates a conforming file with defaults and correct path")

        for command in commands("### Choose a filename or a different destination"):
            assert "Would create" in run(*command)
        assert [path.name for path in (project / "Books").iterdir()] == ["Dune.md"]

        # Prove safety/conformance boundaries instead of just testing successful rendering.
        base = ("rules", "new", "--rule", "books", "--value", "./inputs/dune.json")
        run(*base, "--filename", "Dune.md", succeeds=False)
        assert saved.read_bytes() == original
        write("inputs/invalid.json", '{"title":"Invalid"}')
        run("rules", "new", "--rule", "books", "--value", "inputs/invalid.json", "--filename", "Invalid.md", succeeds=False)
        assert not (project / "Books/Invalid.md").exists()
        write("inputs/quoted.json", json.dumps({"title": 'No: "false"', "author": "false", "synopsis": "Text."}))
        run("rules", "new", "--rule", "books", "--value", "inputs/quoted.json", "--filename", "Quoted.md")
        run("types", "check", "Book", "Books/Quoted.md")
        assert "false" in run("fm", "get", "--key", "author", "Books/Quoted.md")
        run("rules", "validate", "--no-index")
        print("PASS: collisions and invalid input refuse writes; YAML retains punctuation and string kinds")

        # Conformance is deliberately advisory during creation, then enforced by validation.
        template = project / ".md-utils/types/book.knap"
        template_source = template.read_text()
        template.write_text(template_source.split("## Review", 1)[0])
        output = run(*base, "--filename", "Advisory.md")
        assert "does not conform (advisory)" in output
        run("types", "check", "Book", "Books/Advisory.md", succeeds=False)
        run("rules", "validate", "--no-index", succeeds=False)
        (project / "Books/Advisory.md").unlink()
        template.write_text("{% if %}")
        run(*base, "--filename", "Broken.md", succeeds=False)
        assert not (project / "Books/Broken.md").exists()
        template.write_text(template_source)
        print("PASS: advisory creation requires separate validation; broken templates refuse writes")

        # Execute the documented batch, checking preview and both resulting files.
        write("inputs/books.json", example("### Import several records into the same convention", "json"))
        for command in commands("### Import several records into the same convention"):
            run(*command)
            if "--dry-run" in command:
                assert not (project / "Books/Foundation.md").exists()
        for name in ("Foundation", "The Dispossessed"):
            assert (project / f"Books/{name}.md").is_file()
        print("PASS: extracted bulk workflow and validation")

        # Execute both standalone rendering modes and inspect their meaningful output.
        heading = "### Render a report without creating a type or rule"
        write("report.knap", example(heading, "knap"))
        write("report.json", example(heading, "json"))
        for command in commands(heading):
            output = run(*command)
            if "--output" not in command:
                assert "# Weekly review" in output and "- [ ] Check metadata" in output
        assert "Imported notes" in (project / "weekly-review.md").read_text()
        heading = "### Let md-utils serialize frontmatter separately"
        write("meeting.knap", example(heading, "knap"))
        write("meeting.json", example(heading, "json"))
        output = run(*next(commands(heading)))
        assert output.startswith("---\n") and "# Planning" in output
        assert "- [ ] Review the template" in output and "attendees:" in output
        print("PASS: extracted report and body-mode meeting scenarios")

        # Use one rich input to execute every complete expression/block in the cheatsheet.
        values = {
            "title": " old Example ", "subtitle": "Subtitle", "First name": "Ada",
            "author": {"name": "Author"}, "authors": [{"name": "Author"}],
            "metadata": {"article:section": "Books"}, "timestamps": ["00:01"],
            "tags": ["fiction", "reference"], "tasks": ["Review"],
            "people": [{"name": "Ada", "role": "Writer", "active": True}],
            "rows": [{"name": "Ada"}], "summary": "Summary", "status": "draft",
            "count": 0, "review": "Review", "source": "let value = 1",
            "content": "Content", "footer": "Footer", "related": ["Book"],
            "csv_text": "one,two", "expenses": [{"amount": 2}], "price": 3,
            "created": "2026-11-05", "rating": 4.123, "published": False,
            "frontmatter": {"title": "Meeting"}, "data": {"summary": "Summary"},
        }
        write("syntax.json", json.dumps(values))
        snippets = re.findall(r"```knap\n(.*?)\n```", syntax, re.S)
        for content in (syntax, tutorial.split("## Common Knap syntax\n", 1)[1].split("## Other scenarios\n", 1)[0]):
            snippets += [value.replace(r"\|", "|") for value in re.findall(r"`([^`\n]+)`", content)
                         if value.startswith(("{{", "{%", "{#")) and value != "{% tag %}"]
        for snippet in snippets:
            write("syntax.knap", snippet + "\n")
            run("template", "render", "--template", "syntax.knap", "--data", "syntax.json")
        print(f"PASS: {len(snippets)} fenced and inline Knap syntax examples render")

        # Check representative semantics as well as parser/filter availability.
        cases = {
            '{{ count ?? "fallback" }}': "fallback",
            '{{ published ?? "fallback" }}': "fallback",
            '{{ people | map:"name" | join:", " }}': "Ada",
            '{% set label = title | trim %}{{ label | upper }}': "OLD EXAMPLE",
            '{% for person in people %}{{ loop.index }}. {{ person.name }}{% endfor %}': "1. Ada",
            '{% if status == "published" %}Published{% elseif status == "draft" %}Draft{% else %}Other{% endif %}': "Draft",
            'Before{# author note #}After': "BeforeAfter",
        }
        for snippet, expected in cases.items():
            write("syntax.knap", snippet)
            assert run("template", "render", "--template", "syntax.knap", "--data", "syntax.json") == expected
        print("PASS: fallback truthiness, filter chains, assignments, loops, elseif and comment semantics")


if __name__ == "__main__":
    main()
