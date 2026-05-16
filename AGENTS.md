# AGENTS.md

Operational guide for anyone (human or AI) working in this repo.

## Purpose

CI pipeline that builds a [Miro Custom Shape pack](https://help.miro.com/hc/en-us/articles/20352896814866-Custom-Shapes-for-Diagramming) from [cncf/artwork](https://github.com/cncf/artwork) on demand. The pack itself is **never committed** — it's produced by [.github/workflows/release-pack.yml](.github/workflows/release-pack.yml) and published as a GitHub Release asset.

See [README.md](README.md) for the end-user flow (trigger the workflow, download the zip, upload to Miro).

## Layout

- [scripts/build-pack.sh](scripts/build-pack.sh) — the actual build: clones cncf/artwork, picks one SVG per project, runs SVGO, backfills `viewBox`, zips.
- [.github/workflows/release-pack.yml](.github/workflows/release-pack.yml) — `workflow_dispatch` job that runs the script and publishes a GitHub Release.
- [README.md](README.md) — user-facing usage instructions.
- [.gitignore](.gitignore) — keeps `artwork/`, `dist/`, `node_modules/` out of git.

Anything under `artwork/`, `dist/`, `node_modules/` is transient build state and must stay gitignored. The upstream clone is large and fully reproducible from the script — never commit it.

## How to run anything

Local dry run of the same pipeline CI uses:

```sh
bash scripts/build-pack.sh
```

Output lands in `dist/`. Requirements: `git`, `node` (for `npx svgo`), `zip`.

CI release: GitHub **Actions** → **Release pack** → **Run workflow**.

## Branch naming

Follow the [Conventional Branch](https://conventional-branch.github.io/) spec: `<type>/<short-kebab-description>`, lowercase, hyphen-separated, no trailing slash.

Allowed types:

- `feature/` — new functionality (e.g. `feature/include-archived-projects`)
- `bugfix/` — fix to existing behaviour (e.g. `bugfix/svgo-strips-viewbox`)
- `hotfix/` — urgent fix
- `release/` — release prep
- `chore/` — maintenance, refactors, deps, CI (e.g. `chore/bump-svgo-major`)
- `docs/` — docs-only changes
- `test/` — test-only changes

`main` is protected; never commit directly. Open a PR from a conventional branch.

## Commit conventions

Use [Conventional Commits](https://www.conventionalcommits.org/) for the subject line: `<type>(<scope>): <summary>`. Types match the branch-naming list above (`feat`, `fix`, `chore`, `docs`, `test`, `refactor`).

Every commit must end with both trailers, in this order:

```
Assisted-by: claude-code/<model-id>
Signed-off-by: <Your Name> <your-email>
```

- `Signed-off-by` is the human DCO sign-off — only the human contributor takes this trailer. Never add `Signed-off-by` for an AI.
- `Assisted-by` discloses AI assistance when it was used. Omit it when no AI was involved.
- Do **not** use `Co-authored-by` for AI — `Assisted-by` is the right disclosure for tool assistance.

Keep the subject ≤ 72 chars. Use the body for the *why* (what motivated the change, what trade-off was accepted) — diff already shows the *what*.

## PR workflow

1. Branch from `main` using the naming above.
2. Make focused commits with the trailers above.
3. Push and open a PR. PR title mirrors the lead commit's Conventional Commit subject.
4. PR body: one paragraph of context (why), then a short test-plan checklist (what you ran to verify).
5. CI must be green before merge. For pipeline changes, that also means triggering **Release pack** once from the PR branch and confirming the release artifact looks right.

## Releasing

Releases are cut by the [Release pack](.github/workflows/release-pack.yml) workflow on demand — there is no version tag policy beyond the date-based tag the workflow generates (`pack-YYYY-MM-DD-HHMM`). The release asset is `cncf-icons-miro.zip`; the body records the upstream `cncf/artwork` commit it was built from.

If a build looks wrong after release, fix the script on a `bugfix/…` branch, merge, and re-run the workflow — there's no rollback because each release is independent.
