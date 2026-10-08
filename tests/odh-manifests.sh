#!/usr/bin/env bash
# Offline regression tests for CSV patch generation and operator rollout waits.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
# shellcheck source=../bin/odh-manifests
source "$ROOT/bin/odh-manifests"

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
no_annotations=$(jq 'del(.metadata.annotations)' <<< "$fixture")
patch=$(build_modular_dashboard_patch "$no_annotations" "$overrides")
jq -e '.[0].path == "/metadata/annotations" and
  .[0].value["odh-manifests.dev/original-dashboard-images"] == "[]"' <<< "$patch" >/dev/null

existing=$(jq '.spec.install.spec.deployments[0].spec.template.spec.containers[0].env =
  [{name: "RELATED_IMAGE_ODH_DASHBOARD_IMAGE", value: "quay.io/opendatahub/odh-dashboard:main"}]' <<< "$fixture")
patch=$(build_modular_dashboard_patch "$existing" "$overrides")
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
