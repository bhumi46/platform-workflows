# platform-workflows

Shared CI/CD for the IDP lab services: versioning, build, release and deploy, written once and used
by every service repo (pinned to a major tag, e.g. `@v1`). Owned by the platform team.

## Lifecycle (GitFlow-lite)

| Branch | Builds | Default deploy |
|---|---|---|
| `develop` (default) | app `X.Y.Z-dev.N`, chart `A.B.C-dev.M` | dev (`auto`) |
| `release/X.Y` (from develop) | `X.Y.Z-rc.N` | qa (`approval`) |
| `hotfix/X.Y.Z` (from main) | `X.Y.Z-rc.N` | qa |
| `main` (merge of a release/hotfix PR) | nothing rebuilt: the tested rc is re-tagged `X.Y.Z`, tags `vX.Y.Z` / `chart-vA.B.C`, GitHub Release, back-merge PR | staging (`approval`) |

Versions come from **Conventional Commits** (PR titles, squash merges into develop):
`fix:`/`perf:` → patch · `feat:` → minor · `feat!:` or `BREAKING CHANGE:` → major (minor while 0.x) ·
`Release-As: 1.0.0` footer → exactly that version (GA). The **app** version counts commits outside
`charts/` (tags `vX.Y.Z`); the **chart** version counts commits in `charts/<svc>` (tags `chart-vA.B.C`).
If nothing changed, the last release's version is reused and nothing is rebuilt.

## Workflows (`workflow_call`)

| Workflow | Does |
|---|---|
| `build.yml` | computes versions, builds/pushes the multi-arch image (`:<version>` + `:<sha>`), publishes the chart if new |
| `deploy.yml` | sets `image.tag` + chart `targetRevision` for an env in gitops: `auto` commit or a rolling approval PR; never goes backwards |
| `release.yml` | on main: re-tags the tested image, publishes the final chart, tags, GitHub Release, back-merge PR |
| `pr-title.yml` | enforces Conventional Commit PR titles |

Caller example (a service's `.github/workflows/ci.yml`):

```yaml
on:
  pull_request:
  push:
    branches: [develop, 'release/**', 'hotfix/**', main]
jobs:
  test: { ... language-specific ... }
  pr-title:
    if: github.event_name == 'pull_request'
    uses: bhumi46/platform-workflows/.github/workflows/pr-title.yml@v1
  build:
    if: github.ref != 'refs/heads/main'
    needs: test
    uses: bhumi46/platform-workflows/.github/workflows/build.yml@v1
    with: {service: orders-svc}
  deploy:
    if: github.event_name == 'push' && github.ref != 'refs/heads/main'
    needs: build
    uses: bhumi46/platform-workflows/.github/workflows/deploy.yml@v1
    with:
      service: orders-svc
      env: ${{ github.ref_name == 'develop' && 'dev' || 'qa' }}
      version: ${{ needs.build.outputs.version }}
      chart_version: ${{ needs.build.outputs.chart_version }}
    secrets: {GITOPS_TOKEN: ${{ secrets.GITOPS_TOKEN }}}
  release: { if main: uses release.yml@v1, then deploy.yml@v1 with env staging }
```

## Scripts

- `scripts/semver-next`: next version from Conventional Commits (`--prefix v|chart-v`, `--include/--exclude <path>`, `--stage dev|rc|final`).
- `scripts/semver-compare A B`: SemVer 2.0.0 precedence (`1.0.0-dev.2 < 1.0.0-dev.10 < 1.0.0-rc.1 < 1.0.0`).

Tests: `bats tests` (19 cases), shellcheck, actionlint (see `ci.yml`).

## Versioning of this repo

Callers pin `@v1`. Backwards-compatible changes move the `v1` tag; breaking changes get `v2`.
