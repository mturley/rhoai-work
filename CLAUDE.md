# RHOAI Dashboard Workspace

Multi-repo coordination workspace for the RHOAI Dashboard team's AI Hub (model registry/catalog) work.

## Workspace Structure

This workspace contains three git repositories organized by GitHub org:

| Path | Repo | Description |
|------|------|-------------|
| `opendatahub-io/odh-dashboard/` | [opendatahub-io/odh-dashboard](https://github.com/opendatahub-io/odh-dashboard) | ODH Dashboard monorepo (React/TypeScript frontend) |
| `kubeflow/model-registry/` | [kubeflow/model-registry](https://github.com/kubeflow/model-registry) | Upstream Kubeflow Model Registry (Go backend + UI under clients/ui) |
| `opendatahub-io/mod-arch-library/` | [opendatahub-io/mod-arch-library](https://github.com/opendatahub-io/mod-arch-library) | Modular Architecture shared library (React/TypeScript) |

Each repo has its own `.git` directory and is gitignored by this workspace repo.

A VS Code multi-root workspace file (`rhoai-work.code-workspace`) is configured with all three repos plus the workspace root as top-level folders, enabling cross-repo file search and unified SCM views.

## Repo Relationships

```
mod-arch-library (mod-arch-core, mod-arch-shared, mod-arch-kubeflow)
        |
        | npm packages consumed by
        v
model-registry/clients/ui  (upstream frontend + BFF)
        |
        | synced via update-subtree to
        v
odh-dashboard/packages/model-registry/upstream  (+ ODH extensions)
        |
        | frontend consumes REST API from
        v
model-registry  (Go backend, OpenAPI spec)
```

- **mod-arch-library** provides shared React components, hooks, context providers, and theming consumed by the model-registry UI and other odh-dashboard packages.
- **odh-dashboard** is a monorepo. The `packages/model-registry/` package contains the Model Registry UI. `packages/model-registry/upstream/` mirrors the upstream kubeflow repo structure. `packages/model-registry/src/` has downstream-only code.
- **model-registry** (kubeflow) is the upstream repo containing the Go REST API backend, the OpenAPI spec, and the UI code under `clients/ui/` (frontend + BFF). The `clients/ui/` code is regularly synced to `odh-dashboard/packages/model-registry/upstream/` using the `update-subtree` script in odh-dashboard (orchestrated via the `/model-registry-upstream-sync` skill in that repo). The odh-dashboard copy layers on ODH-specific extensions.

## Reading Repo-Specific Instructions

**IMPORTANT:** Before doing substantive work in a specific repo, read its instructions:

- **odh-dashboard**: Read `opendatahub-io/odh-dashboard/AGENTS.md` (CLAUDE.md points to it). For specific tasks, check the agent-rules files under `opendatahub-io/odh-dashboard/docs/agent-rules/`.
- **model-registry**: Read `kubeflow/model-registry/CLAUDE.md`. Key constraint: **never mention RHOAIENG Jira issues** in content pushed to this upstream repo.
- **mod-arch-library**: Read `opendatahub-io/mod-arch-library/AGENTS.md` (CLAUDE.md points to it). Uses Conventional Commits.

## Key Constraints Summary

These are extracted from the individual repo instructions for quick reference. Always read the full repo instructions for complete context.

- **odh-dashboard**: Node >= 22, npm >= 10, Go >= 1.24 (for BFFs). Uses Turbo monorepo, PatternFly v6, Webpack Module Federation. Run `npm run lint`, `npm run test`, `npm run type-check` from repo root.
- **model-registry**: Upstream open-source repo (kubeflow/model-registry). Uses `upstream` remote for canonical repo, `origin` for fork. **Never reference RHOAIENG Jira issues** in any content pushed upstream.
- **mod-arch-library**: Node >= 20, npm >= 10. Uses npm workspaces, Conventional Commits (`feat:`, `fix:`, `docs:`, etc.). No `.sort()` — use `.toSorted()`. Run `npm run build`, `npm run test`, `npm run lint` from repo root.

## Cross-Repo Jira Issues

Many Jira issues in the RHOAIENG project span multiple repos. When working on such issues:

1. **Read the Jira issue** using the Jira MCP tools to understand full scope.
2. **Identify which repos are affected** — e.g., an API change may require:
   - Backend changes in `kubeflow/model-registry/` (Go)
   - Frontend changes in `opendatahub-io/odh-dashboard/packages/model-registry/upstream/frontend/` (TypeScript/React)
   - Shared component changes in `opendatahub-io/mod-arch-library/` (TypeScript/React)
3. **Plan the work order**: Typically bottom-up:
   - API/backend changes first (model-registry)
   - Shared library changes if needed (mod-arch-library)
   - Frontend integration last (odh-dashboard)
4. **Respect upstream boundaries**: Changes to `model-registry` go through kubeflow upstream PRs. Do not reference internal Jira issues in those PRs.

## Context Files

Team and tool configuration is available via the `skills-context/` symlink (pointing to `~/.claude/skills/.context/`):

- `skills-context/people.md` — Full team roster with Jira usernames, GitHub usernames, and emails. Read this when you need team member information for Jira assignments, PR reviews, or understanding who works on what.
- `skills-context/jira-mcp.md` — Jira MCP server configuration, custom field IDs, format requirements
- `skills-context/confluence-mcp.md` — Confluence integration, user key resolution, page ID extraction
- `skills-context/puppeteer-mcp.md` — Browser automation configuration

Read the relevant context file before using the corresponding MCP tools.

## Common Cross-Repo Workflows

### Checking API contract alignment
- Compare the OpenAPI spec in `kubeflow/model-registry/api/` with the TypeScript types in `opendatahub-io/odh-dashboard/packages/model-registry/upstream/frontend/src/`

### Updating shared components
- Make changes in `opendatahub-io/mod-arch-library/`
- Check consumers in `opendatahub-io/odh-dashboard/packages/*/frontend/package.json`
- After publishing a new mod-arch version, update the dependency version in the consuming packages

### File Links in VS Code

When outputting markdown links to files (for clickable references in VS Code), use paths relative to the workspace root (`rhoai-work/`). Since repos are nested under org-name directories, file links must include the repo path prefix (e.g. `kubeflow/model-registry/path/to/file.ts`, not just `path/to/file.ts`).

### Navigating the model-registry UI code
- Upstream UI code: `opendatahub-io/odh-dashboard/packages/model-registry/upstream/frontend/src/`
- Downstream-only code: `opendatahub-io/odh-dashboard/packages/model-registry/src/`
- BFF (Go): `opendatahub-io/odh-dashboard/packages/model-registry/upstream/bff/`
- Extension point: `opendatahub-io/odh-dashboard/packages/model-registry/extensions.ts`
