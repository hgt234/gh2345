# AVD session-host automation

One Azure DevOps pipeline builds a single
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
| Starts the run | Flow Designer calls the Runs API | Run pipeline panel, or [technician/Start-AvdBuild.ps1](technician/Start-AvdBuild.ps1) |
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
  overwrite earlier POC roles of the same name. With
  `AVD_USER_ACCESS_MODE: Group` and self-deallocate off, the build writes no
  role assignments and `access.bicep` is not deployed at all; an Entra group
  supplies the user's access instead.
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
  (`AVD_SELF_DEALLOCATE_ROLE_ID` in the variable group enables this). It
  needs `access.bicep`, so a workload that skips that deployment has no idle
  power-off.
- [endpoint/Invoke-AvdSelfDeallocate.ps1](endpoint/Invoke-AvdSelfDeallocate.ps1)
  runs on each host as SYSTEM via an Intune scheduled task. If any session
  exists - active or disconnected - it exits; otherwise, once uptime passes
  the threshold, it verifies its own identity through IMDS and deallocates
  itself. Deallocate, not shutdown, is what stops compute billing.
  The Intune installer wrapper (Win32 app or platform script that registers
  the task) is not in this repository yet; see step 6 of the deployment
  guide.

## Folder map

```text
.
├── .gitignore
├── PSScriptAnalyzerSettings.psd1       rules for the pipeline scripts (PowerShell 7)
├── README.md
├── config/
│   ├── avd-prod-servicenow.variables.example.yml
│   └── avd-prod-workload.variables.example.yml
├── docs/
│   ├── DEPLOYMENT-GUIDE.md               Azure DevOps setup, pipelines, acceptance
│   └── SERVICE-ACCOUNTS-AND-PERMISSIONS.md   the full access request
├── examples/
│   └── Invoke-AvdDryRun.example.ps1    ARM what-if dry run from your own session (copy, fill, run)
├── endpoint/                           guest scripts delivered by Intune (PowerShell 5.1)
│   ├── Invoke-AvdSelfDeallocate.ps1
│   └── PSScriptAnalyzerSettings.psd1
├── infra/
│   ├── access.bicep                    custom roles and assignments (admin, once per workload)
│   ├── session-host.bicep              one VM, reference-only
│   └── modules/scoped-role-assignment.bicep
├── pipelines/
│   ├── azure-pipelines-avd-provision.yml   the build
│   └── ci-validate.yml                     PR validation gate
├── scripts/                            pipeline steps (PowerShell 7)
│   ├── New-AvdSessionHost.ps1
│   ├── Set-AvdDrainMode.ps1
│   ├── Set-AvdPersonalDesktopAssignment.ps1
│   ├── Test-AvdProvisionRequest.ps1
│   ├── Update-ServiceNowRitm.ps1
│   └── Wait-AvdReadiness.ps1
├── servicenow/
│   ├── Queue-AvdPipeline.js            Flow Designer Action script
│   └── README.md                       request/callback contract
├── technician/                         manual build launcher (PowerShell 5.1)
│   ├── PSScriptAnalyzerSettings.psd1
│   ├── Start-AvdBuild.ps1
│   └── Start-AvdBuild.settings.example.json
└── tests/
    ├── Invoke-AvdDryRun.Tests.ps1      dry-run template
    ├── Production.Tests.ps1            scripts, pipeline, and Bicep safety
    └── Start-AvdBuild.Tests.ps1        launcher
```

## Setup

Follow [docs/DEPLOYMENT-GUIDE.md](docs/DEPLOYMENT-GUIDE.md). It covers, in
order: importing this folder into a fresh Azure DevOps repository, the
service connection and Graph consent, the one-time custom-role deployment,
variable groups, the two pipeline definitions to create (**Provision** and
**CI Validate**), branch protection, queue permissions, power management, and
first-build acceptance. The permissions it requests from each team, and why,
are in
[docs/SERVICE-ACCOUNTS-AND-PERMISSIONS.md](docs/SERVICE-ACCOUNTS-AND-PERMISSIONS.md).

## Technician: start a build

Needs **Queue builds** on the pipeline. Either use the Run pipeline panel
(select the workload, enter the RITM number and requested-for UPN), or from
`technician/` in Windows PowerShell 5.1:

```powershell
az login
.\Start-AvdBuild.ps1 -Workload <workload> -RitmNumber RITM0012345 -RequestedForUpn user@contoso.com -WhatIf
.\Start-AvdBuild.ps1 -Workload <workload> -RitmNumber RITM0012345 -RequestedForUpn user@contoso.com -Wait
```

The script refuses a RITM that has a run in progress or already succeeded
(`-Force` overrides the second case for an approved rebuild), previews the run
without starting it, and with `-Wait` prints text for the RITM work notes. A
failed build keeps the VM and drains it: do not delete it, add the run link to
the RITM, and escalate.

## Repository protection

Anyone who can change the pipeline YAML acts with the service connection's
rights, which under the shared Contributor model is the whole subscription.
Require pull requests, reviewers, and the CI Validate build on `main`, and
restrict the connection to `main` with a branch-control check. The exact
settings are in step 9 of the deployment guide.

## Validate

```powershell
# From the repository root (pwsh). pipelines/ci-validate.yml runs the same checks.
$findings = @(Invoke-ScriptAnalyzer -Path . -Recurse -Settings ./PSScriptAnalyzerSettings.psd1)
$findings += @(Invoke-ScriptAnalyzer -Path ./endpoint -Settings ./endpoint/PSScriptAnalyzerSettings.psd1)
$findings += @(Invoke-ScriptAnalyzer -Path ./technician -Settings ./technician/PSScriptAnalyzerSettings.psd1)
if ($findings) { $findings | Format-Table -AutoSize; throw "PSScriptAnalyzer: $(@($findings).Count) finding(s)" }
Invoke-Pester -Path ./tests -Output Detailed
az bicep build --file infra/session-host.bicep --stdout | Out-Null
az bicep build --file infra/access.bicep --stdout | Out-Null
```

Tests run offline. They do not prove the pipeline in Azure DevOps, so run one
real technician-mode build first, then one ServiceNow-mode build when the
integration is ready. For power management, verify one host deallocates
after its idle threshold and starts again on user connection.
