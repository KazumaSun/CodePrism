# CodePrism

**3-agent parallel dev orchestrator for Cursor** — run Melchior, Balthasar, and Caspar in parallel git worktrees, cross-review each other's work, and synthesize a single plan.

Each agent focuses on a complementary dimension (correctness, maintainability, and operational efficiency). CodePrism splits implementation concerns across three personas before merging insight through a designated rapporteur.

## Concept

| Agent | Persona | Focus |
|-------|---------|--------|
| **Melchior** | Correctness | Requirements, tests, regression, edge cases |
| **Balthasar** | Sustainability | Maintainability, conventions, minimal diffs |
| **Caspar** | Performance & ops | Efficiency, resource use, operational cost |

Pipeline: **implement** (parallel) → **review** (3×2 cross-review, optional anonymization) → **synthesize** (`SYNTHESIS.md`) → **apply** (optional cherry-pick/merge).

## Quickstart

```bash
git clone <this-repo> CodePrism
cd CodePrism
./scripts/install.sh
export PATH="$(pwd)/bin:$PATH"

cd /path/to/your-project
codeprism init
codeprism run --task "Add feature X" --base main
```

Dry-run without side effects:

```bash
codeprism --dry-run implement --task "Try it" --repo .
```

## Commands

| Command | Description |
|---------|-------------|
| `init` | Create `.codeprism/` and example `.codeprism.yaml` in target repo |
| `run` | Full pipeline: implement → review → synthesize |
| `implement` | Create worktrees and run three agents in parallel |
| `review` | Collect diffs and run cross reviews |
| `synthesize` | Rapporteur produces synthesis |
| `apply` | Apply chosen agent branch (`--strategy cherry-pick\|merge`, `--agent`) |
| `status` | Session metadata and backend detection |
| `collect` | Snapshot worktree diffs (after manual edits) |
| `tmux` | 4-pane tmux layout for main + three agents |
| `clean` | Remove worktrees for `--session` |

Global flags: `--dry-run`, `--session`, `--repo`, `--base`, `--task`, `--task-file` / `-f`.

## Task files (YAML / Markdown)

Long tasks can live in a file instead of `--task "..."`.

```bash
# Explicit file
codeprism run --task-file examples/tasks/github-profile.md --repo /path/to/KazumaSun

# Shorthand
codeprism run -f .codeprism/task.yaml --repo .

# Default: if no --task / --task-file, reads (first match):
#   .codeprism/task.md  |  .codeprism/task.yaml  |  .codeprism/task.yml
codeprism run --repo .
```

`codeprism init` copies `examples/tasks/.codeprism.task.example.yaml` → `.codeprism/task.yaml` for editing.

### YAML format

```yaml
title: Short label for logs
base: main          # optional; overrides default base unless you pass --base

task: |
  Multiline prompt for all three agents.
```

`prompt:` is an alias for `task:`.

### Markdown format

Optional YAML frontmatter + body (body is the task if `task:` is omitted):

```markdown
---
title: My feature
base: main
---

# Instructions
Write the full task description here.
```

See [examples/tasks/](examples/tasks/) for samples.

## Configuration

Defaults live in `config/default.yaml`. Per-repo overrides: `.codeprism.yaml` (see `.codeprism.example.yaml`).

- `agent.backend`: `auto` | `cursor-cli` | `cursor-sdk` | `manual`
- `agent.model`: e.g. `composer-2.5`
- `review.anonymize`: `true` hides agent names in review targets
- `synthesis.rapporteur`: default `melchior`
- `worktree.prefix`: branch prefix (default `codeprism`)

## Worktrees & branches

For session `<id>` and agent `<name>`:

- Worktree: `<repo>/.codeprism-worktrees/<id>/<name>/` (inside the target repo)
- Branch: `codeprism/<id>/<name>`
- Session data: `<repo>/.codeprism/sessions/<id>/` (`meta.json`, `worktrees.json`, diffs, prompts)

## Agent backends

**Auto** (default):

1. **cursor-cli** — `cursor agent -p` with `--workspace`; uses `--output-format json` when supported
2. **cursor-sdk** — `optional/sdk/run.mjs` when `CURSOR_API_KEY` is set
3. **manual** — writes prompts under the session dir for human execution; use `codeprism collect` afterward

### Optional SDK

```bash
cd optional/sdk && npm install
export CURSOR_API_KEY=...
```

## tmux & Warp

```bash
codeprism tmux --repo /path/to/project
```

Opens a tiled session: main pane + three agent shells. In Warp or other terminals, open the worktree paths from `codeprism status`.

## Limitations

- Lightweight YAML parsing (not a full YAML engine).
- Agent output quality depends on Cursor model and your task description.
- `apply` assumes a clean merge/cherry-pick context; resolve conflicts manually.
- CI runs `shellcheck` on shell sources; runtime tests are minimal.

## Docs

- [Architecture](docs/architecture.md)
- [ワークフロー（日本語）](docs/workflow-ja.md)

## License

MIT — see [LICENSE](LICENSE).
