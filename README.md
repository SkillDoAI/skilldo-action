# skilldo-action

A GitHub Action that runs [Skilldo](https://github.com/SkillDoAI/skilldo) to generate or update `SKILL.md` for your library. Opens a PR or commits directly — you supply your own API keys and config.

## Quick Start

Add a `skilldo.toml` to your repo root ([configuration reference](https://github.com/SkillDoAI/skilldo#configuration)) and create a workflow:

```yaml
name: Update SKILL.md
on:
  release:
    types: [published]

permissions:
  contents: write
  pull-requests: write

jobs:
  skilldo:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
      - uses: SkillDoAI/skilldo-action@v1
        with:
          mode: pr
        env:
          OPENAI_API_KEY: ${{ secrets.OPENAI_API_KEY }}
```

That's it. On every release, Skilldo generates a `SKILL.md` and opens a PR.

## Inputs

| Input | Default | Description |
|-------|---------|-------------|
| `config` | `skilldo.toml` | Path to config file (relative to `path`) |
| `language` | *(auto-detect)* | Override language: `python`, `javascript`, `rust`, `go` |
| `output` | `SKILL.md` | Output file path (relative to `path`) |
| `version` | `latest` | Skilldo binary version (e.g., `v0.4.0`) |
| `mode` | `pr` | `pr` = open a pull request, `commit` = commit to current branch |
| `pr-branch` | `skilldo/update-skill` | Branch name for PR mode |
| `pr-title` | `chore: update SKILL.md` | PR title |
| `path` | `.` | Subdirectory to generate from (for monorepos) |
| `github-token` | `${{ github.token }}` | Token for git push and PR creation |

## Outputs

| Output | Description |
|--------|-------------|
| `changed` | `true` if SKILL.md was created or modified |
| `pr-url` | PR URL if one was created |

## Configuration

Skilldo is configured via `skilldo.toml`. At minimum, you need a provider and model:

```toml
provider = "openai"
model = "gpt-5.2"
```

See the full [configuration reference](https://github.com/SkillDoAI/skilldo#configuration) for all options including per-stage model mixing, custom instructions, and more.

API keys are passed as environment variables — never put them in `skilldo.toml`.

## Examples

### Commit directly in a PR

Regenerate SKILL.md whenever source files change in a PR:

```yaml
name: Regenerate SKILL.md
on:
  pull_request:
    paths: ['src/**', 'Cargo.toml', 'package.json', 'go.mod']

permissions:
  contents: write

jobs:
  skilldo:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
        with:
          ref: ${{ github.head_ref }}
      - uses: SkillDoAI/skilldo-action@v1
        with:
          mode: commit
        env:
          ANTHROPIC_API_KEY: ${{ secrets.ANTHROPIC_API_KEY }}
```

### Scheduled weekly refresh

```yaml
name: Weekly SKILL.md refresh
on:
  schedule:
    - cron: '0 9 * * 1'

permissions:
  contents: write
  pull-requests: write

jobs:
  skilldo:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
      - uses: SkillDoAI/skilldo-action@v1
        env:
          OPENAI_API_KEY: ${{ secrets.OPENAI_API_KEY }}
```

### Monorepo subdirectory

```yaml
- uses: SkillDoAI/skilldo-action@v1
  with:
    path: packages/my-lib
  env:
    OPENAI_API_KEY: ${{ secrets.OPENAI_API_KEY }}
```

Config is read from `packages/my-lib/skilldo.toml` and output goes to `packages/my-lib/SKILL.md`.

### Auto-merge the PR

Add a step after the action to enable auto-merge:

```yaml
- name: Enable auto-merge
  if: steps.skilldo.outputs.pr-url != ''
  run: gh pr merge --auto --squash "${{ steps.skilldo.outputs.pr-url }}"
  env:
    GH_TOKEN: ${{ secrets.GITHUB_TOKEN }}
```

Requires branch protection with required status checks enabled.

## Platform Support

| Runner | Supported |
|--------|-----------|
| `ubuntu-latest` (x86_64) | Yes |
| `ubuntu-24.04-arm` (aarch64) | Yes |
| `macos-latest` (arm64) | Yes |
| Windows | Not yet |

## License

MIT
