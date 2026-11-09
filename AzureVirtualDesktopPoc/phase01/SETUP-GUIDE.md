# AVD Phase 01 setup and prerequisites

## Purpose

Phase 01 needs tasks from five teams before a technician can build the first desktop. A technician receives a ServiceNow RITM and starts one Azure DevOps pipeline, which builds one Azure Virtual Desktop VM.

Each build creates one VM, NIC, and OS disk. It joins the VM to Entra and Intune, registers it in an existing host pool, and assigns it to the requested user.

The build creates no networking, host pools, or application groups. ServiceNow integration and the hybrid path are out of scope.

The resource layout is one resource group per workload for VMs, one per host pool for AVD resources, and a shared networking resource group. This guide assumes all three are in one subscription.

## Responsibilities

The Azure DevOps project owner coordinates the work, and each other team completes its section. Tasks run in this order, and each row needs the one above it unless the table says otherwise.

| Order | Team | Task | Access needed | Hand back |
| --- | --- | --- | --- | --- |
| 1 | Azure DevOps owner | Import the code and create the pipeline | Project Administrator | Pipeline ID |
| 2 | Identity | Create three app registrations | Can create app registrations, or Application Developer if creation is disabled | Client ID, tenant ID, and service principal object ID for each |
| 3 | Azure DevOps owner | Draft three service connections | Project Administrator or service connection administrator | Issuer and subject identifier for each |
| 4 | Identity | Add federated credentials | Owner of each app registration, or an equivalent Entra role | Confirmation |
| 5 | Identity | Consent to Graph permissions | Privileged Role Administrator | Confirmation |
| 6 | Azure platform | Check resource groups and run the access deployment | Can create custom roles and role assignments in all three resource groups | Deployment output |
| 7 | Azure DevOps owner | Finish the service connections | Project Administrator or service connection administrator | Connection names |
| 8 | Network | Confirm subnet capacity and outbound access | Network owner | Subnet resource ID |
| 9 | AVD or Azure platform | Confirm host pool settings | Host pool owner | Host pool and application group names |
| 10 | Identity | Enable Entra sign-in for Windows Cloud Login | Application Administrator or Cloud Application Administrator | Confirmation |
| 11 | Intune | Confirm automatic enrollment and device policy | Tenant Intune role | Confirmation |
| 12 | Azure DevOps owner | Create variable groups, authorize resources, and grant technician access | Project Administrator | First build date |

The security team should approve the permissions in the Identity and Azure sections before they are granted.

## Service connections

The Azure DevOps owner can start these, but the Identity and Azure teams must complete their parts. Azure DevOps permissions and Azure or Entra permissions are separate, and owning the project grants no Azure or Entra rights.

Use the **App registration or Managed identity (manual)** type with **Workload identity federation**. The automatic type requires the Owner role on the subscription. Federation also means no client secret is created or stored.

Create three connections that all workloads share:

| Connection | Used for | App registration |
| --- | --- | --- |
| Deploy | Creates the VM and gets the registration token | One per connection |
| Readiness | Reads VM, host pool, Entra, and Intune state | One per connection |
| Assignment | Grants user access, assigns the host, and drains on failure | One per connection |

The steps change hands in this order:

1. **Identity:** Create the app registration and send the client ID and tenant ID.
2. **Azure DevOps owner:** In **Project settings > Service connections**, create the connection at subscription scope. Enter the client ID, copy the **Issuer** and **Subject identifier**, and select **Keep as draft**.
3. **Identity:** Add a federated credential using the **Other issuer** scenario with those two values and **Explicit subject identifier**.
4. **Azure platform:** Run the access deployment.
5. **Azure DevOps owner:** Open the draft, select **Finish setup**, then **Verify and save**.

Do not select **Grant access permission to all pipelines**. Authorize this pipeline only.

Pipelines can auto-disable a connection after 100 days of inactivity. If builds stop after a quiet period, check for this under **Service connections** and select **Enable**.

**Open question:** The identities hold roles on resource groups only. If **Verify and save** fails for lack of subscription access, Azure platform and security need to decide how to proceed. This has not yet been tested in the client tenant.

## Identity tasks

Identity creates three app registrations and grants them read-only Graph application permissions. None of them can change users, devices, or policy in Entra or Intune.

| App registration | Graph application permissions | Reason |
| --- | --- | --- |
| Deploy | `User.Read.All` | Confirm the requested user exists and is enabled |
| Readiness | `Device.Read.All`, `DeviceManagementManagedDevices.Read.All` | Confirm Entra join and Intune enrollment |
| Assignment | `User.Read.All` | Resolve the requested user |

