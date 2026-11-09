# AVD Phase 01: technician-started builds

ServiceNow does not start this pipeline yet. A technician receives a RITM and starts the build by hand. Only the Azure-hosted desktop path is in scope.

Each build creates one VM, NIC, and OS disk, joins the VM to Entra and Intune, registers it in an existing host pool, and assigns it to the requested user. Networking, host pools, and application groups are never created.

The original `pipelines/` and `scripts/` are unchanged. This folder adds a new pipeline, which calls the existing provisioning, readiness, assignment, and drain scripts, plus an enrollment check of its own.

A build succeeds only when the VM is Entra-joined, has an Intune record for that same device, is Available in the host pool, and is assigned. Intune compliance, required apps, and Defender onboarding are not checked.

| ServiceNow flow | Phase 01 |
|---|---|
| ServiceNow queues the pipeline | Technician uses the script or the portal |
| Sends four fields | Technician selects the workload and enters RITM number and UPN |
| Hostname supplied and cross-checked | Pipeline derives `AVD<digits>` from the RITM |
| `requested_for` picks a real user | Technician types the UPN; it must be correct |
| Pipeline updates the RITM | Technician updates the RITM by hand |

Entra confirms that the UPN exists and is enabled, but not that it is the right person. Check the UPN against the RITM before you confirm.

## Technician: start a build

You need **Queue builds** permission on the pipeline. Choose either option.

### Option 1: PowerShell script

Works in Windows PowerShell 5.1. Keep `Start-AvdBuild.settings.json` beside the script.

```powershell
az login

# Optional: run every check, start nothing
.\Start-AvdBuild.ps1 -Workload finance -RitmNumber RITM0012345 -RequestedForUpn user@contoso.com -WhatIf

# Queue, then wait for the result and the work-note text
.\Start-AvdBuild.ps1 -Workload finance -RitmNumber RITM0012345 -RequestedForUpn user@contoso.com -Wait
```

Without the Azure CLI, add `-AuthMethod Pat`. The script reads `AZURE_DEVOPS_EXT_PAT` or prompts for a hidden entry. The PAT needs only **Build (Read & execute)**.

The script stops if the RITM has a run in progress or has already succeeded. `-Force` overrides only the second case, and only for an approved rebuild.

Builds can take up to about three and a half hours. Without `-Wait`, use the returned `RunUrl` to follow the build.

### Option 2: Azure DevOps portal

1. Open the pipeline and select **Run pipeline**.
2. Select the **Workload**, then enter the **RITM number** and **Requested-for UPN**.
3. Select **Run**.

The run is named `<RITM>-<date>.<n>`. The portal has no duplicate check, so search for the RITM number first.

### After the build

- **Succeeded:** the desktop is ready and assigned. Update the RITM work notes and close it.
- **Failed:** the VM is kept and drained. Do not delete it. Add the run link to the RITM and escalate.

## Administrator: one-time setup

[SETUP-GUIDE.md](SETUP-GUIDE.md) gives each team its tasks, in order. This section is the short version.

The host pool, desktop application group, and VNet already exist, and this pipeline creates none of them. Do not run the platform pipeline: it builds networking and a host pool.

1. Create a pipeline from `AzureVirtualDesktopPoc/phase01/pipelines/azure-pipelines-session-host-manual.yml`.
2. Create the deploy, readiness, and assignment service connections with workload identity federation, so no secret is stored. All workloads share these three. Grant the Graph and consent items in `docs/PRODUCTION-ACCESS-REQUEST-GUIDE.md`, leaving out `WindowsDefenderATP Machine.Read.All`.
3. Grant technicians **Queue builds** on this pipeline only.
4. Copy `Start-AvdBuild.settings.example.json` to `Start-AvdBuild.settings.json` and set the organization, project, numeric pipeline ID, and branch. Give technicians the script and this file. The real file is git-ignored.
5. Add each workload as below.

### Add a workload

Each workload has its own VM resource group, its own host pool resource group, and a shared networking resource group, all in one subscription. Check the existing resources first:

- The host pool is Personal with Direct assignment.
- Its custom RDP properties include `targetisaadjoined:i:1` and `enablerdsaadauth:i:1`.
- Its desktop application group is in the same resource group.
- The owners accept that the build renews the pool's registration token when it is missing or within 30 minutes of expiry.
- `AVD_LOCATION` matches the VNet region.
- Windows automatic MDM enrollment is configured for the tenant.

Then:

1. Create variable group `avd-phase01-<workload>` from `config/avd-phase01-workload.variables.example.yml`.
2. Add `<workload>` to the `values` list in the pipeline YAML. Use lowercase letters, digits, and hyphens.
3. Authorize the pipeline for that variable group. A new group is not covered by earlier authorization.
4. From this folder, as someone who can create roles and role assignments, review and deploy the permissions. Re-run for each workload.

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

The template creates seven no-delete custom roles and scopes each to one resource group. The assignment identity can grant only Virtual Machine User Login and Desktop Virtualization User, and only to users, through an Azure ABAC condition. That condition cannot be delegated through Privileged Identity Management for a custom role, so these assignments must be direct.

If the image gallery is outside the VM resource group, also grant the deploy identity read access to it. If the VNet is in another subscription, this template does not cover it: grant the subnet join role there by hand.

## Validate

Run from this folder:

```powershell
Invoke-ScriptAnalyzer -Path . -Recurse -Settings ./PSScriptAnalyzerSettings.psd1
Invoke-Pester -Path ./tests -Output Detailed
```

Tests run offline. They do not prove the pipeline in Azure DevOps, so run one real build first.

## Moving to ServiceNow later

Point the REST Message at `pipelines/azure-pipelines-session-host.yml`, which still holds the four-field contract and RITM callbacks.
