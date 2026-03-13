# BFF: Real K8s API for listing and deleting MCPServer deployments

**Type:** Story
**Epic:** [RHOAIENG-51676](https://issues.redhat.com/browse/RHOAIENG-51676) — MCP Server Deployment UI
**Dependencies:** [01 — BFF mock endpoints for listing and deleting](01-bff-list-and-delete-mock.md)
**Track:** BFF (Track 1)

## Description

Replace the mock implementations from story 01 with real K8s API calls using the dynamic client to list and delete MCPServer CRs in the user's namespace.

Follow the pattern established in [`model_registry_settings_repository.go`](https://github.com/opendatahub-io/odh-dashboard/blob/d70a8972b65a4f1caa1e94daa847420a5587dd34/packages/model-registry/upstream/bff/internal/redhat/repositories/model_registry_settings_repository.go):
1. Extract REST config from the authenticated K8s client
2. Create a dynamic client
3. Define the MCPServer GroupVersionResource (GVR)
4. Use `dynamic.Resource(gvr).Namespace(ns).List()` and `.Delete()`

### Implementation Details

- **GVR:** `mcp.x-k8s.io` / `v1alpha1` / `mcpservers` (confirm — see Open Questions)
- **List:** Use dynamic client to list MCPServer CRs, transform unstructured results into the API response types defined in story 01
- **Delete:** Use dynamic client to delete the specified MCPServer CR by name
- **Mock fallback:** Retain the mock implementation and activate it conditionally when `MockK8Client=true` (for local dev/testing), following the existing pattern in the model registry settings handlers
- **Namespace:** Extract from request context using the existing `namespaceFromContext()` helper

### Field Mapping

Map CRD fields from the unstructured K8s response to the BFF API response types:
- `metadata.name` -> deployment identifier
- `metadata.creationTimestamp` -> created date
- `spec.image` -> container image
- `spec.port` -> port
- `status.phase` -> deployment status
- `status.conditions` -> detailed status information
- Additional field mappings TBD based on RHOAIENG-52641 findings

## Acceptance Criteria

- [ ] List endpoint returns real MCPServer CRs from the K8s API
- [ ] Delete endpoint deletes a real MCPServer CR via the K8s API
- [ ] Mock fallback works when `MockK8Client=true`
- [ ] Proper error handling for K8s API failures (not found, forbidden, etc.)
- [ ] Namespace is correctly extracted from request context
- [ ] Unit tests with mocked K8s client
- [ ] Integration tested against a cluster with the MCP lifecycle operator installed

## Open Questions

These should not block implementation. Use the best-guess GVR from story 01, and implement without operator detection initially. Open followup issues or keep this story open until the questions are resolved and adjustments are made.

- **MCPServer CRD group/version:** The upstream CRD uses `mcp.x-k8s.io/v1alpha1`. Is this the correct GVR in the RHOAI context? The MCP lifecycle operator may use a different API group. Use the upstream GVR for now and adjust if needed.
- **RBAC:** What permissions does the user need to list/delete MCPServer CRs? The BFF uses user-token auth, so the user's RBAC roles must include the necessary verbs. This relates to [RHOAIENG-52639](https://issues.redhat.com/browse/RHOAIENG-52639) (SPIKE: Test K8s Basic-User Access to CRD Availability). Implement with standard K8s error handling (403 Forbidden) and refine RBAC requirements based on spike findings.
- **Operator detection:** Should the BFF check whether the MCP lifecycle operator is installed before attempting to list MCPServer CRs? This relates to [RHOAIENG-52637](https://issues.redhat.com/browse/RHOAIENG-52637) (SPIKE: Test MCP Operator Install). Skip operator detection for now — handle gracefully if the CRD doesn't exist (e.g. return empty list or appropriate error).

## References

- [K8s dynamic client pattern](https://github.com/opendatahub-io/odh-dashboard/blob/d70a8972b65a4f1caa1e94daa847420a5587dd34/packages/model-registry/upstream/bff/internal/redhat/repositories/model_registry_settings_repository.go)
- [MCPServer CRD](https://github.com/kubernetes-sigs/mcp-lifecycle-operator/blob/main/config/crd/bases/mcp.x-k8s.io_mcpservers.yaml)
- [Example MCPServer CRs (Matthias Wessendorf)](https://gist.github.com/matzew/3fc0e8b77babe862ef039cb460edfc4b)
- [Conditional mock pattern](https://github.com/opendatahub-io/odh-dashboard/blob/d70a8972b65a4f1caa1e94daa847420a5587dd34/packages/model-registry/upstream/bff/internal/redhat/handlers/model_registry_settings.go)
