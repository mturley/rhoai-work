#!/usr/bin/env bash
# Offline regression tests for CSV patch generation and operator rollout waits.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
# shellcheck source=../bin/odh-manifests
source "$ROOT/bin/odh-manifests"

(
  source "$ROOT/bin/odh-manifests"
  oc() { printf '%s\n' 'clusterserviceversion/rhods-operator.3.5.2'; }
  configure_cluster_layout
  [[ "$CLUSTER_FLAVOR" == rhoai && "$RHOAI_VERSION" == 3.5.2 && "$OPERATOR_NS" == redhat-ods-operator &&
    "$DASHBOARD_NS" == redhat-ods-applications && "$DASHBOARD_DEPLOY" == rhods-dashboard &&
    "$DASHBOARD_CONTAINER" == rhods-dashboard ]]
  oc() {
    printf '%s\n' '{"metadata":{"ownerReferences":[{"kind":"DataScienceCluster"}]},"spec":{"template":{"spec":{"containers":[{"env":[{"name":"RELATED_IMAGE_ODH_DASHBOARD_IMAGE","value":"quay.io/opendatahub/odh-dashboard:main"}]}]}}}}'
  }
  modular_dashboard_present
)

rhoai_revert_output=$(
  source "$ROOT/bin/odh-manifests"
  CLUSTER_FLAVOR=rhoai
  modular_dashboard_present() { return 0; }
  find_csv() { printf '%s\n' rhods-operator.3.5.2; }
  oc() { printf '%s\n' '{"metadata":{"annotations":{}}}'; }
  confirm_run() { echo MUTATION; }
  cmd_revert
)
! grep -q MUTATION <<< "$rhoai_revert_output"

for version in 3.4.5 3.5.2; do
  setup_output=$(
    source "$ROOT/bin/odh-manifests"
    CLUSTER_FLAVOR=rhoai
    RHOAI_VERSION="$version"
    modular_dashboard_present() { [ "$RHOAI_VERSION" = 3.5.2 ]; }
    ensure_pvc() { echo UNEXPECTED_PVC; }
    cmd_setup dashboard
  )
  ! grep -q UNEXPECTED_PVC <<< "$setup_output"
  output=$(
    source "$ROOT/bin/odh-manifests"
    CLUSTER_FLAVOR=rhoai
    RHOAI_VERSION="$version"
    modular_dashboard_present() { [ "$RHOAI_VERSION" = 3.5.2 ]; }
    copy_legacy_rhoai_dashboard_image() { echo "legacy:$1"; }
    copy_modular_dashboard_images() { echo "modular:$1"; }
    cmd_copy dashboard quay.io/mturley/odh-dashboard:test
  )
  if [ "$version" = 3.4.5 ]; then
    [[ "$output" == 'legacy:quay.io/mturley/odh-dashboard:test' ]]
  else
    [[ "$output" == 'modular:quay.io/mturley/odh-dashboard:test' ]]
  fi
done

if (
  source "$ROOT/bin/odh-manifests"
  CLUSTER_FLAVOR=rhoai
  RHOAI_VERSION=3.5.2
  modular_dashboard_present() { return 1; }
  cmd_copy dashboard quay.io/mturley/odh-dashboard:test
) 2>/dev/null; then
  echo 'RHOAI 3.5 without a module operator should fail' >&2
  exit 1
fi

(
  source "$ROOT/bin/odh-manifests"
  oc() {
    printf '%s\n' '{"items":[{"metadata":{"name":"old-operator","creationTimestamp":"2026-10-08T10:00:00Z","deletionTimestamp":"2026-10-08T10:01:00Z"},"status":{"phase":"Running"}},{"metadata":{"name":"current-operator","creationTimestamp":"2026-10-08T10:02:00Z"},"status":{"phase":"Running"}}]}'
  }
  [[ $(find_operator_pod) == current-operator ]]
)

copy_retry_output=$(
  source "$ROOT/bin/odh-manifests"
  copy_attempts=0
  find_operator_pod() { if [ "$copy_attempts" = 0 ]; then echo old-operator; else echo current-operator; fi; }
  confirm_run() { copy_attempts=$((copy_attempts + 1)); [ "$copy_attempts" -gt 1 ]; }
  oc() { [ "$3" != old-operator ]; }
  sleep() { :; }
  copy_to_operator /tmp/manifests /opt/manifests/dashboard 2>&1
)
grep -q 'retrying with the current pod' <<< "$copy_retry_output"