WindowsDefenderATP permissions are not needed, because Phase 01 does not check Defender.

Consent to Graph application permissions requires **Privileged Role Administrator**. Cloud Application Administrator and Application Administrator cannot grant them.

Send the Azure team each identity's **service principal object ID**, shown under **Enterprise applications**. The access deployment needs that value, not the app registration's object ID or the client ID.

- [ ] Three app registrations created
- [ ] Federated credential added to each
- [ ] Graph permissions consented
- [ ] Client IDs and tenant ID sent to the Azure DevOps owner
- [ ] Service principal object IDs sent to Azure platform

## Azure tasks

Azure platform runs `AzureVirtualDesktopPoc/phase01/infra/access.bicep` once per workload, with the same three identities each time. It creates seven no-delete custom roles and scopes each to one resource group.

| Identity | VM resource group | Host pool resource group | Network resource group |
| --- | --- | --- | --- |
| Deploy | Deploy and update VMs, NICs, disks, and extensions | Read the pool and renew its registration token | Read the VNet and join subnets |
| Readiness | Read VM state | Read host pool and session hosts | None |
| Assignment | Grant Virtual Machine User Login | Grant Desktop Virtualization User, assign, and drain | None |

An Azure ABAC condition limits the assignment identity. It can grant only Virtual Machine User Login and Desktop Virtualization User, and only to users, so it cannot grant Owner. This has not been tested against a live role assignment, so confirm it during the first build.

First confirm:

- [ ] The VM, host pool, and network resource groups exist in the same subscription
- [ ] The VM resource group exists for each workload
- [ ] The `Microsoft.Compute`, `Microsoft.Network`, and `Microsoft.DesktopVirtualization` resource providers are registered
- [ ] VM quota is available in the region for the chosen size
- [ ] Azure Policy permits the VM size, NIC, and required tags

Then review and deploy from the `phase01` folder:

```powershell
$parameters = @(
    'workload=<workload>'
    'sessionHostResourceGroupName=<vm-rg>'
    'hostPoolResourceGroupName=<host-pool-rg>'
    'networkResourceGroupName=<network-rg>'
    'deploymentPrincipalId=<service-principal-object-id>'
    'readinessPrincipalId=<service-principal-object-id>'
    'assignmentPrincipalId=<service-principal-object-id>'
)
az deployment sub what-if --location <region> --template-file infra/access.bicep --parameters @parameters
az deployment sub create --location <region> --template-file infra/access.bicep --parameters @parameters
```

These assignments must be direct. Privileged Identity Management cannot delegate conditional role assignment for custom roles.

The template does not cover two cases:

- **Image gallery in another resource group:** grant the deploy identity read access to the gallery.
- **VNet in another subscription:** grant the deploy identity subnet join rights there by hand.

## Network, AVD, and Intune prerequisites

These teams confirm existing configuration, because the build changes nothing here except the registration token. A gap in this section usually appears as a build that times out, not as a clear error.

### Network

