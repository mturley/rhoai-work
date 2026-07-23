# `/odh-manifests` Skill Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Create a Claude Code skill that manages custom volume-mounted dashboard manifests on an ODH cluster, allowing the user to run `:main` or any quay tag instead of the operator's built-in images.

**Architecture:** A SKILL.md file with orchestration logic, backed by three shell scripts that encapsulate the reusable, non-trivial operations (status detection, quay tag fetching, params.env editing + manifest copying). The SKILL.md handles user interaction, action selection, and error reporting. Scripts are invoked by Claude via the Bash tool.

**Tech Stack:** Bash scripts, `oc` CLI, `curl` + `python3` for Quay API, Claude Code SKILL.md format.

## Global Constraints

- Skill location: `/Users/mturley/git/rhoai-work/.claude/skills/odh-manifests/`
- Symlink: `~/git/claude-skills/odh-manifests` -> `../../git/rhoai-work/.claude/skills/odh-manifests`
- SKILL.md frontmatter: `name: odh-manifests`, `description:` with trigger guidance
- Scripts must be executable (`chmod +x`)
- Scripts must use `set -euo pipefail`
- Never modify the local git clone's `manifests/` files — use temp copies
- The skill's SKILL.md instructions tell Claude what to do; scripts are tools Claude invokes

## File Structure

```
.claude/skills/odh-manifests/
  SKILL.md              # Skill instructions (phases, actions, user interaction)
  status.sh             # Detect setup state: PVC, CSV mount, operator, images, digest comparison
  quay-tags.sh          # Fetch + filter recent tags from Quay API
  copy-manifests.sh     # Copy manifests to temp dir, edit params.env, oc cp to operator pod
  README.md             # Usage documentation
```

Symlink in claude-skills repo:
```
~/git/claude-skills/odh-manifests -> ../../git/rhoai-work/.claude/skills/odh-manifests
```

---

### Task 1: `status.sh` — Setup State Detection

**Files:**
- Create: `.claude/skills/odh-manifests/status.sh`

**Interfaces:**
- Consumes: `oc` CLI (must be authenticated), cluster access
- Produces: JSON output on stdout with fields: `pvc_exists`, `csv_mounted`, `operator_replicas`, `operator_running`, `dashboard_namespace`, `containers` (array of `{name, image, tag, imageID}`), `current_tag`, `quay_latest_digest`, `image_current`, `local_manifests_commit`

- [ ] **Step 1: Write `status.sh`**

The script checks cluster state and outputs structured JSON. It should:
1. Check if PVC `dashboard-dev-manifests` exists in `openshift-operators`
2. Check if the CSV has a volumeMount at `/opt/manifests/dashboard`
3. Check operator deployment replica count and running status
4. Get dashboard deployment container images and tags
5. Get running pod imageIDs for the `odh-dashboard` container
6. Fetch the latest digest for the detected tag from quay.io
7. Compare running digest vs quay latest to determine if up to date
8. Get the local manifests commit from the odh-dashboard repo

