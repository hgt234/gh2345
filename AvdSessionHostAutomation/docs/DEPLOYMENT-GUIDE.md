# Deployment guide

End-to-end setup for this solution in a fresh Azure DevOps (ADO) project
repository: repository import, service connection, variable groups, the
pipeline definitions to create, permissions, branch protection, power
management, and first-build acceptance.

Who does what is called out per step. The permissions requested from other
teams are explained in
[SERVICE-ACCOUNTS-AND-PERMISSIONS.md](SERVICE-ACCOUNTS-AND-PERMISSIONS.md);
this guide covers the order and the mechanics.

> Conditional Access is out of scope. Do not change it as part of this setup.

## 1. Pipelines to build

Create exactly **two** pipeline definitions. Everything else is either a
one-time administrative action or a deliberate non-goal.

| Pipeline definition | YAML | Runs when | Service connection | Purpose |
|---|---|---|---|---|
| **AVD - Provision Session Host** | `pipelines/azure-pipelines-avd-provision.yml` | Queued by a technician (Run pipeline panel or `technician/Start-AvdBuild.ps1`) or by ServiceNow | The shared AVD connection | Builds, checks, and assigns one desktop per RITM |
| **AVD - CI Validate** | `pipelines/ci-validate.yml` | Automatically on every pull request to `main`, through a branch policy | None | Lint, offline tests, and Bicep compile; deploys nothing |

Design notes:

- **One provision pipeline, two entry modes.** Technician and ServiceNow
  requests use the same definition. Supplying `ritmSysId` switches on the
  ServiceNow callbacks. Do not create a separate "manual" pipeline: two
  copies of the build logic drift apart.
- **One pipeline for all workloads.** A workload is a variable group
  (`avd-prod-<workload>`) plus an entry in the YAML `workload` list, not a new
  pipeline.
- **The CI pipeline has no triggers of its own on Azure Repos.** Azure Repos
  ignores YAML `pr:` triggers, so it runs only through the branch policy in
  step 9.

Not built as pipelines, on purpose:

| Activity | How it is done instead | Why not a pipeline |
|---|---|---|
| Deploy custom roles (`infra/access.bicep`) | Elevated administrator, once per workload, from a workstation or Cloud Shell (step 4.3). Not needed with group-based user access and self-deallocate off | Creating role definitions needs rights the shared Contributor connection does not have, and a standing elevated connection for a once-a-year task is more risk than value |
| Start VM on Connect role and host-pool setting | One-time administrator action (step 6) | Single assignment, never repeated |
| Decommission or teardown | Separate, human-approved process | Deleting resources is excluded from this solution by design |

Candidates to add later, only if the need appears:

- **Access deployment pipeline**: if workloads are added often, wrap
  `access.bicep` (what-if, then deploy) in a pipeline that uses a *separate*
  elevated connection behind an ADO environment with required approvers.
- **Self-deallocate backfill**: a small pipeline that grants the
  self-deallocate role to VMs built before it was enabled. Today, re-running
  the provision pipeline for the RITM does the same.

## 2. Prerequisites

Confirm before starting:

- [ ] The AVD subscription, peered VNet and subnet, personal host pool,
      desktop application group, and workspace exist.
- [ ] The host pool is **Personal** with **Direct** assignment.
- [ ] Its custom RDP properties include `targetisaadjoined:i:1` and
      `enablerdsaadauth:i:1`.
- [ ] Windows automatic MDM enrollment is configured in the tenant.
- [ ] A Compute Gallery image definition (or the Marketplace fallback) is
      chosen for session hosts.
- [ ] Quota for the session-host VM family is available in the region.
- [ ] You hold ADO **Project Administrator** (or Build Administrator plus
      Endpoint Administrator) in the target project.
- [ ] The ADO team has confirmed which existing service connection to use.

## 3. Create the repository

**Who:** ADO engineer.

1. In ADO, **Repos > Files > New repository** (or the repository dropdown >
   **New repository**). Use type **Git**, a name such as
   `avd-session-host-automation`, and leave it empty (no README, no
   `.gitignore`).
2. Clone it to your workstation.
3. Copy the **contents** of this folder into the root of the clone, not the
   folder itself. The pipelines use repository-root paths such as
   `scripts/...`; a nested folder breaks them.
4. Make sure the hidden **`.gitignore`** came across. File Explorer hides
   dotfiles by default, and `.gitignore` is what keeps the technician settings
   file and run reports out of the repository. From PowerShell:

   ```powershell
   Copy-Item -Path '<source>\AvdSessionHostAutomation\*' -Destination '<clone>' -Recurse -Force
   Copy-Item -LiteralPath '<source>\AvdSessionHostAutomation\.gitignore' -Destination '<clone>' -Force
   Get-ChildItem -LiteralPath '<clone>' -Force | Select-Object Name
   ```

