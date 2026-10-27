# Distribution and lifecycle

## Source basis

Adapted from [installation](https://bettercli.org/design/distribution/installation/),
[self-executing installers](https://bettercli.org/design/distribution/self-executing-installer/),
[auto-updating](https://bettercli.org/design/distribution/auto-updating-cli/),
[application lifecycle](https://bettercli.org/design/cli-application-lifecycle/),
[versioning](https://bettercli.org/design/versioning/), and
[code signing](https://bettercli.org/how-to/sign-cli-executable/).
Several sections are incomplete. Provider prices, signing commands, platform
requirements, and available package tooling must be checked in current official
documentation; no old upstream claim about them is a maintained instruction here.

## Choose channels for the audience

The user's machine and installed version remain under their control. Users may
stay on an old version for years, use mirrors, lack administrative rights, or
switch among multiple installations. Evaluate the full lifecycle before selecting
a convenient one-line installation method.

| Channel | Useful fit | Responsibilities and tradeoffs |
| --- | --- | --- |
| Source build | Technical users and custom platforms | Reproducible instructions, dependencies, version identity, PATH setup |
| Prebuilt archive | Minimal runtime/toolchain requirements | Platform matrix, resources, verification, manual upgrade/removal |
| Language package tooling | Users already in that ecosystem | Extra runtime burden, resolver policies, package lifecycle |
| OS package tooling | Managed installation and upgrades | Platform conventions, manifests, permissions, release coordination |
| Integration/plugin | IDE, CI, or domain workflow | Wrapper compatibility, host UI and update ownership |
| Container image | CI and isolated workloads | Tags/digests, filesystem access, runtime availability, image updates |
| Custom installer | Specific setup needs across environments | Own discovery, verification, upgrade, rollback, and removal behavior |

Supporting several channels is possible; start with justified ones. Surveying
upstream package-manager examples does not authorize installing tools. Respect
local manager restrictions and minimum release-age policies.

Document supported OS/architecture/runtime combinations, dependencies, locations,
verification, exact-version selection, upgrade/downgrade, and removal of caches
and settings. Avoid claiming universal cross-platform support because a language
or package manager is portable.

## Version and migrate intentionally

SemVer is broadly compatible with distribution ecosystems, but retain an approved
project scheme. Define whether users select exact versions, major versions, or
ranges, and how prereleases are handled. Build metadata can identify a date or
commit; extension: do not use it as ordered release precedence.

Version configuration and persistent state where needed. Plan both old data read
by a new binary and new data encountered after downgrade. Explain unsupported
future formats rather than destroying them. Distinguish CLI artifact versions
from configuration/schema versions when the product evolves them independently.

## Updates must respect installation ownership

An updater should respect package managers, local mirrors, pinned versions, and
users who decline upgrades. Do not overwrite a managed executable through an
unrelated channel. Treat breaking updates differently from compatible fixes;
interactive confirmation is not a complete strategy for unattended installations.

Consider simpler update notices before implementing auto-update. Keep notices out
of machine-readable output and avoid adding a blocking network dependency to
every invocation (extensions). Extensible clients and dynamic plugins are optional
architectures, not permission to download and run code during normal work.

## Custom installer decisions

Downloaded shell installers hand control to remote content and take on lifecycle
responsibilities that a package manager might otherwise provide. If designing
one, offer an alternative channel, an explicit version and destination, inspectable
versioned scripts, clear dependency/platform checks, and actionable failures.
Handle an already installed newer, older, or prerelease version deliberately.

Upstream suggests putting the installer body in a function to reduce risks from
partial downloads; this is not authentication or a complete safety guarantee.
Extension: verify fetched artifacts before execution and avoid partial installation
state. Test upgrades and failures, not only a clean installation. Do not execute
an upstream installer while merely reviewing its design.

## Signing and release evidence

Signing, checksums, dependency inventories/SBOMs, and predictable builds address
different concerns. Extension: a checksum fetched with an artifact detects
corruption but does not alone authenticate the publisher. Describe the verification
mechanism and trust source accurately.

For actual signing work, consult current Apple, Microsoft, or relevant Linux/
Sigstore documentation. Plan certificate/key lifecycle and release verification;
network-dependent signing/notarization can fail. Avoid copying historical price or
host-version claims from the source article.

## Verification (extension)

Use clean environments to test supported installation channels, version identity,
bundled resources, runtime dependencies, upgrade, downgrade, and uninstall.
Exercise interruption, permission denial, unavailable download servers, and
verification failure where applicable. Keep publication and real installations
within the user's authorization; design approval is not release approval.