```bash
#!/usr/bin/env bash
# Detect the state of custom volume-mounted dashboard manifests on an ODH cluster.
# Outputs JSON to stdout. Requires: oc (authenticated), curl, python3.
set -euo pipefail

OPERATOR_NS="openshift-operators"
DASHBOARD_NS="opendatahub"
PVC_NAME="dashboard-dev-manifests"
MANIFESTS_REPO="$HOME/git/rhoai-work/opendatahub-io/odh-dashboard"

# 1. PVC check
pvc_exists="false"
if oc get pvc "$PVC_NAME" -n "$OPERATOR_NS" &>/dev/null; then
  pvc_exists="true"
fi

# 2. CSV volume mount check
csv_mounted="false"
csv_name=$(oc get csv -n "$OPERATOR_NS" -o name 2>/dev/null | grep opendatahub-operator | head -n1 | cut -d/ -f2)
if [ -n "$csv_name" ]; then
  mounts=$(oc get csv "$csv_name" -n "$OPERATOR_NS" -o jsonpath='{.spec.install.spec.deployments[0].spec.template.spec.containers[0].volumeMounts}' 2>/dev/null)
  if echo "$mounts" | grep -q '/opt/manifests/dashboard'; then
    csv_mounted="true"
  fi
fi

# 3. Operator deployment
operator_replicas=$(oc get deployment opendatahub-operator-controller-manager -n "$OPERATOR_NS" -o jsonpath='{.spec.replicas}' 2>/dev/null || echo "0")
operator_ready=$(oc get deployment opendatahub-operator-controller-manager -n "$OPERATOR_NS" -o jsonpath='{.status.readyReplicas}' 2>/dev/null || echo "0")
operator_ready="${operator_ready:-0}"

# 4. Dashboard containers
containers_json=$(oc get deployment odh-dashboard -n "$DASHBOARD_NS" -o json 2>/dev/null | python3 -c "
import json, sys
deploy = json.load(sys.stdin)
containers = deploy['spec']['template']['spec']['containers']
result = []
for c in containers:
    image = c['image']
    parts = image.rsplit(':', 1)
    tag = parts[1] if len(parts) > 1 else 'latest'
    result.append({'name': c['name'], 'image': image, 'tag': tag})
json.dump(result, sys.stdout)
" 2>/dev/null || echo "[]")

# 5. Running pod imageID for odh-dashboard container
pod_image_id=$(oc get pods -n "$DASHBOARD_NS" -l app=odh-dashboard -o jsonpath='{.items[0].status.containerStatuses[?(@.name=="odh-dashboard")].imageID}' 2>/dev/null || echo "")

# 6. Detect current tag from odh-dashboard container
current_tag=$(echo "$containers_json" | python3 -c "
import json, sys
containers = json.load(sys.stdin)
for c in containers:
    if c['name'] == 'odh-dashboard':
        print(c['tag'])
        break
" 2>/dev/null || echo "unknown")

# 7. Quay digest comparison
quay_latest_digest=""
image_current="unknown"
if [ "$current_tag" != "unknown" ]; then
  quay_latest_digest=$(curl -sf "https://quay.io/api/v1/repository/opendatahub/odh-dashboard/tag/?specificTag=${current_tag}&onlyActiveTags=true" 2>/dev/null | python3 -c "
import json, sys
data = json.load(sys.stdin)
tags = data.get('tags', [])
if tags:
    print(tags[0].get('manifest_digest', ''))
" 2>/dev/null || echo "")

  if [ -n "$quay_latest_digest" ] && [ -n "$pod_image_id" ]; then
    pod_digest=$(echo "$pod_image_id" | sed 's/.*@//')
    if [ "$pod_digest" = "$quay_latest_digest" ]; then
      image_current="true"
    else
      image_current="false"
    fi
  fi
fi

# 8. Local manifests commit
local_commit=""
if [ -d "$MANIFESTS_REPO/.git" ]; then
  local_commit=$(git -C "$MANIFESTS_REPO" rev-parse --short HEAD 2>/dev/null || echo "")
fi

# Output JSON
python3 -c "
import json
print(json.dumps({
    'pvc_exists': $pvc_exists,
    'csv_mounted': $csv_mounted,
    'csv_name': '${csv_name}',
    'operator_replicas': int('${operator_replicas}'),
    'operator_ready': int('${operator_ready}'),
    'dashboard_namespace': '${DASHBOARD_NS}',
    'containers': ${containers_json},
    'current_tag': '${current_tag}',
    'pod_image_id': '${pod_image_id}',
    'quay_latest_digest': '${quay_latest_digest}',
    'image_current': '${image_current}',
    'local_manifests_commit': '${local_commit}'
}, indent=2))
"
```

- [ ] **Step 2: Make executable and test**

```bash
chmod +x .claude/skills/odh-manifests/status.sh
.claude/skills/odh-manifests/status.sh
```

Expected: JSON output with all fields populated (assumes `oc` is authenticated to a cluster).

- [ ] **Step 3: Commit**

```bash
git add .claude/skills/odh-manifests/status.sh
git commit --signoff -m "feat(odh-manifests): add status detection script"
```

---

### Task 2: `quay-tags.sh` — Fetch Recent Quay Tags

**Files:**
- Create: `.claude/skills/odh-manifests/quay-tags.sh`

**Interfaces:**
- Consumes: `curl`, `python3`, internet access to quay.io
- Produces: Tab-separated output on stdout: `tag_name\tlast_modified` (one per line, sorted by most recent first). Filters out signatures, attestations, sboms, raw SHA digests, Tekton pipeline run tags, and arch-specific tags.

- [ ] **Step 1: Write `quay-tags.sh`**

```bash
#!/usr/bin/env bash
# Fetch and filter recent meaningful tags from a Quay repository.
# Usage: quay-tags.sh [repo] [limit]
#   repo:  quay.io repository path (default: opendatahub/odh-dashboard)
#   limit: max tags to fetch from API (default: 100)
# Outputs tab-separated: tag_name\tlast_modified
set -euo pipefail

REPO="${1:-opendatahub/odh-dashboard}"
LIMIT="${2:-100}"

curl -sf "https://quay.io/api/v1/repository/${REPO}/tag/?limit=${LIMIT}&onlyActiveTags=true" | python3 -c "
import json, sys, re

data = json.load(sys.stdin)
tags = data.get('tags', [])

skip_suffixes = ['.sig', '.sbom', '.att', '.src', '.dockerfile', '.git']
skip_patterns = [
    r'^sha256-',
    r'build-image',
    r'-linux-x86',
    r'-linux-aarch',
    r'^[0-9a-f]{40}$',
]

for t in tags:
    name = t.get('name', '')
    if any(name.endswith(s) for s in skip_suffixes):
        continue
    if any(re.search(p, name) for p in skip_patterns):
        continue
    modified = t.get('last_modified', '')
    print(f'{name}\t{modified}')
"
```