5. Commit and push to `main`. Confirm `main` is the default branch under
   **Project settings > Repositories > (repository) > Branches** (or Repos >
   Branches).

## 4. Service connection, Graph consent, and custom roles

**Who:** ADO engineer (connection details), Entra team (consent), elevated
administrator (roles).

### 4.1 Identify the identity behind the shared connection

1. **Project settings > Service connections**, open the shared AVD
   connection.
2. Find the backing app registration or managed identity, using the
   connection's link to manage the app registration or service principal.
   Record its **application (client) ID**.
3. Resolve its **service-principal object ID**, which is what Azure RBAC and
   `access.bicep` use:

   ```bash
   az ad sp show --id <application-client-id> --query '{appId:appId, objectId:id, displayName:displayName}'
   ```

   The Azure portal's role-assignment picker shows object IDs, not app IDs,
   and GUID search in it can return nothing. Search by display name and match
   the object ID.

### 4.2 Graph application permissions

Send the Entra team the template in section 9 of the access doc. They add
these **Application** permissions to the app and grant admin consent:
`User.Read.All`, `Device.Read.All`, `DeviceManagementManagedDevices.Read.All`,
and `Machine.Read.All` on WindowsDefenderATP only if the MDE gate will be
enabled.

### 4.3 Deploy the custom roles (once per workload, only when needed)

The build writes role assignments only in two cases, and Contributor cannot
write role assignments. Decide first whether this step applies:

| `AVD_USER_ACCESS_MODE` | `AVD_SELF_DEALLOCATE_ROLE_ID` | Step 4.3 |
|---|---|---|
| `Group` | `''` (idle self-deallocate off) | **Skip it.** The build makes no role grants. |
| `Group` | set | Required, for the per-VM self-deallocate grant. |
| `Direct` | either | Required, for the end-user grants. |

**Group mode prerequisites.** Before skipping this step, confirm that the
Entra group the request workflow adds users to holds:

- **Virtual Machine User Login** at the session-host resource group or a
  wider scope. A grant on the application group does not cover VM sign-in;
  Entra-joined hosts check this role against the VM.
- **Desktop Virtualization User** on the desktop application group.

The build does not check group membership. The user must be in the group
before they sign in, or the desktop is ready but the sign-in is refused.

Otherwise, the administrator activates the JIT elevation from the access doc, then runs
the following from the repository root. Under the shared-connection model,
pass the same object ID three times:

```powershell
$parameters = @(
    'workload=<workload>'
    'sessionHostResourceGroupName=<vm-rg>'
    'hostPoolResourceGroupName=<host-pool-rg>'
    'networkResourceGroupName=<network-rg>'
    'deploymentPrincipalId=<object-id>'
    'readinessPrincipalId=<object-id>'
    'assignmentPrincipalId=<object-id>'
)
az deployment sub what-if --location <region> --template-file infra/access.bicep --parameters @parameters
az deployment sub create --location <region> --template-file infra/access.bicep --parameters @parameters `
    --query properties.outputs.selfDeallocateRoleDefinitionId.value -o tsv
