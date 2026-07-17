#!/usr/bin/env bash
# Copy component manifests into the operator pod with specific image tag overrides.
# Usage: copy-manifests.sh <component> [tag]
#   component: "dashboard" or "modelcontroller" (more can be added)
#   tag: quay.io image tag (required for dashboard; optional for modelcontroller)
#
# For dashboard: edits params.env to set all dashboard/module images to the given tag.
# For modelcontroller: clones odh-model-controller repo, edits params.env, copies config/.
#   If tag is provided, sets odh-model-serving-api image to the given tag.
#   If no tag, copies manifests as-is (using upstream defaults).
#
# Requires: oc (authenticated), operator pod running with PVC mounted.
set -euo pipefail

COMPONENT="${1:?Usage: copy-manifests.sh <component> [tag]}"
TAG="${2:-}"
OPERATOR_NS="openshift-operators"

# Find operator pod
OPERATOR_POD=$(oc get po -l name=opendatahub-operator -n "$OPERATOR_NS" \
  -o jsonpath='{.items[0].metadata.name}' 2>/dev/null)
if [ -z "$OPERATOR_POD" ]; then
  echo "ERROR: No operator pod found in $OPERATOR_NS" >&2
  exit 1
fi

case "$COMPONENT" in
  dashboard)
    if [ -z "$TAG" ]; then
      echo "ERROR: tag is required for dashboard component" >&2
      exit 1
    fi
    MANIFESTS_SRC="$HOME/git/rhoai-work/opendatahub-io/odh-dashboard/manifests"
    if [ ! -d "$MANIFESTS_SRC" ]; then
      echo "ERROR: Dashboard manifests not found at $MANIFESTS_SRC" >&2
      exit 1
    fi

    TMPDIR=$(mktemp -d)
    trap 'rm -rf "$TMPDIR"' EXIT
    cp -r "$MANIFESTS_SRC/." "$TMPDIR/"

    sed -i.bak "s|^odh-dashboard-image=.*|odh-dashboard-image=quay.io/opendatahub/odh-dashboard:${TAG}|" "$TMPDIR/odh/params.env"
    sed -i.bak "s|^model-registry-ui-image=.*|model-registry-ui-image=quay.io/opendatahub/odh-mod-arch-modular-architecture:${TAG}|" "$TMPDIR/modular-architecture/params.env"
    sed -i.bak "s|^gen-ai-ui-image=.*|gen-ai-ui-image=quay.io/opendatahub/odh-mod-arch-gen-ai:${TAG}|" "$TMPDIR/modular-architecture/params.env"
    sed -i.bak "s|^maas-ui-image=.*|maas-ui-image=quay.io/opendatahub/mod-arch-maas:${TAG}|" "$TMPDIR/modular-architecture/params.env"
    sed -i.bak "s|^mlflow-ui-image=.*|mlflow-ui-image=quay.io/opendatahub/odh-mod-arch-mlflow:${TAG}|" "$TMPDIR/modular-architecture/params.env"
    sed -i.bak "s|^eval-hub-ui-image=.*|eval-hub-ui-image=quay.io/opendatahub/odh-mod-arch-eval-hub:${TAG}|" "$TMPDIR/modular-architecture/params.env"
    sed -i.bak "s|^automl-ui-image=.*|automl-ui-image=quay.io/opendatahub/odh-mod-arch-automl:${TAG}|" "$TMPDIR/modular-architecture/params.env"
    sed -i.bak "s|^autorag-ui-image=.*|autorag-ui-image=quay.io/opendatahub/odh-mod-arch-autorag:${TAG}|" "$TMPDIR/modular-architecture/params.env"
    sed -i.bak "s|^agent-ops-ui-image=.*|agent-ops-ui-image=quay.io/opendatahub/odh-mod-arch-agent-ops:${TAG}|" "$TMPDIR/modular-architecture/params.env"
    find "$TMPDIR" -name '*.bak' -delete

    echo "Edited dashboard params.env files with tag: $TAG" >&2
    echo "Copying to $OPERATOR_POD:/opt/manifests/dashboard ..." >&2
    oc cp "$TMPDIR/." "$OPERATOR_NS/$OPERATOR_POD:/opt/manifests/dashboard"
    ;;

  modelcontroller)
    TMPDIR=$(mktemp -d)
    trap 'rm -rf "$TMPDIR"' EXIT

    echo "Cloning odh-model-controller config..." >&2
    git clone --depth 1 --filter=blob:none --sparse \
      https://github.com/opendatahub-io/odh-model-controller.git \
      "$TMPDIR/repo" 2>&1 | tail -2 >&2
    git -C "$TMPDIR/repo" sparse-checkout set config 2>&1 >&2

    if [ -n "$TAG" ]; then
      sed -i.bak "s|^odh-model-serving-api=.*|odh-model-serving-api=quay.io/opendatahub/odh-model-serving-api:${TAG}|" "$TMPDIR/repo/config/base/params.env"
      find "$TMPDIR" -name '*.bak' -delete
      echo "Edited modelcontroller params.env: odh-model-serving-api=$TAG" >&2
    else
      echo "Using upstream default images for modelcontroller" >&2
    fi

    echo "Copying to $OPERATOR_POD:/opt/manifests/modelcontroller ..." >&2
    oc cp "$TMPDIR/repo/config/." "$OPERATOR_NS/$OPERATOR_POD:/opt/manifests/modelcontroller"
    ;;

  *)
    echo "ERROR: Unknown component '$COMPONENT'. Supported: dashboard, modelcontroller" >&2
    exit 1
    ;;
esac

echo "Manifests copied successfully." >&2
echo "Restarting operator to pick up new manifests..." >&2

oc rollout restart deploy -n "$OPERATOR_NS" -l name=opendatahub-operator
oc wait --for='jsonpath={.status.conditions[?(@.type=="Ready")].status}=True' \
  po -l name=opendatahub-operator -n "$OPERATOR_NS" --timeout=120s

echo "Operator restarted." >&2
echo "COMPONENT=$COMPONENT"
echo "TAG=${TAG:-default}"
echo "OPERATOR_POD=$OPERATOR_POD"
