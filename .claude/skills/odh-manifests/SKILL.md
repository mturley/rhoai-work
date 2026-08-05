---
name: odh-manifests
description: Manage custom volume-mounted component manifests on an ODH cluster. Check status, set up, update, switch image tags, or revert to operator-managed. Supports dashboard and modelcontroller (model-serving-api). Use when working with component images on a dev cluster.
disable-model-invocation: true
---

# ODH Component Manifests Manager

All logic lives in the `odh-manifests` script at `bin/odh-manifests` in the
rhoai-work workspace. This skill is a thin wrapper — run the script and help
interpret the results.

## Running it

The script is on PATH as `odh-manifests`.

```bash
odh-manifests status              # show current state
odh-manifests status --json       # machine-readable state
odh-manifests setup dashboard     # create PVC + patch CSV
odh-manifests switch dashboard main
odh-manifests update              # restart dashboard for latest images
odh-manifests revert              # tear down
odh-manifests tags [repo]         # list recent quay tags
```

Run `odh-manifests --help` for the full interface.

## How to use it in a session

1. Run `odh-manifests status` and relay the state to the user in your own words.
2. Ask what they want to do, then run the matching subcommand.
3. **The script prompts for approval before every cluster write**, printing the
   exact command and payload. Let those prompts reach the user — do not pass
   `--yes` unless the user explicitly asks you to skip confirmations.

Because the script handles its own prompting, prefer running a single
subcommand and letting it drive, rather than reimplementing the flow with
separate `oc` calls.

## Where you add value

The script handles the mechanics. You handle judgment:

- **Rollout timeouts.** If `switch`, `update`, or `setup` reports a rollout
  that did not complete, investigate. The script already dumps recent events
  and pod status. Read them and diagnose. A common cause is CPU pressure on
  small dev clusters — suggest deleting unused InferenceServices.
- **Image pull failures.** Check whether the tag actually exists on quay
  (`odh-manifests tags`) before assuming a cluster problem.
- **Choosing a tag.** If the user wants a specific PR's build, help them find
  the right `odh-pr-<number>` tag from `odh-manifests tags`.
- **Cluster mismatch.** The script targets ODH (`opendatahub` namespace,
  `odh-dashboard` deployment). On a RHOAI cluster
  (`redhat-ods-applications` / `rhods-dashboard`) it will report "not set up"
  because those resources don't exist. Check `oc get csv -n openshift-operators`
  and tell the user if they're on the wrong cluster type.

## Components

| Component | Operator path | Key images |
|-----------|--------------|------------|
| `dashboard` | `/opt/manifests/dashboard` | odh-dashboard + all module sidecars |
| `modelcontroller` | `/opt/manifests/modelcontroller` | model-serving-api, odh-model-controller |

The PVC is `custom-odh-dev-manifests` in `openshift-operators`, shared by all
components via subPath mounts.

## Background

This uses the operator's
[component-dev hack](https://github.com/opendatahub-io/opendatahub-operator/tree/main/hack/component-dev):
a PVC is mounted over `/opt/manifests/<component>` in the operator pod, so the
operator reconciles from your manifests instead of the ones baked into its
image. Reverting removes the mount and scales the operator down; deployments
keep running with their last-applied images until the operator comes back.