(
  source "$ROOT/bin/odh-manifests"
  CLUSTER_FLAVOR=rhoai
  RHOAI_VERSION=3.4.5
  DASHBOARD_DEPLOY=rhods-dashboard
  DASHBOARD_NS=redhat-ods-applications
  DASHBOARD_CONTAINER=rhods-dashboard
  oc() {
    printf '%s\n' '{"spec":{"template":{"spec":{"containers":[{"name":"rhods-dashboard","image":"quay.io/mturley/odh-dashboard:test"}]}}}}'
  }
  sleep() { :; }
  wait_for_legacy_dashboard_image quay.io/mturley/odh-dashboard:test 5
)

fixture='{"metadata":{"annotations":{}},"spec":{"install":{"spec":{"deployments":[{"spec":{"replicas":0,"template":{"spec":{"containers":[{"env":[]}],"volumes":[]}}}}]}}}}'

patch=$(build_csv_patch "$fixture" '["dashboard","modelcontroller"]')
jq -e '[.[] | select(.path | endswith("/volumeMounts"))] |
  length == 1 and (.[0].value | map(.subPath) == ["dashboard", "modelcontroller"])' <<< "$patch" >/dev/null

overrides=$(modular_dashboard_images pr-10142)
[[ $(jq -r '.[0].value' <<< "$(modular_dashboard_images quay.io/example/dashboard:dev)") == quay.io/example/dashboard:dev ]]
patch=$(build_modular_dashboard_patch "$fixture" "$overrides")
jq -e 'length == 3 and
  ([.[] | select(.path | endswith("/replicas"))] | length == 1) and
  ([.[] | select(.path | endswith("/env/-"))] | length == 1) and
  ([.[] | select(.path | contains("original-dashboard-images"))] | length == 1) and
  ([.[] | select(.value.name? == "RELATED_IMAGE_ODH_DASHBOARD_IMAGE")][0].value.value
    == "quay.io/opendatahub/odh-dashboard:pr-10142")' <<< "$patch" >/dev/null
legacy_output=$(
  source "$ROOT/bin/odh-manifests"
  CLUSTER_FLAVOR=rhoai
  RHOAI_VERSION=3.4.5
  find_csv() { echo rhods-operator.3.4.5; }
  oc() { echo "$fixture"; }
  confirm_run() { printf '%s\n' "$*"; }
  wait_for_operator() { :; }
  wait_for_legacy_dashboard_image() { :; }
  copy_legacy_rhoai_dashboard_image quay.io/mturley/odh-dashboard:test
)
legacy_patch=$(printf '%s\n' "$legacy_output" | grep '^oc patch csv' | grep -o '\[{.*')
jq -e 'any(.[]; .path | contains("original-dashboard-images")) and
  any(.[]; .value.value? == "quay.io/mturley/odh-dashboard:test") and
  all(.[]; .path != "/spec/install/spec/deployments/0/spec/replicas")' <<< "$legacy_patch" >/dev/null
no_annotations=$(jq 'del(.metadata.annotations)' <<< "$fixture")
patch=$(build_modular_dashboard_patch "$no_annotations" "$overrides")
jq -e '.[0].path == "/metadata/annotations" and
  .[0].value["odh-manifests.dev/original-dashboard-images"] == "[]"' <<< "$patch" >/dev/null

