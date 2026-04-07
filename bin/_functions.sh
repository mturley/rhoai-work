# Shell functions for rhoai-work workspace navigation
# Source this file from your shell rc — don't execute it directly.
# These must be shell functions (not scripts) because they change the caller's working directory.

RHOAI_WORK=~/git/rhoai-work
ODH_DASHBOARD=$RHOAI_WORK/opendatahub-io/odh-dashboard
KFMR_DIR=$RHOAI_WORK/kubeflow/model-registry

cdwork()          { cd "$RHOAI_WORK"; }

odh()             { if git remote -v 2>/dev/null | grep -q "odh-dashboard"; then cd "$(git rev-parse --show-toplevel)"; else cd "$ODH_DASHBOARD"; fi; }
odh-mr()          { odh && cd packages/model-registry; }
odh-mr-upstream() { odh && cd packages/model-registry/upstream; }

kfmr()            { if git remote -v 2>/dev/null | grep -q "model-registry"; then cd "$(git rev-parse --show-toplevel)"; else cd "$KFMR_DIR"; fi; }
kfmr-ui()         { kfmr && cd clients/ui; }
kfmr-frontend()   { kfmr-ui && cd frontend; }
kfmr-bff()        { kfmr-ui && cd bff; }
