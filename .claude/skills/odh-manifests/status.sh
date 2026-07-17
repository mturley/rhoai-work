#!/usr/bin/env bash
# Detect the state of custom volume-mounted ODH component manifests on a cluster.
# Outputs JSON to stdout. Requires: oc (authenticated), curl, python3.
set -euo pipefail

OPERATOR_NS="openshift-operators"
DASHBOARD_NS="opendatahub"
PVC_NAME="custom-odh-dev-manifests"
MANIFESTS_REPO="$HOME/git/rhoai-work/opendatahub-io/odh-dashboard"

# 1. PVC check
pvc_exists="false"
if oc get pvc "$PVC_NAME" -n "$OPERATOR_NS" &>/dev/null; then
  pvc_exists="true"
fi

# 2. CSV volume mount check — find all custom-dev-manifests mounts and their subPaths
csv_name=$(oc get csv -n "$OPERATOR_NS" -o name 2>/dev/null | grep opendatahub-operator | head -n1 | cut -d/ -f2 || echo "")
overridden_components="[]"
if [ -n "$csv_name" ]; then
  overridden_components=$(oc get csv "$csv_name" -n "$OPERATOR_NS" -o jsonpath='{.spec.install.spec.deployments[0].spec.template.spec.containers[0].volumeMounts}' 2>/dev/null | python3 -c "
import json, sys
mounts = json.load(sys.stdin)
components = []
for m in mounts:
    if m.get('name') == 'custom-dev-manifests' and 'subPath' in m:
        components.append(m['subPath'])
json.dump(components, sys.stdout)
" 2>/dev/null || echo "[]")
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

# 7. Quay digest comparison for dashboard
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

# 9. Other overridden component details (non-dashboard)
other_components_json=$(echo "$overridden_components" | python3 -c "
import json, sys, subprocess
components = json.load(sys.stdin)
result = []
for comp in components:
    if comp == 'dashboard':
        continue
    # Try to find the deployment and image for known components
    deploy_map = {
        'modelcontroller': [
            {'deployment': 'model-serving-api', 'container': 'server'},
            {'deployment': 'odh-model-controller', 'container': 'manager'}
        ],
        'kserve': [{'deployment': 'kserve-controller-manager', 'container': 'manager'}],
        'modelregistry': [{'deployment': 'model-registry-operator-controller-manager', 'container': 'manager'}],
    }
    deploys = deploy_map.get(comp, [])
    comp_info = {'name': comp, 'deployments': []}
    for d in deploys:
        try:
            img = subprocess.check_output(
                ['oc', 'get', 'deployment', d['deployment'], '-n', 'opendatahub',
                 '-o', 'jsonpath={.spec.template.spec.containers[?(@.name==\"' + d['container'] + '\")].image}'],
                stderr=subprocess.DEVNULL, text=True).strip()
            if img:
                tag = img.rsplit(':', 1)[1] if ':' in img else 'latest'
                comp_info['deployments'].append({'deployment': d['deployment'], 'image': img, 'tag': tag})
        except Exception:
            pass
    result.append(comp_info)
json.dump(result, sys.stdout)
" 2>/dev/null || echo "[]")

# Output JSON
export PVC_EXISTS="$pvc_exists"
export CSV_NAME="${csv_name:-}"
export OVERRIDDEN_COMPONENTS="$overridden_components"
export OPERATOR_REPLICAS="$operator_replicas"
export OPERATOR_READY="$operator_ready"
export DASHBOARD_NS="$DASHBOARD_NS"
export CONTAINERS_JSON="$containers_json"
export CURRENT_TAG="$current_tag"
export POD_IMAGE_ID="$pod_image_id"
export QUAY_LATEST_DIGEST="$quay_latest_digest"
export IMAGE_CURRENT="$image_current"
export LOCAL_COMMIT="$local_commit"
export OTHER_COMPONENTS="$other_components_json"

python3 << 'PYEOF'
import json, os

containers_raw = os.environ.get("CONTAINERS_JSON", "[]")
try:
    containers = json.loads(containers_raw)
except Exception:
    containers = []

overridden_raw = os.environ.get("OVERRIDDEN_COMPONENTS", "[]")
try:
    overridden = json.loads(overridden_raw)
except Exception:
    overridden = []

other_raw = os.environ.get("OTHER_COMPONENTS", "[]")
try:
    other_components = json.loads(other_raw)
except Exception:
    other_components = []

print(json.dumps({
    "pvc_exists": os.environ["PVC_EXISTS"] == "true",
    "pvc_name": "custom-odh-dev-manifests",
    "csv_name": os.environ.get("CSV_NAME", ""),
    "overridden_components": overridden,
    "operator_replicas": int(os.environ.get("OPERATOR_REPLICAS", "0")),
    "operator_ready": int(os.environ.get("OPERATOR_READY", "0")),
    "dashboard_namespace": os.environ.get("DASHBOARD_NS", "opendatahub"),
    "containers": containers,
    "current_tag": os.environ.get("CURRENT_TAG", "unknown"),
    "pod_image_id": os.environ.get("POD_IMAGE_ID", ""),
    "quay_latest_digest": os.environ.get("QUAY_LATEST_DIGEST", ""),
    "image_current": os.environ.get("IMAGE_CURRENT", "unknown"),
    "local_manifests_commit": os.environ.get("LOCAL_COMMIT", ""),
    "other_components": other_components
}, indent=2))
PYEOF