existing=$(jq '.spec.install.spec.deployments[0].spec.template.spec.containers[0].env =
  [{name: "RELATED_IMAGE_ODH_DASHBOARD_IMAGE", value: "quay.io/opendatahub/odh-dashboard:main"}]' <<< "$fixture")
patch=$(build_modular_dashboard_patch "$existing" "$overrides")
legacy_patch=$(jq -c '[.[] | select(.path != "/spec/install/spec/deployments/0/spec/replicas")]' <<< "$patch")
jq -e 'all(.[]; .path != "/spec/install/spec/deployments/0/spec/replicas")' <<< "$legacy_patch" >/dev/null
jq -e '([.[] | select(.op == "replace" and (.path | endswith("/env/0")))] | length == 1) and
  (.[0].value | fromjson | .[0].value == "quay.io/opendatahub/odh-dashboard:main")' <<< "$patch" >/dev/null

active=$(jq '.metadata.annotations["odh-manifests.dev/original-dashboard-images"] =
    "[{\"name\":\"RELATED_IMAGE_ODH_DASHBOARD_IMAGE\",\"value\":\"quay.io/opendatahub/odh-dashboard:main\"}]" |
  .spec.install.spec.deployments[0].spec.template.spec.containers[0].env =
    [{name: "OTHER", value: "keep"}, {name: "RELATED_IMAGE_ODH_DASHBOARD_IMAGE", value: "quay.io/opendatahub/odh-dashboard:pr-10142"}]' <<< "$fixture")
patch=$(build_modular_restore_patch "$active" '["RELATED_IMAGE_ODH_DASHBOARD_IMAGE"]' \
  '[{"name":"RELATED_IMAGE_ODH_DASHBOARD_IMAGE","value":"quay.io/opendatahub/odh-dashboard:main"}]')
jq -e 'length == 3 and
  .[0].path == "/spec/install/spec/deployments/0/spec/template/spec/containers/0/env/1" and
  .[1].value.value == "quay.io/opendatahub/odh-dashboard:main" and
  .[2].path == "/metadata/annotations/odh-manifests.dev~1original-dashboard-images"' <<< "$patch" >/dev/null
patch=$(build_modular_restore_patch "$active" '["RELATED_IMAGE_ODH_DASHBOARD_IMAGE"]' '[]')
jq -e 'length == 2 and .[0].op == "remove" and .[1].op == "remove"' <<< "$patch" >/dev/null

pending_status='{"pvc_exists":false,"modular_dashboard":true,"overridden_components":["dashboard"],"operator_replicas":1,"configured_dashboard_image":"quay.io/opendatahub/odh-dashboard:pr-10142","containers":[{"name":"odh-dashboard","image":"quay.io/opendatahub/odh-dashboard:pr-10028"}]}'
[[ $(describe_state "$pending_status") == 'waiting for dashboard image' ]]

image='quay.io/opendatahub/odh-dashboard:pr-10142'
[[ $(dashboard_image_freshness "$image" 'quay.io/opendatahub/odh-dashboard:pr-10028' true 'image@sha256:old' 'sha256:new') == pending ]]
[[ $(dashboard_image_freshness "$image" "$image" false 'image@sha256:old' 'sha256:new') == pending ]]
[[ $(dashboard_image_freshness "$image" "$image" true 'image@sha256:old' 'sha256:new') == false ]]
[[ $(dashboard_image_freshness "$image" "$image" true 'image@sha256:new' 'sha256:new') == true ]]
[[ $(dashboard_image_freshness "$image" "$image" true 'image@sha256:new' '') == unknown ]]

# Mock oc: no cluster requests are made by this test.
oc() { printf '%s\n' "$*"; }
output=$(wait_for_operator 5s)
grep -Fx 'wait --for=create deployment/opendatahub-operator-controller-manager -n openshift-operators --timeout=5s' <<< "$output" >/dev/null
grep -Fx 'rollout status deployment/opendatahub-operator-controller-manager -n openshift-operators --timeout=5s' <<< "$output" >/dev/null

oc() {
  case "$1 $2 $3" in
    'get deployment dashboard-operator')
      printf '%s\n' '{"spec":{"template":{"spec":{"containers":[{"name":"manager","env":[{"name":"RELATED_IMAGE_ODH_DASHBOARD_IMAGE","value":"quay.io/opendatahub/odh-dashboard:pr-10142"}]}]}}}}' ;;
    'get deployment odh-dashboard')
      printf '%s\n' '{"spec":{"template":{"spec":{"containers":[{"name":"odh-dashboard","image":"quay.io/opendatahub/odh-dashboard:pr-10142"}]}}}}' ;;
    'rollout status deployment/dashboard-operator') return 0 ;;
    *) return 1 ;;
  esac
}
wait_for_dashboard_image 'quay.io/opendatahub/odh-dashboard:pr-10142' 5

cmd_copy() { printf 'copied %s %s\n' "$1" "$2"; }
watch_rollout() { printf 'rolled out %s\n' "$1"; }
gather_status() { printf 'fresh state\n'; }
print_status() { printf 'status: %s\n' "$1"; }
[[ $(cmd_switch dashboard pr-10142) == $'copied dashboard pr-10142\nrolled out odh-dashboard\nstatus: fresh state' ]]

printf 'odh-manifests offline tests passed\n'
