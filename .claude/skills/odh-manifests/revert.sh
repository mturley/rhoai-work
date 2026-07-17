#!/usr/bin/env bash
# Revert the custom manifests setup: clean CSV, scale operator to 0, delete PVC.
# Usage: revert.sh
set -euo pipefail

OPERATOR_NS="openshift-operators"
PVC_NAME="custom-odh-dev-manifests"

# 1. Scale operator to 0
echo "Scaling operator to 0..." >&2
oc scale deployment/opendatahub-operator-controller-manager -n "$OPERATOR_NS" --replicas=0 2>/dev/null || true

# 2. Clean CSV
CSV=$(oc get csv -n "$OPERATOR_NS" -o name 2>/dev/null | grep opendatahub-operator | head -n1 | cut -d/ -f2)
if [ -n "$CSV" ]; then
  echo "Cleaning CSV $CSV..." >&2
  oc get csv "$CSV" -n "$OPERATOR_NS" -o json | python3 -c "
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
    if vm.get('name') != 'custom-dev-manifests'
]

pod_spec['volumes'] = [
    v for v in pod_spec.get('volumes', [])
    if v.get('name') != 'custom-dev-manifests'
]

spec['replicas'] = 0
json.dump(csv, sys.stdout)
" | oc replace -f -
  echo "CSV cleaned." >&2
else
  echo "No opendatahub-operator CSV found, skipping CSV cleanup." >&2
fi

# 3. Delete PVC
echo "Deleting PVC $PVC_NAME..." >&2
oc delete pvc "$PVC_NAME" -n "$OPERATOR_NS" --ignore-not-found

echo "Revert complete. Operator is scaled to 0, custom manifests removed." >&2
echo "Note: dashboard deployment still runs with its last images." >&2
