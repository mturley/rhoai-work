# RHOAI Dashboard Workspace

Multi-repo coordination workspace for working across the RHOAI Dashboard team's repositories using Claude Code.

## Repos

- **[odh-dashboard](https://github.com/opendatahub-io/odh-dashboard)** — Frontend dashboard monorepo (React/TypeScript)
- **[hub](https://github.com/kubeflow/hub)** — Upstream Kubeflow Hub backend (Go + Python)
- **[notebooks](https://github.com/kubeflow/notebooks)** — Upstream Kubeflow Notebooks (workspaces UI + backend, active trunk: `notebooks-v2`)
- **[mod-arch-library](https://github.com/opendatahub-io/mod-arch-library)** — Shared modular architecture library (React/TypeScript)
- **[model-registry-operator](https://github.com/opendatahub-io/model-registry-operator)** — Model registry Kubernetes operator (Go)

## Setup

Clone the repos into their org-namespaced directories (these are gitignored):

```bash
git clone git@github.com:opendatahub-io/odh-dashboard.git opendatahub-io/odh-dashboard
git clone git@github.com:kubeflow/hub.git kubeflow/hub
git clone git@github.com:kubeflow/notebooks.git kubeflow/notebooks
git clone git@github.com:opendatahub-io/mod-arch-library.git opendatahub-io/mod-arch-library
git clone git@github.com:opendatahub-io/model-registry-operator.git opendatahub-io/model-registry-operator
```

Create the skills-context symlink for Claude Code tool configuration (the `.context` directory comes from [mturley/claude-skills](https://github.com/mturley/claude-skills)):

```bash
ln -s ~/.claude/skills/.context skills-context
```

## VS Code Workspace

Open `rhoai-work.code-workspace` in VS Code to get a [multi-root workspace](https://code.visualstudio.com/docs/editor/multi-root-workspaces) with all repos plus the workspace root as top-level folders. This provides cross-repo file search, unified SCM views, and per-repo git integration.

See `CLAUDE.md` for workspace instructions used by Claude Code.
