# /odh-manifests

Manage custom volume-mounted component manifests on an ODH cluster.

## What it does

This skill uses the [component-dev hack](https://github.com/opendatahub-io/opendatahub-operator/tree/main/hack/component-dev) to override the ODH operator's built-in component images with chosen quay tags (e.g. `:main`, a PR build tag).

## Usage

```
/odh-manifests
```

The skill detects the current cluster state and offers contextual actions:

- **Set up** — create PVC, patch CSV, copy manifests with chosen tags
- **Update** — restart deployments to pull latest images for the current tag
- **Switch tag** — change to a different quay image tag
- **Manage another component** — add an override for an additional component
- **Revert** — tear down the custom setup, return to operator-managed

## Supported Components

| Component | Operator manifest path | Repo | Key images |
|-----------|----------------------|------|------------|
| `dashboard` | `/opt/manifests/dashboard` | `opendatahub-io/odh-dashboard` (local clone) | odh-dashboard + all module sidecars |
| `modelcontroller` | `/opt/manifests/modelcontroller` | `opendatahub-io/odh-model-controller` (cloned on demand) | model-serving-api, odh-model-controller |

More components can be added by extending `copy-manifests.sh` and `setup.sh`.

## Flow

1. **Cluster confirmation** — verifies `oc` auth and asks the user to confirm the cluster
2. **Status detection** — runs `status.sh` to check PVC, CSV volume mounts, operator state, all overridden components and their images
3. **Status report** — presents a summary: which components are overridden, what tags are running, whether images are current
4. **Action menu** — offers contextual actions based on state:
   - Not set up → offer to set up (asks which components and tags)
   - Set up + outdated → offer to update, switch tag, manage another component, or revert
   - Set up + current → offer to switch tag, manage another component, force update, or revert

## Prerequisites

- `oc` CLI authenticated to an ODH cluster
- Local clone of `odh-dashboard` at `~/git/rhoai-work/opendatahub-io/odh-dashboard/`
- Internet access to `quay.io` (for tag listing and digest comparison)

## Cluster Resources

The skill creates or removes these hard-coded resources:

| Resource | Namespace | Purpose |
|----------|-----------|---------|
| PVC `custom-odh-dev-manifests` | `openshift-operators` | Stores custom manifests for all overridden components |
| VolumeMount `custom-dev-manifests` | (on CSV/operator pod) | Mounts the PVC with subPath per component (e.g. `subPath: dashboard`) |

It also patches the operator CSV (`opendatahub-operator` in `openshift-operators`) and triggers rollouts on component deployments in `opendatahub`.

## Scripts

| Script | Purpose |
|--------|---------|
| `status.sh` | Detect setup state (PVC, CSV mounts, operator, images, all overridden components) |
| `quay-tags.sh [repo]` | Fetch and filter recent tags from quay.io (default: `opendatahub/odh-dashboard`) |
| `copy-manifests.sh <component> [tag]` | Copy component manifests with tag substitution into operator pod |
| `setup.sh [component...]` | Create PVC and patch CSV for component overrides (idempotent) |
| `revert.sh` | Tear down custom setup: scale operator to 0, clean CSV, delete PVC |
