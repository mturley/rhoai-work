---
name: odh-manifests
description: Manage custom volume-mounted dashboard manifests on an ODH cluster. Check status, set up, update, switch image tags, or revert to operator-managed. Use when working with dashboard images on a dev cluster.
---

# ODH Dashboard Manifests Manager

Manage custom volume-mounted dashboard manifests on an ODH cluster using the
[component-dev hack](https://github.com/opendatahub-io/opendatahub-operator/tree/main/hack/component-dev).
This overrides the operator's built-in dashboard images with a chosen quay tag (e.g. `:main`, a PR build).

**Scripts in this directory:**
- `status.sh` — detect setup state (PVC, CSV mount, operator, images, digest comparison)
- `quay-tags.sh` — fetch recent meaningful tags from quay.io
- `copy-manifests.sh <tag>` — copy manifests with tag substitution into operator pod

## Phase 1: Cluster Authentication & Confirmation

1. Run `oc cluster-info` and `oc whoami`.
2. If either fails, tell the user to re-authenticate (`oc login`) and abort.
3. Present the cluster URL and logged-in user to the human via AskUserQuestion:
   - "Is this the right cluster?"
   - Options: "Yes, proceed" / "No, abort"
4. If user says no, abort with a message.

## Phase 2: Detect Setup State

Run the `status.sh` script from this skill's directory. Parse the JSON output.

The script is at the path relative to this SKILL.md file: `./status.sh`

Interpret the results:
- **Setup active:** `pvc_exists == true && csv_mounted == true && operator_replicas > 0`
- **Partially set up:** some but not all indicators are true — warn the user
- **Not set up:** `pvc_exists == false`

## Phase 3: Report Status

Present a clear summary to the user based on the status JSON. Include:
- Whether custom manifests are active and what tag is configured
- PVC, CSV mount, and operator state
- Current dashboard image tag and build age
- Whether the running image matches the latest on quay for that tag
- Local manifests repo commit (so user knows if they need to `git pull`)

## Phase 4: Offer Contextual Actions

Use AskUserQuestion to present relevant actions. The available actions depend on state:

**If NOT set up:**
- "Set up custom manifests" — full setup flow

**If set up and images outdated:**
- "Update images" — rollout restart to pull latest
- "Switch tag" — change to a different quay tag
- "Revert" — tear down custom setup

**If set up and images current:**
- "Switch tag" — change to a different quay tag
- "Force update" — rollout restart even though images match
- "Revert" — tear down custom setup

Always include a "Do nothing" option.

---

## Action: Set Up Custom Manifests

### Step 1: Ask for tag

Use AskUserQuestion:
- Option 1: `main` (Recommended)
- Option 2: "Another tag"

If "Another tag" is selected:
1. Run `./quay-tags.sh` from this skill's directory
2. Parse the tab-separated output and present the first 15 tags as AskUserQuestion options
3. The user can pick one or type a custom tag via "Other"

### Step 2: Present the plan

Tell the user exactly what will happen:
1. Create PVC `dashboard-dev-manifests` in `openshift-operators` (100Mi)
2. Patch the CSV to mount PVC at `/opt/manifests/dashboard` (sets replicas=1, strategy=Recreate, fsGroup=1001)
3. Wait for operator pod to start
4. Copy manifests from local clone with the chosen tag substituted in params.env
5. Restart operator to pick up new manifests
6. Monitor dashboard rollout

Ask user to confirm before proceeding.

### Step 3: Execute setup

**Create PVC:**
```bash
oc apply -f - <<'EOF'
apiVersion: v1
kind: PersistentVolumeClaim
metadata:
  name: dashboard-dev-manifests
  namespace: openshift-operators
spec:
  accessModes: [ReadWriteOnce]
  resources:
    requests:
      storage: 100Mi
EOF
```

**Patch CSV:**
First, check if the CSV already has the volume mount (the patch is NOT idempotent). If it does, skip this step and warn the user.

```bash
CSV=$(oc get csv -n openshift-operators -o name | grep opendatahub-operator | head -n1 | cut -d/ -f2)

oc patch csv "$CSV" -n openshift-operators --type json -p '[
  {"op": "replace", "path": "/spec/install/spec/deployments/0/spec/replicas", "value": 1},
  {"op": "add", "path": "/spec/install/spec/deployments/0/spec/strategy", "value": {"type": "Recreate"}},
  {"op": "add", "path": "/spec/install/spec/deployments/0/spec/template/spec/securityContext/fsGroup", "value": 1001},
  {"op": "add", "path": "/spec/install/spec/deployments/0/spec/template/spec/containers/0/volumeMounts/-", "value": {"name": "dashboard-manifests", "mountPath": "/opt/manifests/dashboard"}},
  {"op": "add", "path": "/spec/install/spec/deployments/0/spec/template/spec/volumes/-", "value": {"name": "dashboard-manifests", "persistentVolumeClaim": {"claimName": "dashboard-dev-manifests"}}}
]'
```

**Wait for operator pod:**
```bash
oc wait --for='jsonpath={.status.conditions[?(@.type=="Ready")].status}=True' \
  po -l name=opendatahub-operator -n openshift-operators --timeout=120s
```

**Copy manifests with tag:**
Run `./copy-manifests.sh <tag>` from this skill's directory.

**Monitor dashboard rollout:**
```bash
oc rollout status deployment/odh-dashboard -n opendatahub --timeout=300s
```

If the rollout times out, enter troubleshooting:
- `oc get pods -n opendatahub -l app=odh-dashboard`
- Check events: `oc get events -n opendatahub --sort-by='.lastTimestamp' | grep dashboard | tail -10`
- Check container statuses on any non-Ready pod
- Report findings and suggest fixes (common: CPU pressure — suggest deleting unused InferenceServices)

**Final status check:** Run `status.sh` again and report the result.

---

## Action: Update Images

1. Tell the user: "Restarting dashboard deployment to pull the latest `:TAG` images from quay."
2. Run:
   ```bash
   oc rollout restart deployment/odh-dashboard -n opendatahub
   ```
3. Monitor with `oc rollout status deployment/odh-dashboard -n opendatahub --timeout=300s`
4. If rollout times out, troubleshoot (same as setup).
5. Run `status.sh` and report final state.

---

## Action: Switch Tag

### Step 1: Ask for new tag

Same tag selection flow as setup (AskUserQuestion with `main` or "Another tag" → `quay-tags.sh`).

### Step 2: Present the plan

Tell the user:
1. Copy manifests to temp dir with the new tag in params.env
2. Copy into operator pod
3. Restart operator to pick up new manifests
4. Monitor dashboard rollout

Ask to confirm.

### Step 3: Execute

Run `./copy-manifests.sh <new-tag>` from this skill's directory. This handles the temp copy, sed edits, oc cp, and operator restart.

Then monitor: `oc rollout status deployment/odh-dashboard -n opendatahub --timeout=300s`

If rollout times out, troubleshoot. Run `status.sh` and report final state.

---

## Action: Revert

### Step 1: Present the plan

Tell the user exactly what will happen:
1. Scale operator deployment to 0 replicas
2. Clean the CSV: remove volume mount, volume, fsGroup, Recreate strategy
3. Delete the PVC
4. Note: the dashboard deployment will remain running with its current images — the operator just stops managing it

Ask to confirm.

### Step 2: Execute revert

**Scale operator to 0:**
```bash
oc scale deployment/opendatahub-operator-controller-manager -n openshift-operators --replicas=0
```

**Clean CSV:**
```bash
CSV=$(oc get csv -n openshift-operators -o name | grep opendatahub-operator | head -n1 | cut -d/ -f2)

oc get csv "$CSV" -n openshift-operators -o json | python3 -c "
import json, sys
csv = json.load(sys.stdin)
deploy = csv['spec']['install']['spec']['deployments'][0]
spec = deploy['spec']

spec.pop('strategy', None)

pod_spec = spec['template']['spec']
sc = pod_spec.get('securityContext', {})
sc.pop('fsGroup', None)
if not sc:
    pod_spec.pop('securityContext', None)

container = pod_spec['containers'][0]
container['volumeMounts'] = [
    vm for vm in container.get('volumeMounts', [])
    if vm.get('name') != 'dashboard-manifests'
]

pod_spec['volumes'] = [
    v for v in pod_spec.get('volumes', [])
    if v.get('name') != 'dashboard-manifests'
]

spec['replicas'] = 0
json.dump(csv, sys.stdout)
" | oc replace -f -
```

**Delete PVC:**
```bash
oc delete pvc dashboard-dev-manifests -n openshift-operators --ignore-not-found
```

Report completion. Run `status.sh` for final state.

---

## Error Handling

- If `oc` auth fails at any point, stop and tell the user to `oc login`.
- If a step fails, report the error with context (command run, output received) and stop.
- Never proceed past a failed step — the user needs to know what went wrong.
- The CSV patch is NOT idempotent. Before patching, check if the volume mount already exists and skip if so.