- [ ] **Step 2: Make executable and test**

```bash
chmod +x .claude/skills/odh-manifests/quay-tags.sh
.claude/skills/odh-manifests/quay-tags.sh | head -15
```

Expected: 15 lines of tab-separated `tag_name\tdate`, with tags like `main`, `odh-stable`, `pr-NNNN`, `odh-pr-NNNN`.

- [ ] **Step 3: Commit**

```bash
git add .claude/skills/odh-manifests/quay-tags.sh
git commit --signoff -m "feat(odh-manifests): add quay tag fetching script"
```

---

### Task 3: `copy-manifests.sh` — Prepare and Copy Manifests

**Files:**
- Create: `.claude/skills/odh-manifests/copy-manifests.sh`

**Interfaces:**
- Consumes: `oc` CLI (authenticated), local odh-dashboard clone at `~/git/rhoai-work/opendatahub-io/odh-dashboard/manifests/`, a quay image tag as argument
- Produces: Copies edited manifests into the operator pod's volume. Outputs progress messages to stderr, final status to stdout. Creates and cleans up a temp directory (never modifies the repo).

- [ ] **Step 1: Write `copy-manifests.sh`**

```bash
#!/usr/bin/env bash
# Copy dashboard manifests into the operator pod with a specific image tag.
# Usage: copy-manifests.sh <tag>
#   tag: quay.io image tag to set in params.env (e.g. "main", "pr-1234")
# Requires: oc (authenticated), operator pod running with PVC mounted.
set -euo pipefail

TAG="${1:?Usage: copy-manifests.sh <tag>}"
OPERATOR_NS="openshift-operators"
MANIFESTS_SRC="$HOME/git/rhoai-work/opendatahub-io/odh-dashboard/manifests"

if [ ! -d "$MANIFESTS_SRC" ]; then
  echo "ERROR: Manifests source not found at $MANIFESTS_SRC" >&2
  exit 1
fi

# Create temp copy
TMPDIR=$(mktemp -d)
trap 'rm -rf "$TMPDIR"' EXIT
cp -r "$MANIFESTS_SRC/." "$TMPDIR/"

# Edit params.env in the temp copy — core dashboard image
sed -i.bak "s|^odh-dashboard-image=.*|odh-dashboard-image=quay.io/opendatahub/odh-dashboard:${TAG}|" "$TMPDIR/odh/params.env"

# Edit params.env in the temp copy — modular architecture module images
sed -i.bak "s|^model-registry-ui-image=.*|model-registry-ui-image=quay.io/opendatahub/odh-mod-arch-modular-architecture:${TAG}|" "$TMPDIR/modular-architecture/params.env"
sed -i.bak "s|^gen-ai-ui-image=.*|gen-ai-ui-image=quay.io/opendatahub/odh-mod-arch-gen-ai:${TAG}|" "$TMPDIR/modular-architecture/params.env"
sed -i.bak "s|^maas-ui-image=.*|maas-ui-image=quay.io/opendatahub/mod-arch-maas:${TAG}|" "$TMPDIR/modular-architecture/params.env"
sed -i.bak "s|^mlflow-ui-image=.*|mlflow-ui-image=quay.io/opendatahub/odh-mod-arch-mlflow:${TAG}|" "$TMPDIR/modular-architecture/params.env"
sed -i.bak "s|^eval-hub-ui-image=.*|eval-hub-ui-image=quay.io/opendatahub/odh-mod-arch-eval-hub:${TAG}|" "$TMPDIR/modular-architecture/params.env"
sed -i.bak "s|^automl-ui-image=.*|automl-ui-image=quay.io/opendatahub/odh-mod-arch-automl:${TAG}|" "$TMPDIR/modular-architecture/params.env"
sed -i.bak "s|^autorag-ui-image=.*|autorag-ui-image=quay.io/opendatahub/odh-mod-arch-autorag:${TAG}|" "$TMPDIR/modular-architecture/params.env"
sed -i.bak "s|^agent-ops-ui-image=.*|agent-ops-ui-image=quay.io/opendatahub/odh-mod-arch-agent-ops:${TAG}|" "$TMPDIR/modular-architecture/params.env"

# Clean up .bak files (macOS sed creates these)
find "$TMPDIR" -name '*.bak' -delete

echo "Edited params.env files with tag: $TAG" >&2

# Find operator pod
OPERATOR_POD=$(oc get po -l name=opendatahub-operator -n "$OPERATOR_NS" \
  -o jsonpath='{.items[0].metadata.name}' 2>/dev/null)
if [ -z "$OPERATOR_POD" ]; then
  echo "ERROR: No operator pod found in $OPERATOR_NS" >&2
  exit 1
fi
echo "Copying manifests to $OPERATOR_POD:/opt/manifests/dashboard ..." >&2

# Copy into pod
oc cp "$TMPDIR/." "$OPERATOR_NS/$OPERATOR_POD:/opt/manifests/dashboard"

echo "Manifests copied successfully." >&2
echo "Restarting operator to pick up new manifests..." >&2

oc rollout restart deploy -n "$OPERATOR_NS" -l name=opendatahub-operator
oc wait --for='jsonpath={.status.conditions[?(@.type=="Ready")].status}=True' \
  po -l name=opendatahub-operator -n "$OPERATOR_NS" --timeout=120s

echo "Operator restarted. Waiting for dashboard rollout..." >&2
echo "TAG=$TAG"
echo "OPERATOR_POD=$OPERATOR_POD"
```

