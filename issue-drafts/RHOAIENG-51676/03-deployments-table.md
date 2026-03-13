# MCP Deployments list page and table

**Type:** Story
**Epic:** [RHOAIENG-51676](https://issues.redhat.com/browse/RHOAIENG-51676) — MCP Server Deployment UI
**Dependencies:** API contract from [01 — BFF mock endpoints](01-bff-list-and-delete-mock.md)
**Track:** Frontend (Track 2)

## Description

Build the MCP Deployments list page, including navigation, page shell, and the deployments table. This is the primary view for managing deployed MCP servers.

Reference the [static prototype](https://rhoai-3-4-cb1313.pages.redhat.com/ai-hub/mcp/deployments) for visual design.

This is downstream-only code in `packages/model-registry/src/`.

### Navigation and Page Shell

- Add "MCP Deployments" nav item under "MCP servers" in the left sidebar
- Create the route and page component
- Page title: "MCP server deployments"
- Page description: "Manage and view the health and performance of your deployed MCP servers."
- Project selector dropdown at top of page
- Empty state when no deployments exist

### Table

Follow existing table patterns (e.g. `RegisteredModelTable.tsx` using `SortableData` columns and `Table` from mod-arch-shared).

**Columns:**
| Column | Sortable | Notes |
|--------|----------|-------|
| Server | Yes | TBD field mapping — see Open Questions |
| Name | Yes | TBD field mapping — see Open Questions |
| Created | Yes | `metadata.creationTimestamp`, formatted as date string |
| Status | Yes | Derived from `status.phase` — color-coded label with tooltip |

**Status display:**
- Color-coded labels: green for healthy states, red for error states
- Tooltips explaining the status (see prototype screenshots)
- Exact mapping from `status.phase` (Pending/Running/Failed) to display labels TBD — should be more nuanced than just available/unavailable

**Toolbar:**
- Search/filter input: "Filter by name or server name"
- Item count display (e.g. "1 - 3 of 3")

**Pagination:**
- Standard pagination controls at bottom of table

**Row actions (kebab menu):**
- "Edit" — stub action, non-functional (placeholder for future implementation)
- "Delete" — triggers delete flow (see [04 — Delete deployment](04-delete-deployment.md))

### Data Fetching

- Create a custom hook (e.g. `useMcpDeployments`) using `useFetchState` from mod-arch-core
- Wire up to the BFF list endpoint (`GET /api/v1/mcp_deployments`)
- Can develop against the mock BFF endpoint initially

## Acceptance Criteria

- [ ] "MCP Deployments" appears in the sidebar navigation under "MCP servers"
- [ ] Page displays with correct title, description, and project selector
- [ ] Table renders deployment data with all 4 columns
- [ ] Columns are sortable
- [ ] Filter input filters by name/server name
- [ ] Pagination works correctly
- [ ] Status column shows color-coded labels with tooltips
- [ ] Kebab menu shows "Edit" (disabled/stub) and "Delete" actions
- [ ] Empty state displays when no deployments exist
- [ ] Data is fetched from the BFF list endpoint
- [ ] Component tests for table rendering and filtering

## Open Questions

These should not block implementation. Use the best-guess field mappings from the BFF API contract (story 01) and the status mapping below. Open a followup issue or keep this story open until the questions are resolved and adjustments are made.

- **Server vs Name columns:** The prototype shows "Server" (e.g. "Kubernetes-1.0.0") and "Name" (e.g. "Kubernetes Test") as separate values. The MCPServer CRD has `metadata.name` and `spec.image` but no obvious mapping to these two display values. This depends on [RHOAIENG-52641](https://issues.redhat.com/browse/RHOAIENG-52641) (SPIKE: Evaluate MCPServers for Commonality). Use whatever field mapping the BFF provides and adjust once the spike is complete.
- **Status mapping:** The CRD uses `status.phase` with values Pending/Running/Failed. The prototype shows "available" (green) and "unavailable" (red). Make a best-guess mapping (e.g. Running = "available" green, Failed = "unavailable" red, Pending = "pending" yellow/blue) and adjust based on UX feedback.

## References

- [Static prototype](https://rhoai-3-4-cb1313.pages.redhat.com/ai-hub/mcp/deployments)
- [Existing table pattern: RegisteredModelTable](https://github.com/opendatahub-io/odh-dashboard/blob/d70a8972b65a4f1caa1e94daa847420a5587dd34/packages/model-registry/upstream/frontend/src/app/pages/modelRegistry/screens/RegisteredModels/RegisteredModelTable.tsx)
- [SortableData column pattern](https://github.com/opendatahub-io/odh-dashboard/blob/d70a8972b65a4f1caa1e94daa847420a5587dd34/packages/model-registry/upstream/frontend/src/app/pages/modelRegistry/screens/RegisteredModels/RegisteredModelsTableColumns.ts)
- [useFetchState hook pattern](https://github.com/opendatahub-io/odh-dashboard/blob/d70a8972b65a4f1caa1e94daa847420a5587dd34/packages/model-registry/upstream/frontend/src/app/hooks/useRegisteredModels.ts)
