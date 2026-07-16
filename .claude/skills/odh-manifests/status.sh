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
csv_name=$(oc get csv -n "$OPERATOR_NS" -o name 2>/dev/null | grep opendatahub-operator | head -n1 | cut -d/ -f2 || echo "")
if [ -n "$csv_name" ]; then
  mounts=$(oc get csv "$csv_name" -n "$OPERATOR_NS" -o jsonpath='{.spec.install.spec.deployments[0].spec.template.spec.containers[0].volumeMounts}' 2>/dev/null || echo "")
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

# Output JSON — pass values via env vars to avoid quoting issues
export PVC_EXISTS="$pvc_exists"
export CSV_MOUNTED="$csv_mounted"
export CSV_NAME="${csv_name:-}"
export OPERATOR_REPLICAS="$operator_replicas"
export OPERATOR_READY="$operator_ready"
export DASHBOARD_NS="$DASHBOARD_NS"
export CONTAINERS_JSON="$containers_json"
export CURRENT_TAG="$current_tag"
export POD_IMAGE_ID="$pod_image_id"
export QUAY_LATEST_DIGEST="$quay_latest_digest"
export IMAGE_CURRENT="$image_current"
export LOCAL_COMMIT="$local_commit"

python3 << 'PYEOF'
import json, os

containers_raw = os.environ.get("CONTAINERS_JSON", "[]")
try:
    containers = json.loads(containers_raw)
except Exception:
    containers = []

print(json.dumps({
    "pvc_exists": os.environ["PVC_EXISTS"] == "true",
    "csv_mounted": os.environ["CSV_MOUNTED"] == "true",
    "csv_name": os.environ.get("CSV_NAME", ""),
    "operator_replicas": int(os.environ.get("OPERATOR_REPLICAS", "0")),
    "operator_ready": int(os.environ.get("OPERATOR_READY", "0")),
    "dashboard_namespace": os.environ.get("DASHBOARD_NS", "opendatahub"),
    "containers": containers,
    "current_tag": os.environ.get("CURRENT_TAG", "unknown"),
    "pod_image_id": os.environ.get("POD_IMAGE_ID", ""),
    "quay_latest_digest": os.environ.get("QUAY_LATEST_DIGEST", ""),
    "image_current": os.environ.get("IMAGE_CURRENT", "unknown"),
    "local_manifests_commit": os.environ.get("LOCAL_COMMIT", "")
}, indent=2))
PYEOF