```

Review the what-if before creating: it should show only role definitions and
role assignments. Record the GUID printed by the create command; it becomes
`AVD_SELF_DEALLOCATE_ROLE_ID` in step 5. Then end the elevation.

When this step applies, it is required even under Contributor: Contributor
cannot write role assignments, and the build grants the end user's sign-in
and desktop roles (Direct mode) or the VM's self-deallocate role.

## 5. Variable groups

**Who:** ADO engineer.

### 5.1 Workload group (required)

1. **Pipelines > Library > + Variable group**. Name it exactly
   `avd-prod-<workload>`, matching the entry you add to the pipeline YAML in
   step 7.
2. Add every variable from
   [../config/avd-prod-workload.variables.example.yml](../config/avd-prod-workload.variables.example.yml)
   with real values:
   - set all three `AVD_*_SERVICE_CONNECTION` variables to the shared
     connection's **name**, exactly as shown in Service connections;
   - set `AVD_USER_ACCESS_MODE` to `Group` when an Entra group already grants
     desktop access (the step 4.3 prerequisites), or `Direct` to have the
     build grant the roles per user;
   - set `AVD_SELF_DEALLOCATE_ROLE_ID` to the GUID from step 4.3, or `''`
     when step 4.3 was skipped;
   - set `AVD_REQUIRED_APP_NAMES_JSON` to the exact installed DisplayNames of
     the base applications, for example `["App One","App Two"]`. Use the full
     names, not substrings. `[]` disables the app gate.
3. Under **Pipeline permissions** for the group, leave open access off. You
   authorize the provision pipeline in step 8.
4. For each additional workload, repeat with its own group.

### 5.2 ServiceNow group (only when ServiceNow goes live)

Create `avd-prod-servicenow` from
[../config/avd-prod-servicenow.variables.example.yml](../config/avd-prod-servicenow.variables.example.yml).
Click the lock icon on `SN_CLIENT_SECRET` (and `SN_PASSWORD` if Basic auth is
used) to make them secret. Technician-only builds never load this group, so it
can wait.

## 6. Power management

**Who:** host-pool owner, subscription team, and Intune team.

1. **Start VM on Connect:** in the host pool's **Properties**, set
   *Start VM on Connect* to **Yes**. Then grant *Desktop Virtualization Power
   On Contributor* to the Azure Virtual Desktop service principal (app ID
   `9cdead84-a844-4324-93f2-b2e6bb768d07`) at **subscription** scope. The
   commands are in section 8.1 of the access doc; Microsoft documents that a
   lower scope breaks the feature.
2. **Idle self-deallocate:** nothing to do in Azure. The provision pipeline
   grants each VM's identity the role at build time when
   `AVD_SELF_DEALLOCATE_ROLE_ID` is set. If step 4.3 was skipped, the
   variable is `''`, no VM gets the role, and idle power-off is off: the
   guest task below would find no permission to deallocate. Hosts then stay
   running until stopped some other way.
3. **Guest task (Intune):** the Intune team deploys
   [../endpoint/Invoke-AvdSelfDeallocate.ps1](../endpoint/Invoke-AvdSelfDeallocate.ps1)
   to the AVD device group as a scheduled task running as SYSTEM, for example
   every 15 minutes.

   **Gap: the installer is not in this repository yet.** Intune has no
   native scheduled-task payload, so the task needs a wrapper: a Win32 app or
   platform script that copies the script to a protected local path,
   registers the task, and has a detection rule. Build and pilot that wrapper
   before relying on idle power-off.

## 7. Set the workload list in the pipeline YAML

**Who:** ADO engineer, through a pull request once branch policies exist (or
directly on the first commit).

In `pipelines/azure-pipelines-avd-provision.yml`, replace `example-workload`
in both `default:` and `values:` with your real workload names:

```yaml
  - name: workload
    displayName: Workload
    type: string
    default: finance
    values:
      - finance
      - engineering
