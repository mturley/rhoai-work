---
name: odh-manifests
description: Manage custom volume-mounted component manifests on an ODH cluster. Check status, set up, update, switch image tags, or revert to operator-managed. Supports dashboard and modelcontroller (model-serving-api). Use when working with component images on a dev cluster.
---

# ODH Component Manifests Manager

Manage custom volume-mounted component manifests on an ODH cluster using the
[component-dev hack](https://github.com/opendatahub-io/opendatahub-operator/tree/main/hack/component-dev).
This overrides the operator's built-in component images with chosen quay tags.

**Scripts in this directory:**
- `status.sh` — detect setup state (PVC, CSV mounts, operator, images, overridden components)
- `quay-tags.sh [repo]` — fetch recent meaningful tags from quay.io (default repo: `opendatahub/odh-dashboard`)
- `copy-manifests.sh <component> [tag]` — copy component manifests with tag substitution into operator pod
- `setup.sh [component...]` — create PVC and patch CSV for component overrides (idempotent)
- `revert.sh` — tear down custom setup (scale operator to 0, clean CSV, delete PVC)

**Supported components:**

| Component | Operator path | Repo | Key images |
|-----------|--------------|------|------------|
| `dashboard` | `/opt/manifests/dashboard` | `opendatahub-io/odh-dashboard` (local clone) | odh-dashboard + all module sidecars |
| `modelcontroller` | `/opt/manifests/modelcontroller` | `opendatahub-io/odh-model-controller` (cloned on demand) | model-serving-api, odh-model-controller |

The PVC is `custom-odh-dev-manifests` in `openshift-operators`, shared by all components via subPath mounts.

## Phase 1: Cluster Authentication & Confirmation

1. Run `oc cluster-info` and `oc whoami`.
2. If either fails, tell the user to re-authenticate (`oc login`) and abort.
3. Present the cluster URL and logged-in user to the human via AskUserQuestion:
   - "Is this the right cluster?"
   - Options: "Yes, proceed" / "No, abort"
4. If user says no, abort with a message.

## Phase 2: Detect Setup State

Run `./status.sh` from this skill's directory. Parse the JSON output.

Key fields:
- `pvc_exists` — whether the PVC exists
- `overridden_components` — list of component subPaths mounted (e.g. `["dashboard", "modelcontroller"]`)
- `operator_replicas` / `operator_ready` — operator state
- `containers` — dashboard container images and tags
- `current_tag` — dashboard image tag
- `image_current` — whether dashboard image matches quay latest for that tag
- `other_components` — details on non-dashboard overridden components (deployments, images, tags)

Interpret:
- **Setup active:** `pvc_exists == true && overridden_components is non-empty && operator_replicas > 0`
- **Partially set up:** PVC exists but operator is down or no mounts
- **Not set up:** `pvc_exists == false`

## Phase 3: Report Status

Present a clear summary including:
- PVC and operator state
- **For each overridden component:** what tag is running, whether images are current
- Dashboard image tag, build age, and quay digest comparison
- Other overridden components with their deployment images
- Local manifests repo commit
- Which Managed DSC components could also be overridden but aren't

## Phase 4: Offer Contextual Actions

Use AskUserQuestion to present relevant actions based on state:

**If NOT set up:**
- "Set up custom manifests" — asks which components to override, then runs setup + copy flow

**If set up:**
- "Update dashboard images" — rollout restart to pull latest for current tag (only if dashboard is overridden)
- "Switch dashboard tag" — change dashboard to a different quay tag
- "Manage another component" — add or update an override for another component
- "Revert" — tear down the entire custom setup
- "Do nothing"

If dashboard images are outdated, highlight the "Update" option.

---

## Action: Set Up Custom Manifests

### Step 1: Ask which components

Use AskUserQuestion with multiSelect:
- "dashboard" (Recommended) — override dashboard and all module sidecars
- "modelcontroller" — override model-serving-api and odh-model-controller

### Step 2: Ask for dashboard tag (if dashboard selected)

Use AskUserQuestion:
- Option 1: `main` (Recommended)
- Option 2: "Another tag"

If "Another tag" is selected:
1. Run `./quay-tags.sh` from this skill's directory
2. Parse the tab-separated output and present the first 15 tags as options
3. The user can pick one or type a custom tag via "Other"

### Step 3: Ask for modelcontroller tag (if modelcontroller selected)

Same flow, but use `./quay-tags.sh opendatahub/odh-model-serving-api` for tags.
Default recommendation: use upstream defaults (no tag override).

### Step 4: Present the plan

Tell the user exactly what will happen:
1. Create PVC `custom-odh-dev-manifests` in `openshift-operators` (if needed)
2. Patch CSV with volume mount(s) for selected components (replicas=1, Recreate, fsGroup=1001)
3. Wait for operator pod
4. Copy manifests for each component with chosen tags
5. Restart operator
6. Monitor rollouts

Ask user to confirm.

### Step 5: Execute

Run `./setup.sh <components...>` from this skill's directory.
Then for each component, run `./copy-manifests.sh <component> [tag]`.
Monitor rollouts:
```bash
oc rollout status deployment/odh-dashboard -n opendatahub --timeout=300s
```
If modelcontroller was set up, also check `model-serving-api`.

If any rollout times out, troubleshoot:
- Check pod events and container statuses
- Common issue: CPU pressure — suggest deleting unused InferenceServices

Run `./status.sh` and report final state.

---

## Action: Update Dashboard Images

1. Tell the user: "Restarting dashboard deployment to pull the latest `:TAG` images."
2. Run `oc rollout restart deployment/odh-dashboard -n opendatahub`
3. Monitor with `oc rollout status deployment/odh-dashboard -n opendatahub --timeout=300s`
4. If rollout times out, troubleshoot.
5. Run `./status.sh` and report final state.

---

## Action: Switch Dashboard Tag

### Step 1: Ask for new tag

Same tag selection flow as setup.

### Step 2: Present plan and confirm

### Step 3: Execute

Run `./copy-manifests.sh dashboard <new-tag>` from this skill's directory (handles temp copy, sed edits, oc cp, operator restart).
Monitor: `oc rollout status deployment/odh-dashboard -n opendatahub --timeout=300s`
Run `./status.sh` and report final state.

---

## Action: Manage Another Component

### Step 1: Ask which component

Present components that are Managed in the DSC but not currently overridden.
Currently supported: `dashboard`, `modelcontroller`.

### Step 2: Ask for tag (if applicable)

### Step 3: Execute

Run `./setup.sh <component>` to add the CSV mount (idempotent).
Then run `./copy-manifests.sh <component> [tag]`.
Monitor relevant deployment rollout.
Run `./status.sh` and report final state.

---

## Action: Revert

### Step 1: Present the plan

Tell the user:
1. Scale operator to 0
2. Clean CSV: remove all custom-dev-manifests volume mounts, volume, fsGroup, Recreate strategy
3. Delete PVC
4. Dashboard and other deployments remain running with their current images

Ask to confirm.

### Step 2: Execute

Run `./revert.sh` from this skill's directory.
Run `./status.sh` and report final state.

---

## Error Handling

- If `oc` auth fails at any point, stop and tell the user to `oc login`.
- If a step fails, report the error with context and stop.
- `setup.sh` is idempotent — safe to run multiple times.
- `copy-manifests.sh` requires the operator pod to be running.
