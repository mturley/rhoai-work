# /odh-manifests

Manage custom volume-mounted dashboard manifests on an ODH cluster.

## What it does

This skill uses the [component-dev hack](https://github.com/opendatahub-io/opendatahub-operator/tree/main/hack/component-dev) to override the ODH operator's built-in dashboard images with a chosen quay tag (e.g. `:main`, a PR build tag).

## Usage

```
/odh-manifests
```

The skill detects the current cluster state and offers contextual actions:

- **Set up** — create PVC, patch CSV, copy manifests with chosen tag
- **Update** — restart dashboard to pull latest images for the current tag
- **Switch tag** — change to a different quay image tag
- **Revert** — tear down the custom setup, return to operator-managed

## Flow

1. **Cluster confirmation** — verifies `oc` auth and asks the user to confirm the cluster
2. **Status detection** — runs `status.sh` to check PVC, CSV volume mount, operator state, dashboard images, and quay digest comparison
3. **Status report** — presents a summary: what tag is running, whether images are current, local clone commit
4. **Action menu** — offers contextual actions based on state:
   - Not set up → offer to set up (asks for quay tag, walks through PVC + CSV patch + manifest copy)
   - Set up + outdated → offer to update (rollout restart), switch tag, or revert
   - Set up + current → offer to switch tag, force update, or revert

## Prerequisites

- `oc` CLI authenticated to an ODH cluster
- Local clone of `odh-dashboard` at `~/git/rhoai-work/opendatahub-io/odh-dashboard/`
- Internet access to `quay.io` (for tag listing and digest comparison)

## Scripts

| Script | Purpose |
|--------|---------|
| `status.sh` | Detect setup state (PVC, CSV mount, operator, images, digest) |
| `quay-tags.sh` | Fetch and filter recent tags from quay.io |
| `copy-manifests.sh <tag>` | Copy manifests with tag substitution into operator pod |
