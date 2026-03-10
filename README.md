# RHOAI Dashboard Workspace

Multi-repo coordination workspace for working across the RHOAI Dashboard team's repositories using Claude Code.

## Repos

- **[odh-dashboard](https://github.com/opendatahub-io/odh-dashboard)** — Frontend dashboard monorepo (React/TypeScript)
- **[model-registry](https://github.com/kubeflow/model-registry)** — Upstream model registry backend (Go + Python)
- **[mod-arch-library](https://github.com/opendatahub-io/mod-arch-library)** — Shared modular architecture library (React/TypeScript)

## Setup

Clone the repos into their org-namespaced directories (these are gitignored):

```bash
git clone git@github.com:opendatahub-io/odh-dashboard.git opendatahub-io/odh-dashboard
git clone git@github.com:kubeflow/model-registry.git kubeflow/model-registry
git clone git@github.com:opendatahub-io/mod-arch-library.git opendatahub-io/mod-arch-library
```

Create the skills-context symlink for Claude Code tool configuration (the `.context` directory comes from [mturley/claude-skills](https://github.com/mturley/claude-skills)):

```bash
ln -s ~/.claude/skills/.context skills-context
```

## VS Code Workspace

Open `rhoai-work.code-workspace` in VS Code to get a [multi-root workspace](https://code.visualstudio.com/docs/editor/multi-root-workspaces) with all three repos plus the workspace root as top-level folders. This provides cross-repo file search, unified SCM views, and per-repo git integration.

See `CLAUDE.md` for workspace instructions used by Claude Code.
