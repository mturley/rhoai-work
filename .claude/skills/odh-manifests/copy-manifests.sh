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
