# AVD Phase 01: technician-started builds

ServiceNow does not start this pipeline yet. A technician receives a RITM and starts the build by hand. Only the Azure-hosted desktop path is in scope.

The original `pipelines/` and `scripts/` are unchanged. This folder adds a new pipeline, which calls the existing provisioning, readiness, assignment, and drain scripts.

| ServiceNow flow | Phase 01 |
|---|---|
| ServiceNow queues the pipeline | Technician uses the script or the portal |
| Sends four fields | Technician enters RITM number and UPN |
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
.\Start-AvdBuild.ps1 -RitmNumber RITM0012345 -RequestedForUpn user@contoso.com -WhatIf

# Queue, then wait for the result and the work-note text
.\Start-AvdBuild.ps1 -RitmNumber RITM0012345 -RequestedForUpn user@contoso.com -Wait
```

Without the Azure CLI, add `-AuthMethod Pat`. The script reads `AZURE_DEVOPS_EXT_PAT` or prompts for a hidden entry. The PAT needs only **Build (Read & execute)**.

The script stops if the RITM has a run in progress or has already succeeded. `-Force` overrides only the second case, and only for an approved rebuild.

Builds can take up to about three hours. Without `-Wait`, use the returned `RunUrl` to follow the build.

### Option 2: Azure DevOps portal

1. Open the pipeline and select **Run pipeline**.
2. Enter the **RITM number** and **Requested-for UPN**.
3. Select **Run**.

The run is named `<RITM>-<date>.<n>`. The portal has no duplicate check, so search for the RITM number first.

### After the build

- **Succeeded:** the desktop is ready and assigned. Update the RITM work notes and close it.
- **Failed:** the VM is kept and drained. Do not delete it. Add the run link to the RITM and escalate.

## Administrator: one-time setup

The platform, access, and image pipelines need no changes and do not use ServiceNow.

1. Create variable group `avd-poc-platform` from `config/avd-poc-platform.variables.example.yml`. Variable group `avd-poc-servicenow` is not needed.
2. Create a pipeline from `AzureVirtualDesktopPoc/phase01/pipelines/azure-pipelines-session-host-manual.yml`.
3. Authorize that pipeline for the variable group and the deploy, readiness, and assignment service connections. They are authorized per pipeline, so the existing authorization does not carry over.
4. Grant technicians **Queue builds** on this pipeline only.
5. Copy `Start-AvdBuild.settings.example.json` to `Start-AvdBuild.settings.json` and set the organization, project, numeric pipeline ID, and branch. Give technicians the script and this file. The real file is git-ignored.

## Validate

Run from this folder:

```powershell
Invoke-ScriptAnalyzer -Path . -Recurse -Settings ./PSScriptAnalyzerSettings.psd1
Invoke-Pester -Path ./tests -Output Detailed
```

Tests run offline. They do not prove the pipeline in Azure DevOps, so run one real build first.

## Moving to ServiceNow later

Point the REST Message at `pipelines/azure-pipelines-session-host.yml`, which still holds the four-field contract and RITM callbacks.
