# /odh-manifests

Manage custom volume-mounted component manifests on an ODH cluster.

## What it does

Uses the [component-dev hack](https://github.com/opendatahub-io/opendatahub-operator/tree/main/hack/component-dev)
to override the ODH operator's built-in component images with chosen quay tags
(e.g. `:main`, a PR build tag).

## Implementation

All logic lives in **`bin/odh-manifests`** in the rhoai-work workspace, on PATH
as `odh-manifests`. This skill is a thin wrapper that runs the script and helps
interpret results — see `SKILL.md`.

You can run the script directly without Claude:

```bash
odh-manifests                          # interactive menu
odh-manifests status [--json]          # show current state
odh-manifests setup [component...]     # create PVC and patch CSV
odh-manifests copy <component> [tag]   # copy manifests into the operator pod
odh-manifests switch <component> [tag] # copy manifests and watch the rollout
odh-manifests update                   # restart dashboard for latest images
odh-manifests revert                   # tear down the custom setup
odh-manifests tags [repo]              # list recent quay tags
```

## Safety

Every command that writes to the cluster (`apply`, `patch`, `replace`, `scale`,
`delete`, `cp`, `rollout restart`) prints the exact command and the payload it
would send, then waits for approval. Reads run without prompting. Pass `--yes`
to skip the prompts in scripted use.

## Supported Components

| Component | Operator manifest path | Source | Key images |
|-----------|----------------------|--------|------------|
| `dashboard` | `/opt/manifests/dashboard` | local clone at `opendatahub-io/odh-dashboard` | odh-dashboard + all module sidecars |
| `modelcontroller` | `/opt/manifests/modelcontroller` | `opendatahub-io/odh-model-controller` (cloned on demand) | model-serving-api, odh-model-controller |

To add a component, extend `mount_path_for`, `quay_repo_for`, `deployments_for`,
and add a `copy_<component>_manifests` function in `bin/odh-manifests`.

## Prerequisites

- `oc` CLI authenticated to an ODH cluster
- `jq` and `curl`
- Local clone of `odh-dashboard` at `~/git/rhoai-work/opendatahub-io/odh-dashboard/`
- Internet access to `quay.io` (for tag listing and digest comparison)

## Cluster Resources

| Resource | Namespace | Purpose |
|----------|-----------|---------|
| PVC `custom-odh-dev-manifests` | `openshift-operators` | Stores custom manifests for all overridden components |
| VolumeMount `custom-dev-manifests` | (on CSV/operator pod) | Mounts the PVC with a subPath per component (e.g. `subPath: dashboard`) |

It also patches the operator CSV (`opendatahub-operator` in
`openshift-operators`) and triggers rollouts on component deployments in
`opendatahub`.

Reverting removes the mount, scales the operator to 0, and deletes the PVC.
Deployments keep running with their last-applied images until the operator
comes back and reconciles them.