```

ServiceNow does not send `workload`, so the `default` is the workload every
ServiceNow-queued build uses. Each listed name needs its variable group from
step 5.

## 8. Create the two pipeline definitions

**Who:** ADO engineer.

### 8.1 Provision pipeline

1. **Pipelines > New pipeline > Azure Repos Git**, select the repository.
2. **Existing Azure Pipelines YAML file**, branch `main`, path
   `/pipelines/azure-pipelines-avd-provision.yml`.
3. Use the Run dropdown and choose **Save**, not Run.
4. Rename it (**...** menu > **Rename/move**) to
   `AVD - Provision Session Host`.
5. Record the **pipeline ID**, the `definitionId=` number in the pipeline's
   URL. The technician launcher and the ServiceNow REST Message both need it.
6. Authorize resources for this pipeline only:
   - **Project settings > Service connections >** shared connection
     **> ... > Security > Pipeline permissions**: add this pipeline.
   - **Pipelines > Library >** each `avd-prod-*` group **> Pipeline
     permissions**: add this pipeline.

   If you skip this, the first run pauses with *"This pipeline needs
   permission to access a resource"*; a resource administrator can click
   **Permit** then. Pre-authorizing avoids the pause.

### 8.2 CI validation pipeline

1. **Pipelines > New pipeline > Azure Repos Git**, same repository,
   **Existing Azure Pipelines YAML file**, path `/pipelines/ci-validate.yml`.
2. **Save**, then rename to `AVD - CI Validate`.
3. It needs no service connection or variable group. Attach it to `main` in
   step 9.

## 9. Protect `main`

**Who:** ADO engineer.

Anyone who can change the YAML on a branch the service connection trusts can
act with that connection's rights, which under the shared model is
Contributor on the whole subscription. These controls make the reviewed code
on `main` the only code that can use it.

1. **Repos > Branches >** `main` **> ... > Branch policies**:
   - **Require a minimum number of reviewers**: at least 1, and do not allow
     requestors to approve their own changes.
   - **Build validation > +**: pipeline `AVD - CI Validate`, trigger
     *Automatic*, policy *Required*, build expiration *Immediately when main
     is updated*.
   - **Automatically included reviewers**: a reviewer group, required, for
     paths `/infra/*;/pipelines/*;/scripts/*;/endpoint/*`.
2. **Repository security**: limit **Bypass policies when pushing** and
   **Bypass policies when completing pull requests** to administrators.
3. **Service connection > Approvals and checks > + > Branch control**: allow
   only `refs/heads/main` and tick *Verify branch protection*. Queued runs
   from any other branch can then never use the connection.

   **Coordinate this check first.** Checks apply to every pipeline that uses
   the connection. If the shared connection serves other pipelines that run
   from other branches, this check blocks them. In that case, ask for a
   dedicated AVD connection, or have the connection owner decide.

## 10. Queue permissions for people and ServiceNow

**Who:** ADO engineer.

On **AVD - Provision Session Host > ... > Manage security**:

- **Technicians group**: *Queue builds* **Allow**; leave *Edit build
  pipeline* and *Administer build permissions* not set or **Deny**.
- **ServiceNow queue identity** (when live): *Queue builds* **Allow** on this
  pipeline only.

Project **Contributors** inherit *Queue builds* on all pipelines by default.
If technicians or the ServiceNow identity are Contributors, a PAT's scope does
not restrict which pipelines they can queue. Restricting to this one pipeline
requires them to be outside Contributors, or denied elsewhere.

## 11. Technician tooling

**Who:** ADO engineer, then technicians.

1. Copy `technician/Start-AvdBuild.settings.example.json` to
   `technician/Start-AvdBuild.settings.json` and fill in `organization`,
   `project`, `pipelineId` (from step 8.1), and `branch` (`main`). The real
   file is git-ignored; distribute it with the script, not through the repo.
2. Technicians run it from Windows PowerShell 5.1 after `az login`; see the
   main README. The Run pipeline panel works too, but it has no
   duplicate-RITM check.

## 12. First-build acceptance

Run in this order, using a test RITM number and a licensed test user:

1. **Pull request check**: open a trivial pull request; confirm
   `AVD - CI Validate` runs and must pass before completion.
2. **What-if from the launcher**: `Start-AvdBuild.ps1 ... -WhatIf`. It
   compiles the run with your values (a preview) and starts nothing. This
   catches YAML errors and an unknown workload name early.
3. **Azure what-if from your own session**: copy
   [../examples/Invoke-AvdDryRun.example.ps1](../examples/Invoke-AvdDryRun.example.ps1)
   to `examples/Invoke-AvdDryRun.ps1` (git-ignored), replace every
   `<PLACEHOLDER>` with the value from the workload variable group, then, in
   PowerShell 7.2 or later after `az login --tenant <tenant-id>`:

   ```powershell
   ./examples/Invoke-AvdDryRun.ps1 -RitmNumber RITM0012345 -RequestedForUpn testuser@contoso.com
   ```

   It runs the Provision stage's checks and the real ARM what-if, always with
   `-WhatIf`, so it never renews the token or deploys. It passes only when the
   VM, NIC, and two extensions are creates, nothing else changes, and the NIC
   has no public IP. It runs as you, not the service connection: ARM what-if
   needs the same rights as the deployment (Contributor on the session-host
   resource group is enough) plus Graph read on the user. The report holds
   tenant resource IDs and is written to your temp folder; delete it after.
4. **Technician-mode build**: queue for real. Confirm:
   - the Provision stage's `session-host-what-if.json` artifact shows only
     creates for the VM, NIC, disk, and extensions, with nothing touching the
     network or host pool;
   - the Readiness stage's run summary shows every gate passed;
   - the user can sign in to the desktop;
   - when self-deallocate is configured, the VM identity holds
     `AVD Prod Self Deallocate` on its own VM;
   - in Group mode, the build created no role assignment for the user.
5. **Power cycle** (after the Intune wrapper exists): leave the desktop idle
   with the user signed out; confirm it deallocates after the threshold and
   starts again when the user connects.
6. **Failure path**: queue with a disabled or nonexistent test UPN. The build
   should fail in Provision before any VM is created.
7. **ServiceNow mode** (when live): queue from a test RITM; confirm the RITM
   moves through In Progress to Ready with the hostname written back.

## 13. Adding a workload later

1. If step 4.3 applies to the new workload, the elevated administrator
   deploys `access.bicep` for it and records its self-deallocate role GUID.
   In Group mode, confirm the workload's Entra group holds the two roles
   over its session-host resource group and application group instead.
2. Create `avd-prod-<workload>` (step 5.1) and authorize the provision
   pipeline for it (step 8.1).
3. Pull request: add the name to the YAML `values` list (step 7).
4. If its session hosts live in a new resource group, the Start VM on Connect
   role already covers it (subscription scope); confirm the Intune task
   targets its devices.