- [ ] The subnet has free addresses for the expected number of desktops
- [ ] The subnet is in the same region as the VMs
- [ ] Session hosts can reach the [required AVD endpoints](https://learn.microsoft.com/azure/virtual-desktop/required-fqdn-endpoint) outbound
- [ ] Session hosts can also reach Entra and Intune endpoints, which that list does not cover
- [ ] DNS resolves those endpoints from the subnet

No inbound ports are needed. VMs have no public IP address.

### AVD host pool

Check each host pool:

- [ ] Host pool type is Personal with Direct assignment
- [ ] RDP properties include `targetisaadjoined:i:1` and `enablerdsaadauth:i:1`
- [ ] The desktop application group is in the host pool's resource group
- [ ] The application group is published to a workspace, so users can see it
- [ ] The owner accepts that a build renews the registration token when it is missing or within 30 minutes of expiry

### Entra sign-in

The `enablerdsaadauth` setting needs [Microsoft Entra authentication for RDP](https://learn.microsoft.com/azure/virtual-desktop/configure-single-sign-on) enabled once per tenant.

- [ ] Enabled on the Windows Cloud Login service principal, under **Devices > Remote connection configuration**
- [ ] Conditional Access reviewed for the Windows Cloud Login app
- [ ] Kerberos server object created if Active Directory is in the environment and users need on-premises resources

### Intune

- [ ] Windows automatic MDM enrollment is configured for the tenant
- [ ] Device-targeted configuration, update, and compliance policies include these VMs

The Intune team chooses how to target these devices. A build passes on enrollment, and compliance is not checked.

## Azure DevOps tasks

The Azure DevOps owner completes all of this without Azure or Entra rights once the other teams hand back their values.

1. Import the repository so that `AzureVirtualDesktopPoc/` sits at the root, because the pipeline uses that path.
2. Create a pipeline from `AzureVirtualDesktopPoc/phase01/pipelines/azure-pipelines-session-host-manual.yml`.
3. Replace `example-workload` in the pipeline's `values` list with real workload names. Use lowercase letters, digits, and hyphens.
4. For each workload, create variable group `avd-phase01-<workload>` from `config/avd-phase01-workload.variables.example.yml`.
5. During the first test build, select **Permit** to authorize each variable group and service connection. Authorization is per pipeline, and each new variable group needs it too.
6. Grant technicians **Queue builds** on this pipeline only.
7. Restrict who can edit the pipeline and its branch, because editing the YAML gives access to all three connections.
8. Copy `Start-AvdBuild.settings.example.json` to `Start-AvdBuild.settings.json` and set the organization, project, numeric pipeline ID, and branch.
9. Give technicians `Start-AvdBuild.ps1` and that settings file.

The variable group needs these values from the other teams:

| Variable | From |
| --- | --- |
| `AVD_SUBSCRIPTION_ID`, `AVD_TENANT_ID`, `AVD_LOCATION` | Azure platform |
| `AVD_SESSION_HOST_RESOURCE_GROUP`, `AVD_PLATFORM_RESOURCE_GROUP` | Azure platform |
| `AVD_HOST_POOL_NAME`, `AVD_DESKTOP_APP_GROUP_NAME` | Host pool owner |
| `AVD_SESSION_HOST_SUBNET_ID` | Network |
| `AVD_VM_SIZE`, `AVD_OS_DISK_SKU` | Azure platform |
| `AVD_IMAGE_SOURCE_TYPE`, gallery image values | Image owner |
| Three `AVD_*_SERVICE_CONNECTION` names | Azure DevOps owner |

Keep the example values that turn off the app and Defender checks. Do not store secrets in these groups, because the pipeline needs none.

Do not run the original platform pipeline. It builds networking and a host pool.

Technicians need Windows PowerShell 5.1, the Azure CLI, and a signed-in account with **Queue builds**. Without the Azure CLI, they can use a PAT limited to **Build (Read & execute)**, or start the pipeline in the portal.

## Validation and sign-off

Setup is complete when one test build succeeds and the test user can sign in. The code has passed offline tests only, so this first build is its first real run.

Use a test RITM and a licensed test user:

1. Run `Start-AvdBuild.ps1` with `-WhatIf`. This compiles the pipeline with the workload and starts nothing.
2. Run the build with `-Wait`, on Windows PowerShell 5.1.
3. Confirm the checks below.

- [ ] `-WhatIf` passes, confirming the pipeline compiles with that workload
- [ ] The VM, NIC, and OS disk appear only in the VM resource group
- [ ] The VM shows as Entra-joined and appears in Intune
- [ ] The session host is Available in the host pool
- [ ] The Assign stage succeeds, proving the role condition allows the two AVD roles
- [ ] The assignment identity cannot grant another role, such as Reader
- [ ] The test user signs in to the desktop through Windows App

If a build fails, the pipeline keeps the VM and drains it. Do not delete the VM. Send the run link to the Azure DevOps owner.

Repeat the host pool checks and a test build for each new workload.

## Sources

- [Azure Resource Manager service connections](https://learn.microsoft.com/azure/devops/pipelines/library/connect-to-azure)
- [Manual workload identity service connections](https://learn.microsoft.com/azure/devops/pipelines/release/configure-workload-identity)
- [Service connections and pipeline authorization](https://learn.microsoft.com/azure/devops/pipelines/library/service-endpoints)
- [Grant tenant-wide admin consent](https://learn.microsoft.com/entra/identity/enterprise-apps/grant-admin-consent)
- [Delegate role assignment with conditions](https://learn.microsoft.com/azure/role-based-access-control/delegate-role-assignments-overview)
- [Single sign-on for Azure Virtual Desktop](https://learn.microsoft.com/azure/virtual-desktop/configure-single-sign-on)
- [Required endpoints for Azure Virtual Desktop](https://learn.microsoft.com/azure/virtual-desktop/required-fqdn-endpoint)
