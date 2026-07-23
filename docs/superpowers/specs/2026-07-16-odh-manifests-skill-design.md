# `/odh-manifests` Skill Design

## Purpose

A Claude Code skill for managing custom volume-mounted dashboard manifests on an ODH cluster. This uses the [component-dev hack](https://github.com/opendatahub-io/opendatahub-operator/tree/main/hack/component-dev) from the operator repo to override the dashboard images the operator deploys — typically to run `:main` or a PR branch tag instead of the operator's built-in version.

The skill replaces a manual multi-step process (create PVC, patch CSV, copy manifests, restart operator) with a single `/odh-manifests` command that detects the current state and offers relevant actions.

## Location

- Primary: `/Users/mturley/git/rhoai-work/.claude/skills/odh-manifests/SKILL.md`
- Symlink: `~/git/claude-skills/odh-manifests` -> `../../git/rhoai-work/.claude/skills/odh-manifests`

## Flow

### Phase 1: Cluster Authentication & Confirmation

1. Run `oc cluster-info` and `oc whoami`
2. If auth fails → abort with message to re-authenticate
3. Present cluster URL and user to the human via AskUserQuestion: "Is this the right cluster?"
4. If user says no → abort

### Phase 2: Detect Setup State

Check these indicators:

| Check | Command | Meaning |
|-------|---------|---------|
| PVC exists | `oc get pvc dashboard-dev-manifests -n openshift-operators` | Volume for custom manifests is provisioned |
| CSV patched | Check CSV for volumeMount at `/opt/manifests/dashboard` | Operator is configured to read custom manifests |
| Operator running | Check deployment replicas > 0 | Operator is actively reconciling |
| Dashboard images | `oc get deployment odh-dashboard -n opendatahub` container images | What tag/version is currently running |
| Current tag | Infer from image tags (`:main`, `:v3.4.3-odh`, etc.) | What was configured |

### Phase 3: Report Status

Present a clear status summary. Examples:

**Setup active:**
```
Custom manifests: Active (tag: main)
  PVC:        dashboard-dev-manifests ✓
  CSV mount:  /opt/manifests/dashboard ✓
  Operator:   Running (1 replica)
  Dashboard:  quay.io/opendatahub/odh-dashboard:main
              Built: 2026-07-15 (12h ago), commit c7924e39
  Image sync: Up to date (matches quay.io latest)
```

**Not set up:**
```
Custom manifests: Not detected
  PVC:        Not found
  Operator:   Scaled to 0 (or running with built-in manifests)
  Dashboard:  quay.io/opendatahub/odh-dashboard:v3.4.3-odh
              Built: 2026-06-09 (34 days old)
```

### Phase 4: Offer Contextual Actions

Present relevant actions via AskUserQuestion based on detected state.

**If NOT set up:**
- **Set up custom manifests** — full setup flow (see below)

**If set up and images outdated:**
- **Update images** — rollout restart to pull latest for current tag
- **Switch tag** — change to a different quay tag
- **Revert** — tear down custom setup, return to operator-managed

**If set up and images current:**
- **Switch tag** — change to a different quay tag
- **Force update** — rollout restart even though images match
- **Revert** — tear down custom setup

## Action: Set Up Custom Manifests

1. Ask user for quay image tag via AskUserQuestion:
   - Option 1: `main` (recommended)
   - Option 2: "Another tag" — if selected, fetch recent tags from the Quay API (`https://quay.io/api/v1/repository/opendatahub/odh-dashboard/tag/?limit=20&onlyActiveTags=true`) and present them as options (sorted by last_modified, most recent first). The user can pick one or type a custom tag.

2. Present the plan:
   - Create PVC `dashboard-dev-manifests` in `openshift-operators`
   - Patch the CSV to mount PVC at `/opt/manifests/dashboard` (sets replicas=1, strategy=Recreate, fsGroup=1001)
   - Wait for operator pod
   - Edit `params.env` files to use the chosen tag
   - Copy manifests from local clone into operator pod
   - Restart operator to pick up manifests
   - Monitor dashboard rollout

3. Ask user to confirm before proceeding.

4. Execute, reporting progress at each step. If any step fails, stop and report the error with context.

5. After rollout completes, run a final status check and report.

### Editing params.env for the chosen tag

The tag needs to be applied to two files before copying:

- `manifests/odh/params.env` — set `odh-dashboard-image=quay.io/opendatahub/odh-dashboard:<tag>`
- `manifests/modular-architecture/params.env` — set all module images to `:<tag>`

Important: edit temporary copies, not the repo files. Use a temp directory, copy manifests there, edit params.env, then `oc cp` the temp copy.

The image names per container are:
- `odh-dashboard-image` → `quay.io/opendatahub/odh-dashboard:<tag>`
- `model-registry-ui-image` → `quay.io/opendatahub/odh-mod-arch-modular-architecture:<tag>`
- `gen-ai-ui-image` → `quay.io/opendatahub/odh-mod-arch-gen-ai:<tag>`
- `maas-ui-image` → `quay.io/opendatahub/mod-arch-maas:<tag>`
- `mlflow-ui-image` → `quay.io/opendatahub/odh-mod-arch-mlflow:<tag>`
- `eval-hub-ui-image` → `quay.io/opendatahub/odh-mod-arch-eval-hub:<tag>`
- `automl-ui-image` → `quay.io/opendatahub/odh-mod-arch-automl:<tag>`
- `autorag-ui-image` → `quay.io/opendatahub/odh-mod-arch-autorag:<tag>`
- `agent-ops-ui-image` → `quay.io/opendatahub/odh-mod-arch-agent-ops:<tag>`

## Action: Update Images

1. `oc rollout restart deployment/odh-dashboard -n opendatahub`
2. Monitor with `oc rollout status --timeout=300s`
3. If rollout stalls, troubleshoot:
   - Check pod events for scheduling failures (CPU/memory pressure)
   - Check container statuses for CrashLoopBackOff
   - Check liveness/readiness probe failures
   - Report findings with suggested fixes
4. Final status check.

## Action: Switch Tag

1. Ask user for new tag.
2. Present the plan:
   - Copy manifests to temp dir
   - Edit params.env with new tag
   - Copy into operator pod
   - Restart operator
   - Monitor dashboard rollout
3. Confirm, execute, monitor (same as setup but skips PVC/CSV steps).

## Action: Revert

1. Present the plan:
   - Scale operator to 0
   - Remove volume mount, volumes, fsGroup, Recreate strategy from CSV
   - Delete PVC
   - Note: dashboard deployment will remain as-is with whatever images it had
2. Confirm before proceeding.
3. Execute each step, reporting progress.
4. Final status check.

## Manifest Source

The skill uses the local clone at `~/git/rhoai-work/opendatahub-io/odh-dashboard/manifests/`. If the user wants the latest manifests, they should `git pull` in that repo first. The skill should note the current commit of the local clone when reporting status.

## Error Handling

- Auth failure → abort with re-login instructions
- PVC creation failure → report and abort
- CSV patch failure → report and abort (note: patch is not idempotent, warn if volume mount already exists)
- `oc cp` failure → report and abort
- Rollout timeout → enter troubleshooting mode (pod events, container status, resource pressure)
- Operator pod not starting → check events, report

## Non-Goals

- This skill does not manage non-dashboard components (kserve, model-registry operator, etc.)
- It does not modify the local git clone (uses temp copies for params.env edits)
- It does not handle RHOAI clusters (only ODH)
