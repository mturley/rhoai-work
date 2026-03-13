# Delete MCP server deployment

**Type:** Story
**Epic:** [RHOAIENG-51676](https://issues.redhat.com/browse/RHOAIENG-51676) — MCP Server Deployment UI
**Dependencies:** [03 — MCP Deployments table](03-deployments-table.md), delete endpoint from [01 — BFF mock endpoints](01-bff-list-and-delete-mock.md)
**Track:** Frontend (Track 2)

## Description

Implement the delete action for MCP server deployments, triggered from the kebab menu in the deployments table. Includes a confirmation modal that requires typing the deployment name to confirm deletion.

Reference the [static prototype](https://rhoai-3-4-cb1313.pages.redhat.com/ai-hub/mcp/deployments) for visual design of the delete modal.

This is downstream-only code in `packages/model-registry/src/`.

### Delete Confirmation Modal

Follow the existing delete modal pattern (e.g. `DeleteModal.tsx` or `DeleteModelRegistryModal.tsx`).

**Modal content:**
- Title: "Delete MCP server deployment?"
- Warning icon
- Body text: "The **{deploymentName}** MCP server deployment and its API keys will be deleted, and its endpoint will no longer be available as an AI asset."
- Confirmation input: "Type **{deploymentName}** to confirm deletion:"
- Helper text below input: "Enter the deployment name exactly as shown to confirm deletion."
- Submit button: "Delete MCP server deployment" (disabled until name matches)
- Cancel button

**Behavior:**
- Submit button disabled until typed name exactly matches the deployment name
- Enter key submits when name matches
- Loading state on submit button while delete is in progress
- Error display if delete fails
- On success: close modal, refresh the deployments table
- On cancel: close modal, no action

### API Integration

- Call `DELETE /api/v1/mcp_deployments/:name` via the BFF
- Handle success/error responses
- Refresh the table data after successful deletion

## Acceptance Criteria

- [ ] "Delete" action in kebab menu opens the delete confirmation modal
- [ ] Modal displays the correct deployment name in the warning text
- [ ] Delete button is disabled until the typed name exactly matches
- [ ] Enter key submits when the name matches
- [ ] Loading state shown during deletion
- [ ] Error message displayed if deletion fails
- [ ] Table refreshes after successful deletion
- [ ] Modal closes on successful deletion or cancel
- [ ] Component tests for modal behavior (disabled state, name matching, submission)

## References

- [Static prototype — delete modal](https://rhoai-3-4-cb1313.pages.redhat.com/ai-hub/mcp/deployments)
- [Existing delete modal pattern](https://github.com/opendatahub-io/odh-dashboard/blob/d70a8972b65a4f1caa1e94daa847420a5587dd34/packages/model-registry/upstream/frontend/src/app/pages/modelRegistry/screens/components/DeleteModal.tsx)
- [Delete model registry modal example](https://github.com/opendatahub-io/odh-dashboard/blob/d70a8972b65a4f1caa1e94daa847420a5587dd34/packages/model-registry/src/modelRegistrySettings/DeleteModelRegistryModal.tsx)
