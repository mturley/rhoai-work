# BFF: Mock endpoints for listing and deleting MCPServer deployments

**Type:** Story
**Epic:** [RHOAIENG-51676](https://issues.redhat.com/browse/RHOAIENG-51676) — MCP Server Deployment UI
**Dependencies:** None (can start immediately)
**Track:** BFF (Track 1)

## Description

Add new BFF endpoints for listing and deleting MCPServer deployments, initially backed by mock data. These endpoints will serve as the API contract for the frontend team to build against in parallel.

Use the BFF downstream extension mechanism documented in [extensions.md](https://github.com/opendatahub-io/odh-dashboard/blob/main/packages/model-registry/upstream/bff/docs/extensions.md). Handlers go in `internal/redhat/handlers/`, repositories in `internal/redhat/repositories/`.

### Endpoints

- **`GET /api/v1/mcp_deployments`** — List MCPServer deployments in the current namespace
  - Returns paginated list of MCPServer deployment objects
  - Supports query params for pagination (pageSize, nextPageToken)
- **`DELETE /api/v1/mcp_deployments/:name`** — Delete an MCPServer deployment by name

### Mock Data

Mock data should include several MCPServer deployments with varying statuses to enable frontend development and testing. The mock data structure should mirror the MCPServer CR spec/status fields from the [CRD](https://github.com/kubernetes-sigs/mcp-lifecycle-operator/blob/main/config/crd/bases/mcp.x-k8s.io_mcpservers.yaml).

Key CRD fields to include in the API response:
- `metadata.name`, `metadata.namespace`, `metadata.creationTimestamp`
- `spec.image`, `spec.port`
- `status.phase` (Pending, Running, Failed)
- `status.conditions` (for detailed status info)

### API Response Types

Define Go structs for the API response and corresponding TypeScript types for the frontend. The response type should abstract over the raw CRD structure where appropriate (e.g. flattening nested fields).

**Note:** The exact field mapping for the "Server" and "Name" columns in the UI is TBD (see Open Questions). Make a best-guess mapping to unblock dependent stories — the API response structure can be adjusted in a followup once the open questions are resolved.

## Acceptance Criteria

- [ ] BFF handler for `GET /api/v1/mcp_deployments` returns mock deployment data
- [ ] BFF handler for `DELETE /api/v1/mcp_deployments/:name` accepts a delete request and returns success
- [ ] Handlers are registered via the downstream extension mechanism (not added to upstream route definitions)
- [ ] Mock data includes deployments with different `status.phase` values (Pending, Running, Failed)
- [ ] Go response types are defined in a models file
- [ ] TypeScript types for the API response are defined for frontend consumption
- [ ] Unit tests for both handlers with mock data

## Open Questions

These should not block implementation. Make a best guess to unblock dependent stories, then open a followup issue or keep this story open until the questions are resolved and adjustments are made.

- **Server vs Name mapping:** The prototype shows "Server" (e.g. "Kubernetes-1.0.0") and "Name" (e.g. "Kubernetes Test") as separate columns. The MCPServer CRD has `metadata.name` and `spec.image` but no obvious mapping to these two display values. This depends on findings from [RHOAIENG-52641](https://issues.redhat.com/browse/RHOAIENG-52641) (SPIKE: Evaluate MCPServers for Commonality). Make a best-guess mapping and adjust once the spike is complete.
- **MCPServer CRD group/version:** The upstream CRD uses `mcp.x-k8s.io/v1alpha1`. Confirm this is the correct group/version for the RHOAI context, or if there is a different GVR to use. Use the upstream GVR for now and adjust if needed.

## References

- [MCPServer CRD](https://github.com/kubernetes-sigs/mcp-lifecycle-operator/blob/main/config/crd/bases/mcp.x-k8s.io_mcpservers.yaml)
- [BFF extensions documentation](https://github.com/opendatahub-io/odh-dashboard/blob/main/packages/model-registry/upstream/bff/docs/extensions.md)
- [Existing downstream handler example](https://github.com/opendatahub-io/odh-dashboard/blob/d70a8972b65a4f1caa1e94daa847420a5587dd34/packages/model-registry/upstream/bff/internal/redhat/handlers/model_registry_settings.go)
- [Example MCPServer CRs (Matthias Wessendorf)](https://gist.github.com/matzew/3fc0e8b77babe862ef039cb460edfc4b)
- [Static prototype](https://rhoai-3-4-cb1313.pages.redhat.com/ai-hub/mcp/deployments)
