# md-recipes: community interoperability proposal

Status: recipe design is not finalized and still needs human review, 2026-10-26.
The fixture-first delivery
approach is approved; recipe fields and representation are not. This supersedes
the earlier restriction to purely illustrative recipe examples, without claiming
an implemented or published recipe standard. See [RFC 0005](rfcs/0005-mdstandard.md).

## Existing ecosystems and recommendation

Recommend Schema.org Recipe as the first external interchange vocabulary, with
Nextcloud Cookbook as a concrete application test target. Cooklang is a second
candidate integration and a source of human-authoring ideas. Implement a documented
subset and explicit adapters, not a claim to accept every external representation.

These are domain vocabulary and application research recommendations, not approval
to adopt JSON-LD processing. JSON-LD/YAML-LD integration is deferred by the owner
and is not a prerequisite for this recipe standard. Any concrete application
adapter still needs its own reviewed format and preservation contract.

Research checked 2026-10-25:

- [Schema.org Recipe](https://schema.org/Recipe) supplies ingredient, instruction,
  yield, and timing vocabulary. Its live page is labeled a development version;
  fixture mappings must pin the reviewed vocabulary/profile rather than track it
  silently. [Google's recipe guidance](https://developers.google.com/search/docs/appearance/structured-data/recipe)
  demonstrates JSON-LD usage, but search-result eligibility is a separate consumer
  profile, not the minimum requirements for a personal recipe.
- [Nextcloud Cookbook](https://github.com/nextcloud/cookbook) explicitly stores
  Schema.org-based JSON recipes and documents mobile clients. Its
  [0.11.12 release](https://github.com/nextcloud/cookbook/releases/tag/v0.11.12)
  was published 2026-10-13. This is concrete evidence of maintained application
  use, not proof that all Schema.org values interoperate without adaptation.
- [Cooklang](https://cooklang.org/docs/spec/) embeds ingredients, cookware and
  timers in text instructions. It has documented
  [community channels](https://cooklang.org/contact/) and a
  [CookCLI 0.39.0 release](https://github.com/cooklang/cookcli/releases/tag/v0.39.0)
  published 2026-10-24. Its syntax is not Markdown; supporting it requires an
  explicit parser/serializer, not blind field renaming or arbitrary strategy code.
- [Tandoor's integration matrix](https://docs.tandoor.dev/features/import_export/)
  demonstrates real cross-application exchange and direction-specific support.
  Fixture claims must distinguish import, export, images, and application versions.
- [Open Recipe Format](https://open-recipe-format.readthedocs.io/en/latest/)
  is useful design background, but does not meet our evidenced active-ecosystem
  criterion. Its default-branch tip is
  [8e4b990](https://github.com/techhat/openrecipeformat/commit/8e4b990cbe844cb49e6c6e4d4e5d89fb8b13fcb5)
  dated 2021-01-19; repository API reports last push 2022-10-16, a different metric.
  [Read the Docs](https://app.readthedocs.org/projects/open-recipe-format/) reports
  the linked docs last built over nine years ago. No maintained consuming-app
  ecosystem was established in this review; that is not proof that nobody uses it.

ORF's [reference](https://open-recipe-format.readthedocs.io/en/latest/topics/reference/orf.html)
usefully models ingredient substitutions, per-step notes, attribution, and multiple
yields. Its [walkthrough](https://open-recipe-format.readthedocs.io/en/latest/topics/tutorials/walkthrough.html)
also recognizes nonlinear scaling. I would borrow those concerns, but avoid its
parallel yield/amount arrays and company-registration-style recipe identity as
our initial model. These are design judgments, not interoperability defects proven
against a deployed application.

## First principles

See the [deferred Schema.org research](schema-org-alignment.md) for semantic
bindings, CookAction, and the June 2026 ordering update. Domain observations may
inform later human review; linked-data integration is not part of the current
recipe deliverables. Neither document defines an approved recipe format.

1. A recipe describes a repeatable method; a cooking entry records one attempt.
2. Preserve what the author actually wrote. Ingredients such as “salt to taste”
   and “1–2 small onions” must not require fabricated numeric precision.
3. Order, grouping, and repeated ingredients carry meaning. Do not deduplicate.
4. A yield may be one loaf, twelve biscuits, or four servings. Missing is unknown,
   not one serving; no implicit scaling or unit conversion.
5. Time estimates, dietary labels, nutrition and outcomes are authored claims.
   Validation does not establish culinary accuracy or food safety.
6. Narrative, source attribution, extensions and links are user data. Dropping
   them requires an explicit strategy and visible loss acknowledgment.
7. Each fact has one authoritative representation; do not require users to keep
   editable frontmatter steps and body instructions synchronized.

## Candidate minimal contract

Propose standard-shaped Markdown with YAML frontmatter. Required recipe fields:
stable `id`, nonempty `name`, ordered nonempty `ingredientGroups`, and ordered
nonempty `instructionSections`. Groups may be unnamed; each ingredient has
nonempty `text`; each instruction section has ordered steps with nonempty `text`.
Identifiers survive renaming/moving a file. Exact ID syntax awaits the shared
exchange identity decision; no filename or source URL is sufficient by itself.

Optional fields: description, textual yield, explicitly authored durations,
equipment, author/source attribution, images, tags, and extension data. Nutrition,
structured quantities, scaling rules, and subrecipe ingredients should be later
extensions, not required complexity. Attribution/license information must be
preserved when supplied; no rights are inferred from a successful import.

Candidate representation (illustrative identifier and original sample text):

```yaml
---
id: recipe-soup-example
name: Weeknight lentil soup
yield: 4 bowls
ingredientGroups:
  - name: Soup
    items:
      - text: 1 cup red lentils, rinsed
      - text: 4 cups vegetable stock
      - text: Salt to taste
instructionSections:
  - name: Cook
    steps:
      - text: Combine the lentils and stock in a saucepan.
      - text: Simmer until the lentils are tender; season to taste.
---

## Notes

Use a wider pan when making a larger batch.
```

This prioritizes deterministic structured exchange; the body holds narrative
notes. The main tradeoff is that editing instructions in YAML feels less natural
than a Markdown ordered list. An alternative is authoritative body headings/lists,
but that requires exact rules for sections, nested lists, prose and extraction.
The owner should select the representation before recipe schemas are authored.

Propose a separate cooking-entry rule/type: stable ID, cooking date, and exactly
one reference to a recipe; optional substitutions, observations and personal
rating. Keep observations in its body. No reverse list on the recipe is required.
A relationship references the current recipe unless an explicit revision/snapshot
is preserved; do not imply historical reconstruction from a path link alone.

Recommend the full example standard declares both roles, while permitting an
empty cooking-entry population. Whether recipe-only consumers advertise a subset
or use a separate core standard must be resolved with #192; no profile mechanism
is silently introduced. CookAction is related vocabulary, but cooking-history
interoperability is not claimed for recipe-only applications.

## Interoperability boundary

Propose mappings: `name` to Schema.org `name`, textual ingredients to
`recipeIngredient`, steps/sections to `recipeInstructions`, and yield to
`recipeYield`. Grouping, notes, identity and unsupported extensions need explicit
preservation or loss findings. Plain instruction strings can be wrapped as a
single step, without pretending prose has been segmented accurately.

Start with saved, pinned JSON fixtures from a defined Schema.org/Nextcloud profile.
Do not require live web scraping, remote JSON-LD context execution, or network
access in transformation actions. Support for arbitrary JSON-LD graphs, HTML,
images, and Cooklang requires separately specified built-in operations/adapters.
Versioned application smoke checks supplement, rather than replace, offline
fixtures. No actual interoperability is verified yet.

## Explicitly lossy local adoption

Owner-approved direction: an import strategy may deliberately drop unwanted keys,
provided the user acknowledges the specific loss and absence of a lossless
round-trip guarantee. Recommend binding acknowledgment to reviewed plan/output
hashes and enumerating affected fields/files in Markdown and machine-readable
reports; exact syntax remains open.

Distinguish two cases: dropping optional nutrition can still permit a valid export,
but not reconstruction of the original. Dropping required instructions prevents
conforming export until missing information is supplied. Never fabricate values
or advertise an inverse exporter. A lossy import-only local representation uses
in-transit adoption; it cannot claim at-rest conformance after discarding required
standard obligations. Unknown fields are preserved or rejected unless expressly
covered by acknowledged loss. Backups do not turn a lossy adapter into a lossless one.

## Fixture-first delivery

Before freezing this domain design, review the required fields, instructions
representation, cooking-history boundary, and first external application target.
Then author installable experimental definitions and original example data.
Use a second small journal standard to test generality, not more recipe features.

Plan 0.1.0 (initial), 0.1.1 (identity migration), and 0.2.0 (meaningful structural
change). A candidate change is flat ingredient/step lists to named groups/sections,
wrapping existing lists without inventing groups. These are experimental fixture
releases, not invented public release history; exact contracts need owner approval.

Local configurations: direct adoption under different folders, stronger local
requirements, renamed/restructured fields with both adapters, and an explicit
lossy import-only variant. Test records with repeated ingredients, fractions,
unquantified amounts, multiple sections, optional data, unknown extensions,
broken links, and contradictory local requirements. Fixture expectations precede
implementation; unimplemented scenarios are tracked as such, never counted as passes.
