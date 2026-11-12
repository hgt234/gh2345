# AVD production build pipeline

Production successor to the POC. One Azure DevOps pipeline builds a single
private, Entra-joined Windows 11 personal desktop per ServiceNow RITM into
infrastructure that **already exists**: the AVD subscription, the peered VNet
and session-host subnet, the personal host pool, the desktop application
group, and the workspace. None of those are ever created, modified, or
deleted here.

Each build: validates the request, deploys the VM (named `AVD<RITM digits>`),
registers it in the existing host pool, runs pre-flight readiness gates
(Entra join, Intune enrollment, required base apps, AVD `Available`), reports
the results back to the build run, assigns the requested user, and - when the
request came from ServiceNow - writes the lifecycle back to the RITM.

After the build, each desktop manages its own power: Start VM on Connect
powers it on when its user connects, and an Intune-deployed guest task
deallocates it when idle (see [Power management](#power-management)).

MDE is delivered by Intune, so there is no Defender extension or agent step;
an optional read-only MDE onboarding gate exists for final acceptance runs.

## Two ways to start a build, one pipeline

[pipelines/azure-pipelines-avd-provision.yml](pipelines/azure-pipelines-avd-provision.yml)

| | ServiceNow (when its automation is live) | Technician (available now) |
|---|---|---|
| Starts the run | Flow Designer calls the Runs API | Run pipeline panel, or `phase01/Start-AvdBuild.ps1` pointed at this pipeline's ID |
| Parameters sent | `ritmNumber`, `ritmSysId`, `requestedHostName`, `requestedForUpn` | `workload`, `ritmNumber`, `requestedForUpn`; sys_id and host name left blank |
| Host name | Supplied and cross-checked against the RITM | Derived from the RITM |
| RITM updates | Automatic (In Progress / Ready / Failed) | Technician updates the RITM by hand |

Supplying `ritmSysId` is the switch: when present, the ServiceNow variable
group is loaded and the callback stages compile into the run; when blank,
the pipeline has no ServiceNow dependency at all, so technician builds work
before any ServiceNow configuration exists. A technician who knows the
sys_id may enter it to get automatic RITM updates.

## Identity model

The pipeline reads its three service-connection names from the workload
variable group, so it runs on either model without code changes:

- **Shared connection (this org's model, the assumed default):** point
  `AVD_DEPLOYMENT_SERVICE_CONNECTION`, `AVD_READINESS_SERVICE_CONNECTION`,
  and `AVD_ASSIGNMENT_SERVICE_CONNECTION` at the existing subscription-wide
  Contributor connection. The identity behind it still needs the Graph
  permissions and the role-assignment grants that Contributor lacks - see
  "Running on one shared service connection" in
  [docs/SERVICE-ACCOUNTS-AND-PERMISSIONS.md](docs/SERVICE-ACCOUNTS-AND-PERMISSIONS.md).
- **Least privilege (optional target state):** three WIF connections, one
  identity per stage, each holding only its stage's custom roles.

## Safety model

- [infra/session-host.bicep](infra/session-host.bicep) references the subnet
  with `existing` and declares no `Microsoft.DesktopVirtualization` resource.
  It can only create the VM, NIC, disk, and the Entra-join and AVD-agent
  extensions.
- [scripts/New-AvdSessionHost.ps1](scripts/New-AvdSessionHost.ps1) runs an
  ARM what-if first and blocks the deployment if it contains any Delete or
  Recreate, deploys in Incremental mode, and refuses a VM name that exists
  under a different RITM or user.
- [infra/access.bicep](infra/access.bicep) defines custom roles with **no
  delete actions**. The assignment identity's ABAC condition permits exactly
  two kinds of grant: the two end-user roles to users, and the
  self-deallocate role to each VM's own identity. It cannot grant Owner or
  anything else. The role GUIDs are namespaced so deploying them cannot
  overwrite the phase01 roles.
- Host-pool write exists only to renew the registration token; the failure
  path drains the host (`allowNewSession=false`) and preserves the VM for
  investigation.
- Under the shared Contributor connection, subscription RBAC no longer
  limits the pipeline's identity, so these code guards plus restricted
  service-connection authorization and protected YAML are the effective
  controls.
- Every mutating script supports `-WhatIf`, and the Pester suite proves
  `-WhatIf` performs zero changes.

## Power management

Details and rationale in section 8 of
[docs/SERVICE-ACCOUNTS-AND-PERMISSIONS.md](docs/SERVICE-ACCOUNTS-AND-PERMISSIONS.md).

- **Start VM on Connect:** enabled on the host pool, with the built-in
  *Desktop Virtualization Power On Contributor* role granted to the AVD
  first-party service principal (app ID `9cdead84-a844-4324-93f2-b2e6bb768d07`)
  at subscription scope - Microsoft documents that any lower scope breaks the
  feature. The AVD control plane powers a deallocated desktop back on when
  its user connects.
- **Idle power-off is usage-aware, not schedule-based.** AVD's personal
  autoscale was evaluated and rejected: these workloads run 24/7 and
  autoscale only reacts to disconnect/log-off events inside time phases, so
  a running host with zero sessions is never deallocated. Instead,
  `access.bicep` defines the `AVD Prod Self Deallocate` role (VM read +
  deallocate only) and the build's Assign stage grants it to each new VM's
  own system-assigned identity, on that VM only
  (`AVD_SELF_DEALLOCATE_ROLE_ID` in the variable group enables this).
- [endpoint/Invoke-AvdSelfDeallocate.ps1](endpoint/Invoke-AvdSelfDeallocate.ps1)
  runs on each host as SYSTEM via an Intune scheduled task. If any session
  exists - active or disconnected - it exits; otherwise, once uptime passes
  the threshold, it verifies its own identity through IMDS and deallocates
  itself. Deallocate, not shutdown, is what stops compute billing.

## Folder map

```text
production/
├── config/     variable-group examples (per-workload and ServiceNow)
├── docs/       SERVICE-ACCOUNTS-AND-PERMISSIONS.md - the full access request
├── endpoint/   PS 5.1 guest scripts delivered by Intune (idle self-deallocate)
├── infra/      session-host.bicep, access.bicep (reference-only, no-delete)
├── pipelines/  azure-pipelines-avd-provision.yml
├── scripts/    validate, deploy, readiness, assign, drain, ServiceNow callback
└── tests/      Pester suite: WhatIf proofs, gate logic, pipeline/Bicep safety
```

## Setup (administrator, once per workload)

Prerequisites: the host pool is Personal with Direct assignment, its custom
RDP properties include `targetisaadjoined:i:1` and `enablerdsaadauth:i:1`,
Windows automatic MDM enrollment is configured, and `AVD_LOCATION` matches
the VNet region.

1. Work through
   [docs/SERVICE-ACCOUNTS-AND-PERMISSIONS.md](docs/SERVICE-ACCOUNTS-AND-PERMISSIONS.md)
   with the owning teams. For the shared-connection model that means: Graph
   application permissions (admin-consented) on the identity behind the
   existing connection, and nothing else new - the role grants arrive in
   step 4.
2. Create the pipeline from
   `AzureVirtualDesktopPoc/production/pipelines/azure-pipelines-avd-provision.yml`
   and authorize the shared service connection for this pipeline only.
3. Create variable group `avd-prod-<workload>` from
   [config/avd-prod-workload.variables.example.yml](config/avd-prod-workload.variables.example.yml),
   add `<workload>` to the `values` list in the pipeline YAML, and authorize
   the pipeline for the group. Set all three `*_SERVICE_CONNECTION` values
   to the shared connection (or to the three per-stage connections under the
   least-privilege model).
4. As the one-time elevated administrator, deploy the access roles. Under
   the shared-connection model, pass the shared identity's service-principal
   object ID for all three principal parameters. Re-run per workload; the
   deployment is additive and idempotent.

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
   az deployment sub create --location <region> --template-file infra/access.bicep --parameters @parameters
   ```

   Record the `selfDeallocateRoleDefinitionId` output and set it as
   `AVD_SELF_DEALLOCATE_ROLE_ID` in the workload variable group.
5. Configure power management: enable Start VM on Connect on the host pool,
   grant *Desktop Virtualization Power On Contributor* to the AVD
   first-party service principal at subscription scope (commands in
   section 8.1 of the access doc), and have the Intune team deploy
   [endpoint/Invoke-AvdSelfDeallocate.ps1](endpoint/Invoke-AvdSelfDeallocate.ps1)
   as a recurring scheduled task on the AVD device group.
6. Grant technicians **Queue builds** on this pipeline only.
7. When ServiceNow goes live: create `avd-prod-servicenow` from
   [config/avd-prod-servicenow.variables.example.yml](config/avd-prod-servicenow.variables.example.yml),
   authorize the pipeline, and point the ServiceNow REST Message at this
   pipeline with the four-field contract (`servicenow/Queue-AvdPipeline.js`
   works unchanged apart from the pipeline ID).

If the image gallery is outside the VM resource group, also grant the deploy
identity read access to it (already covered by Contributor in the shared
model). If the VNet is in another subscription, `access.bicep` does not
cover it: grant the subnet join role there by hand.

Hosts built before `AVD_SELF_DEALLOCATE_ROLE_ID` was set never received the
self-deallocate grant: re-run the pipeline for those RITMs or grant the role
to their VM identities once by hand.

## Validate

```powershell
# From this folder (pwsh)
$findings = @(Invoke-ScriptAnalyzer -Path . -Recurse -Settings ./PSScriptAnalyzerSettings.psd1)
$findings += @(Invoke-ScriptAnalyzer -Path ./endpoint -Settings ./endpoint/PSScriptAnalyzerSettings.psd1)
if ($findings) { $findings | Format-Table -AutoSize; throw "PSScriptAnalyzer: $(@($findings).Count) finding(s)" }
Invoke-Pester -Path ./tests -Output Detailed
az bicep build --file infra/session-host.bicep --stdout | Out-Null
az bicep build --file infra/access.bicep --stdout | Out-Null
```

Tests run offline. They do not prove the pipeline in Azure DevOps, so run one
real technician-mode build first, then one ServiceNow-mode build when the
integration is ready. For power management, verify one host deallocates
after its idle threshold and starts again on user connection.
