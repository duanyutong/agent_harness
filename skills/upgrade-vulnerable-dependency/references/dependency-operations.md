# Dependency Resolver Operations

Consult this reference when selecting the package manager's native upgrade command. The workflow's advisory evidence, selected target and compatibility constraints govern the actual arguments; these examples do not select a version or authorise unrelated upgrades.

| Package manager | Native command example      |
| --------------- | --------------------------- |
| npm             | `npm update`                |
| pnpm            | `pnpm up`                   |
| Yarn            | `yarn up`                   |
| Bundler         | `bundle update`             |
| uv              | `uv lock --upgrade-package` |
| Poetry          | `poetry update`             |
| Cargo           | `cargo update -p`           |
| Go              | `go get`                    |

Use the package manager and version established by the repository. Inspect its installed help or current official documentation for target-version, manifest and lockfile options. Scope the operation to the selected package or necessary parent dependency; a command without suitable arguments may update additional packages.
