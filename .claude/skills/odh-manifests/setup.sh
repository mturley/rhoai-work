#!/usr/bin/env bash
# Set up the custom manifests PVC and CSV patches for the ODH operator.
# Usage: setup.sh [component...]
#   component: one or more of "dashboard", "modelcontroller" (default: dashboard)
# Creates the PVC if it doesn't exist, patches the CSV with volume + subPath mounts,
# and ensures the operator is running with replicas=1, Recreate strategy, fsGroup=1001.
# Idempotent: skips PVC creation if it exists, skips CSV patches if mounts already present.
set -euo pipefail

OPERATOR_NS="openshift-operators"
PVC_NAME="custom-odh-dev-manifests"

# Components to set up (default: dashboard)
if [ $# -eq 0 ]; then
  COMPONENTS=("dashboard")
else
  COMPONENTS=("$@")
fi

# Component → operator manifest path mapping
declare -A MOUNT_PATHS
MOUNT_PATHS[dashboard]="/opt/manifests/dashboard"
MOUNT_PATHS[modelcontroller]="/opt/manifests/modelcontroller"

# 1. Create PVC if needed
if oc get pvc "$PVC_NAME" -n "$OPERATOR_NS" &>/dev/null; then
  echo "PVC $PVC_NAME already exists, skipping creation." >&2
else
  echo "Creating PVC $PVC_NAME..." >&2
  oc apply -f - <<EOF
apiVersion: v1
kind: PersistentVolumeClaim
metadata:
  name: $PVC_NAME
  namespace: $OPERATOR_NS
spec:
  accessModes: [ReadWriteOnce]
  resources:
    requests:
      storage: 200Mi
EOF
fi

# 2. Patch CSV
CSV=$(oc get csv -n "$OPERATOR_NS" -o name 2>/dev/null | grep opendatahub-operator | head -n1 | cut -d/ -f2)
if [ -z "$CSV" ]; then
  echo "ERROR: No opendatahub-operator CSV found" >&2
  exit 1
fi

# Get current state
CSV_JSON=$(oc get csv "$CSV" -n "$OPERATOR_NS" -o json)

# Check what's already there
NEEDS_PATCH="false"
PATCH_OPS="[]"

PATCH_OPS=$(echo "$CSV_JSON" | python3 -c "
import json, sys

csv = json.load(sys.stdin)
deploy = csv['spec']['install']['spec']['deployments'][0]
spec = deploy['spec']
pod_spec = spec['template']['spec']
container = pod_spec['containers'][0]
mounts = container.get('volumeMounts', [])
volumes = pod_spec.get('volumes', [])

components = sys.argv[1:]
pvc_name = '$PVC_NAME'

ops = []

# Ensure replicas=1
if spec.get('replicas', 1) != 1:
    ops.append({'op': 'replace', 'path': '/spec/install/spec/deployments/0/spec/replicas', 'value': 1})

# Ensure Recreate strategy
if spec.get('strategy', {}).get('type') != 'Recreate':
    ops.append({'op': 'add', 'path': '/spec/install/spec/deployments/0/spec/strategy', 'value': {'type': 'Recreate'}})

# Ensure fsGroup
sc = pod_spec.get('securityContext', {})
if sc.get('fsGroup') != 1001:
    if 'securityContext' not in pod_spec:
        ops.append({'op': 'add', 'path': '/spec/install/spec/deployments/0/spec/template/spec/securityContext', 'value': {'fsGroup': 1001}})
    else:
        ops.append({'op': 'add', 'path': '/spec/install/spec/deployments/0/spec/template/spec/securityContext/fsGroup', 'value': 1001})

# Ensure the PVC volume exists
vol_exists = any(v.get('name') == 'custom-dev-manifests' for v in volumes)
if not vol_exists:
    ops.append({
        'op': 'add',
        'path': '/spec/install/spec/deployments/0/spec/template/spec/volumes/-',
        'value': {'name': 'custom-dev-manifests', 'persistentVolumeClaim': {'claimName': pvc_name}}
    })

# Ensure each component has a volumeMount with subPath
for comp in components:
    mount_path = {
        'dashboard': '/opt/manifests/dashboard',
        'modelcontroller': '/opt/manifests/modelcontroller',
    }.get(comp)
    if not mount_path:
        print(f'ERROR: Unknown component {comp}', file=sys.stderr)
        sys.exit(1)
    mount_exists = any(
        m.get('name') == 'custom-dev-manifests' and m.get('subPath') == comp
        for m in mounts
    )
    if not mount_exists:
        ops.append({
            'op': 'add',
            'path': '/spec/install/spec/deployments/0/spec/template/spec/containers/0/volumeMounts/-',
            'value': {'name': 'custom-dev-manifests', 'mountPath': mount_path, 'subPath': comp}
        })

json.dump(ops, sys.stdout)
" "${COMPONENTS[@]}")

if [ "$PATCH_OPS" = "[]" ]; then
  echo "CSV already has all required patches, skipping." >&2
else
  echo "Patching CSV $CSV..." >&2
  oc patch csv "$CSV" -n "$OPERATOR_NS" --type json -p "$PATCH_OPS"
fi

# 3. Wait for operator pod
echo "Waiting for operator pod..." >&2
oc wait --for='jsonpath={.status.conditions[?(@.type=="Ready")].status}=True' \
  po -l name=opendatahub-operator -n "$OPERATOR_NS" --timeout=120s

echo "Setup complete. Operator is running with custom manifest mounts for: ${COMPONENTS[*]}" >&2
echo "COMPONENTS=${COMPONENTS[*]}"
