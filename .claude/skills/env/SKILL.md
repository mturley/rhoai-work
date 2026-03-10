---
name: env
description: Switch the active cluster and/or user in the odh-dashboard .env.local file.
---

Switch the active cluster and/or user in the `.env.local` file at `opendatahub-io/odh-dashboard/.env.local`.

## Steps

1. **Read the file** at `opendatahub-io/odh-dashboard/.env.local`.

2. **Parse the sections.** Each cluster section is delimited by `# ===========` lines. The section header comment contains the cluster name. A section is ACTIVE if its env vars are uncommented (no `# ` prefix). Alternative values use the `## alt: ` prefix. Info URLs use `## url: ` prefix.

3. **Identify the currently active cluster** (the one with uncommented env vars) and its current settings (OC_USER, OC_PROJECT, ODH_APP).

4. **Ask the user what to change** using AskUserQuestion. Ask up to 2 questions:

   - **Cluster**: "Which cluster do you want to connect to?" — List all available cluster names parsed from section headers. Put the currently active one first with "(current)" in its label. Only ask this if there are 4 or fewer clusters; otherwise list them as text output and ask the user to pick by typing. The user may also provide a cluster name as an argument to the `/env` command (e.g. `/env Green Scrum 1`), in which case skip asking and use that cluster.

   - **User**: "Which user?" — List the available OC_USER values for the selected cluster (the default value and any `## alt:` values). Only ask this if the selected cluster has alternative OC_USER values. Put the current/default one first.

5. **Apply the changes** by editing the file:
   - Comment all env vars in the previously active section (add `# ` prefix to each var line, but don't touch `## alt:` or `## url:` lines).
   - Uncomment all env vars in the newly selected section (remove `# ` prefix from var lines, but don't touch `## alt:` lines).
   - If the user selected an alternative OC_USER, swap it: add `## alt: ` prefix to the current OC_USER line and remove the `## alt: ` prefix from the selected one.
   - Update the section header comments: add `(ACTIVE)` to the new cluster's header and remove it from the old one.

6. **Log in** by running `make login` from the `opendatahub-io/odh-dashboard` directory, then run `oc cluster-info` and `oc whoami` to verify the connection.

7. **Confirm** by printing a summary of the new active configuration (cluster name, OC_URL, OC_USER, OC_PROJECT, ODH_APP). Also include any `## url:` lines from the active cluster's section as clickable links, labeled by their prefix (e.g. "OCP", "ODH", "Console").