- [ ] **Step 2: Make executable and test (dry run — verify temp dir creation and sed edits)**

```bash
chmod +x .claude/skills/odh-manifests/copy-manifests.sh

# Dry-run test: just verify the sed edits work correctly
TMPDIR=$(mktemp -d)
cp -r ~/git/rhoai-work/opendatahub-io/odh-dashboard/manifests/. "$TMPDIR/"
sed -i.bak "s|^odh-dashboard-image=.*|odh-dashboard-image=quay.io/opendatahub/odh-dashboard:test-tag|" "$TMPDIR/odh/params.env"
grep 'odh-dashboard-image' "$TMPDIR/odh/params.env"
rm -rf "$TMPDIR"
```

Expected: `odh-dashboard-image=quay.io/opendatahub/odh-dashboard:test-tag`

- [ ] **Step 3: Commit**

```bash
git add .claude/skills/odh-manifests/copy-manifests.sh
git commit --signoff -m "feat(odh-manifests): add manifest copy script with tag substitution"
```

---

### Task 4: `SKILL.md` — Skill Instructions

**Files:**
- Create: `.claude/skills/odh-manifests/SKILL.md`

**Interfaces:**
- Consumes: `status.sh`, `quay-tags.sh`, `copy-manifests.sh` (all in same directory)
- Produces: Claude Code skill invokable as `/odh-manifests`

- [ ] **Step 1: Write `SKILL.md`**

```markdown
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
```

- [ ] **Step 2: Commit**

```bash
git add .claude/skills/odh-manifests/SKILL.md
git commit --signoff -m "feat(odh-manifests): add skill instructions"
```

---

### Task 5: `README.md` and Symlink

**Files:**
- Create: `.claude/skills/odh-manifests/README.md`
- Create: `~/git/claude-skills/odh-manifests` (symlink)

- [ ] **Step 1: Write `README.md`**

```markdown
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
```

- [ ] **Step 2: Create symlink in claude-skills repo**

```bash
ln -s ../../git/rhoai-work/.claude/skills/odh-manifests ~/git/claude-skills/odh-manifests
```

- [ ] **Step 3: Commit skill files**

```bash
cd ~/git/rhoai-work
git add .claude/skills/odh-manifests/README.md
git commit --signoff -m "feat(odh-manifests): add README"
```

- [ ] **Step 4: Commit symlink in claude-skills repo**

```bash
cd ~/git/claude-skills
git add odh-manifests
git commit --signoff -m "feat: add odh-manifests skill symlink"
```

---

### Task 6: End-to-End Verification

**Files:** None (testing only)

- [ ] **Step 1: Verify skill is discoverable**

Check that the skill appears in Claude Code's skill list. The skill name `odh-manifests` should appear in the available skills.

- [ ] **Step 2: Test `status.sh` against the zaffre cluster**

```bash
# Authenticate first
odh-env zaffre
# Run status detection
.claude/skills/odh-manifests/status.sh
```

Expected: JSON with `pvc_exists: true`, `csv_mounted: true`, `operator_replicas: 1`, containers showing `:main` tags, `image_current: true` or `false`.

- [ ] **Step 3: Test `quay-tags.sh`**

```bash
.claude/skills/odh-manifests/quay-tags.sh | head -10
```

Expected: 10 lines of meaningful tags with timestamps.

- [ ] **Step 4: Invoke `/odh-manifests` and walk through the flow**

Run `/odh-manifests` in Claude Code and verify:
1. Cluster confirmation prompt appears
2. Status report is accurate
3. Action menu shows correct options for the current state
4. (Optionally) test the "Update images" action if images are outdated
