# AVD Phase 00: interactive VM deployment

`Deploy-AvdVm.ps1` deploys one session host from your own Azure sign-in, with no Azure DevOps pipeline. It uses the same `infra/session-host.bicep` template as the pipelines.

It creates a VM, NIC, and OS disk, joins the VM to Entra with automatic Intune enrollment, and registers it in the host pool you name. The VM gets no public IP address.

It does not create networking or host pools, assign the VM to a user, or confirm Intune enrollment.

## Before you start

- Azure CLI installed, with Bicep available to it. Windows PowerShell 5.1 or PowerShell 7 both work.
- Rights to create the VM, NIC, and disk in the VM resource group, join the subnet, and read and retrieve a registration token from the host pool. Renewing an expired token also needs write access on the host pool.
- The VM region matches the VNet region. The script uses the VM resource group's region unless you pass `-Location`.
- The host pool's RDP properties include `targetisaadjoined:i:1`. The script warns if they do not.
- Windows automatic MDM enrollment is configured for the tenant.

## Deploy

```powershell
az login
az account set --subscription <subscription-id>

$deployment = @{
    VmName = 'AVD-TEST-01'
    ResourceGroupName = '<vm-rg>'
    HostPoolName = '<host-pool>'
    HostPoolResourceGroupName = '<host-pool-rg>'
    SubnetId = '/subscriptions/<id>/resourceGroups/<network-rg>/providers/Microsoft.Network/virtualNetworks/<vnet>/subnets/<subnet>'
}

# Runs every check and the Azure what-if. Changes nothing.
.\Deploy-AvdVm.ps1 @deployment -WhatIf

# Deploys the VM. This can take 20 minutes.
.\Deploy-AvdVm.ps1 @deployment
```

The default image is the template's Windows 11 Enterprise Marketplace image. To use a corporate image, add `-GalleryImageVersionId <version-id>`.

The script refuses a VM name that already exists in the resource group. If a deployment fails, delete the partial VM and resources, or use a new name.

## After the deployment

1. Check that the session host shows **Available** in the host pool.
2. Check that the device appears in Entra and Intune. Enrollment can finish some time after the script ends.
3. Assign the user to the session host.
4. Give the user **Desktop Virtualization User** on the application group and **Virtual Machine User Login** on the VM.

The local administrator password is random and is not shown or stored. To sign in as local administrator, reset it with `az vm user update`.

The temporary parameter file holds that password and the registration token during the run, and the script always removes it.

## Validate

Run from this folder:

```powershell
Invoke-ScriptAnalyzer -Path . -Recurse -Settings ./PSScriptAnalyzerSettings.psd1
Invoke-Pester -Path ./tests -Output Detailed
```

Tests run offline. They do not prove a real deployment.
