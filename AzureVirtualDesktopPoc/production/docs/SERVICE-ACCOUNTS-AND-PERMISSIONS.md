# Production service accounts, app registrations, and permissions

This is the complete access request for the production AVD build pipeline in
[`production/`](../). Each item says what we are asking for and why. The POC's
bootstrap, image-builder, decommission, and hybrid identities are **not**
requested; see [section 7](#7-what-we-are-not-asking-for).

Two deployment models are covered. [Section 2](#2-running-on-one-shared-service-connection)
uses the organization's existing subscription-wide service connection(s) and
is the smallest request. [Section 3](#3-the-three-azure-workload-identities-least-privilege-model)
is the least-privilege target state with one identity per stage. The pipeline
supports both without code changes because the three connection names are
variable-group values.

The pipeline builds one session host per ServiceNow RITM into infrastructure
that already exists (subscription, peered VNet and subnet, host pool, desktop
application group, workspace). Nothing in the runtime path can delete an Azure
resource, change the network, or reconfigure the host pool beyond renewing its
registration token.

> Conditional Access is out of scope. Do not request, inspect, or change
> Conditional Access policies for this solution.

## 1. Quick reference

In the shared-connection model (section 2), the three Azure rows below
collapse onto the single identity behind the existing connection: it needs
the union of their API permissions plus the two ABAC-constrained Assign
roles on top of its Contributor grant.

| Identity | Kind | Azure RBAC (custom, no delete actions) | API permissions (Application, admin consent) | Why it exists |
|---|---|---|---|---|
| `sc-avd-prod-deploy` | Entra app registration + WIF service connection | `AVD Prod Deploy VMs` (VM resource group), `AVD Prod Join Subnet` (network resource group), `AVD Prod Register Hosts` (host pool resource group) | Microsoft Graph `User.Read.All` | Deploys the VM, NIC, disk, and extensions; joins the existing subnet; gets or renews the host pool registration token |
| `sc-avd-prod-readiness` | Entra app registration + WIF service connection | `AVD Prod Check VMs` (VM resource group, includes VM Run Command), `AVD Prod Read Hosts` (host pool resource group) | Microsoft Graph `Device.Read.All`, `DeviceManagementManagedDevices.Read.All`; WindowsDefenderATP `Machine.Read.All` only if the MDE gate is enabled | Verifies the VM is running, Entra-joined, Intune-enrolled, has the base apps installed, and is Available in the pool |
| `sc-avd-prod-assignment` | Entra app registration + WIF service connection | `AVD Prod Assign VM Login` (VM resource group), `AVD Prod Assign Desktop` (host pool resource group); both ABAC-constrained | Microsoft Graph `User.Read.All` | Grants the end user sign-in and desktop access, binds the personal host to them, and drains failed hosts |
| ServiceNow callback OAuth client + `avd.integration` | ServiceNow inbound OAuth client credentials bound to a web-service-only user | None | `PATCH /api/now/table/sc_req_item/{sys_id}` only; write limited to the AVD status/hostname fields and `work_notes` | Lets the pipeline report Queued / In Progress / Ready / Failed back to the RITM |
| ServiceNow-to-ADO queue identity | Azure DevOps PAT (interim) held in a ServiceNow credential | None | PAT scope **Build: Read & execute**; `Queue builds` granted only on this one pipeline | Lets ServiceNow start the build. Not needed until the ServiceNow side goes live; technicians queue builds with their own accounts until then |
| One-time administrator | Human, PIM/JIT | Rights to create role definitions and role assignments at the three resource groups (for example JIT **User Access Administrator** at those scopes) | None | Deploys `production/infra/access.bicep` once per workload, then drops the elevation |
| Technicians | Human Azure DevOps users | None | Azure DevOps `Queue builds` on this pipeline only | Start builds by hand while the ServiceNow automation is behind |
| Azure Virtual Desktop service principal (app ID `9cdead84-a844-4324-93f2-b2e6bb768d07`) | Microsoft first-party service principal, already in the tenant | Built-in **Desktop Virtualization Power On Contributor** at subscription scope (Microsoft documents that any lower scope breaks Start VM on Connect) | None | Lets the AVD control plane start a deallocated personal host when its user connects (section 8.1) |
| Session-host VM identity | System-assigned managed identity, already created per VM by the Bicep; the build's Assign stage grants the role | Custom `AVD Prod Self Deallocate` (VM read + deallocate only) at the VM's own scope | None | The Intune-deployed guest task deallocates its own idle VM through IMDS (section 8.3) |

All Azure identities authenticate with **workload identity federation**
(no client secrets to store or rotate) and each service connection is
authorized only for this pipeline, never for all pipelines.

## 2. Running on one shared service connection

The organization already operates ARM service connections granted
**Contributor on the entire AVD subscription**, and this solution is built to
run on that model. A service connection is only the Azure DevOps wrapper
around an Entra identity (an app registration or managed identity), so "use
the existing connection" means "grant the identity behind it what is listed
below."

**To adopt the shared connection, set `AVD_DEPLOYMENT_SERVICE_CONNECTION`,
`AVD_READINESS_SERVICE_CONNECTION`, and `AVD_ASSIGNMENT_SERVICE_CONNECTION`
in the workload variable group to the same connection name.** No YAML or
script changes are needed.

**What subscription Contributor already covers:** every ARM call in the
pipeline - deployments, VM/NIC/disk/extension writes, subnet join, host-pool
registration-token renewal, VM Run Command, and session-host assign/drain
writes.

**What is still missing and must be requested for the identity behind the
shared connection:**

1. **Role-assignment write.** Contributor's `NotActions` exclude
   `Microsoft.Authorization/*/Write`, so the Assign stage's grants of
   *Virtual Machine User Login* and *Desktop Virtualization User* fail under
   Contributor alone. Fix: deploy [access.bicep](../infra/access.bicep) once,
   passing the shared connection's **service-principal object ID** for all
   three principal parameters. The two ABAC-constrained Assign roles then sit
   alongside Contributor, and the identity still cannot grant anything except
   those two end-user roles, and only to users. (A scoped User Access
   Administrator grant would also work but is far broader; prefer the
   constrained roles.) This one-time deployment still needs the elevated
   administrator from [section 5](#5-one-time-human-setup) because
   Contributor cannot create role definitions either.
2. **Microsoft Graph application permissions.** Azure RBAC grants no Graph
   access at any tier. The app registration behind the shared connection
   needs the union of the permissions in the quick reference: `User.Read.All`,
   `Device.Read.All`, `DeviceManagementManagedDevices.Read.All`, plus
   WindowsDefenderATP `Machine.Read.All` only if the MDE gate is enabled -
   all Application type, with admin consent.
3. **Key Vault, only if adopted later.** If pipeline secrets (for example the
   ServiceNow client secret) move from the protected variable group to a Key
   Vault-linked group, the same identity needs **Key Vault Secrets User** on
   that vault (RBAC vaults) or a get/list access policy. Nothing in the
   current design requires it.

**What this model costs in safety, stated for the approvers:** Contributor
can modify or delete anything in the subscription, including the host pools
and the network stack, so subscription RBAC no longer protects the existing
AVD estate from this pipeline's identity. The effective protections become
the code in this repository - reference-only Bicep, the what-if
Delete/Recreate block, Incremental-mode deployments, ownership-tag checks,
and the absence of any delete call - plus Azure DevOps controls: authorize
the shared connection only for intended pipelines (never "all pipelines"),
and protect the YAML with branch policies/code owners, because anyone who can
edit the pipeline can act with the connection's full Contributor rights. If
the organization later tightens to least privilege, section 3 is the target
state: create the three connections, re-run `access.bicep` with the
per-stage object IDs, and update three variable-group values.

## 3. The three Azure workload identities (least-privilege model)

Three separate app registrations keep each stage of the build on its own
least-privilege credential, so a compromise of any one stage never yields the
combined permission set. Use this model where the organization wants the
pipeline identity unable to delete or reconfigure existing AVD resources at
the RBAC layer rather than only at the code layer.

### 3.1 `sc-avd-prod-deploy`

**What we are asking for:** a single-tenant app registration with a federated
credential for the Azure DevOps service connection; the three deployment
custom roles from `access.bicep`; Graph `User.Read.All` (Application) with
admin consent.

**Why:**

- *Deploy VMs* (VM resource group) holds ARM deployment, VM/NIC/disk/extension
  write, and Compute read. It has no delete action, so a bad run can create or
  converge a VM but never remove one. Extension write is the one privileged
  operation: it installs the Entra join and AVD agent extensions, which run as
  SYSTEM in the guest. That is inherent to building a session host; the
  compensating controls are the pipeline-only service-connection
  authorization and Activity Log monitoring.
- *Join Subnet* (network resource group) is read plus `subnets/join/action`
  only. The identity can attach a NIC to the existing subnet but cannot
  create, change, or delete any network resource, so the peered network stack
  cannot be touched.
- *Register Hosts* (host pool resource group) allows host-pool read, write,
  and `retrieveRegistrationToken/action`. Write exists only because renewing
  an expired registration token is an ARM PATCH of the pool's
  `registrationInfo`; the pipeline sets nothing else and cannot delete the
  pool or its hosts. Pool owners accept that a build renews the token when it
  is missing or within 30 minutes of expiry.
- Graph `User.Read.All` lets the pre-flight resolve the requested UPN and
  refuse a build for a missing or disabled account before any resource is
  created.

### 3.2 `sc-avd-prod-readiness`

**What we are asking for:** a second app registration + WIF connection; the
two readiness custom roles; Graph `Device.Read.All` and
`DeviceManagementManagedDevices.Read.All` (Application) with admin consent.
WindowsDefenderATP `Machine.Read.All` (Application) is only needed if the
optional MDE readiness gate is turned on.

**Why:**

- *Check VMs* (VM resource group) is Compute read plus
  `virtualMachines/runCommand/action`. Run Command executes the checked-in,
  read-only application-inventory script inside the guest so the build can
  prove the base applications actually installed before handing the desktop
  to the user. Be aware that RBAC cannot restrict Run Command to that one
  script: treat this identity as capable of guest SYSTEM execution, keep its
  service connection authorized for this pipeline only, and monitor Run
  Command invocations. If that is unacceptable, the app gate can be disabled
  (`AVD_REQUIRED_APP_NAMES_JSON: '[]'`) and this action removed from the
  role.
- *Read Hosts* (host pool resource group) is read-only and confirms the host
  reaches `Available` in the pool.
- `Device.Read.All` finds the Entra device record and proves a real
  Entra join (trust type `AzureAd`, account enabled).
- `DeviceManagementManagedDevices.Read.All` proves Intune enrolled that same
  device (matched on device ID, so a stale record cannot pass) - Intune is
  what delivers policy, apps, and Defender onboarding, so enrollment is the
  management handoff gate.
- MDE `Machine.Read.All` (optional) reads onboarding and health status only.
  Since Defender onboarding arrives through Intune policy, most builds can
  rely on the enrollment gate and leave this off, which keeps the Defender
  API consent out of the request entirely.

### 3.3 `sc-avd-prod-assignment`

**What we are asking for:** a third app registration + WIF connection; the two
assignment custom roles; Graph `User.Read.All` (Application) with admin
consent.

**Why:**

- The build's last step grants the end user the built-in **Virtual Machine
  User Login** role on their VM and **Desktop Virtualization User** on the
  desktop application group, then sets the personal host's `assignedUser`.
  That requires `Microsoft.Authorization/roleAssignments/write` at the two
  resource groups.
- Unconstrained role-assignment write is an escalation path (it could assign
  Owner). Both roles therefore carry an **Azure ABAC condition** that limits
  this identity to assigning exactly those two role IDs, and only to users.
  The condition is part of the Bicep and deployed with the role; please
  verify it on the assignment rather than waiving it.
- `sessionHosts/write` on the host pool scope is what sets `assignedUser`,
  and is also used to put a failed host into drain mode so nobody signs in
  to a desktop that failed its checks. There is still no delete action.
- Graph `User.Read.All` re-resolves the UPN at assignment time.

## 4. ServiceNow identities

### 4.1 Callback OAuth client and integration user

**What we are asking for (ServiceNow team):** a web-service-only integration
user (for example `avd.integration`) with ACLs limited to the applicable AVD
RITMs; an inbound client-credentials OAuth application bound to that user; an
API auth scope restricted to `PATCH /api/now/table/sc_req_item/{sys_id}`;
write access only to `u_avd_build_status`, `u_avd_hostname`, and
`work_notes`.

**Why:** the pipeline writes the request lifecycle (In Progress, Ready,
Failed) and the hostname back to the RITM so the service desk sees build
state without opening Azure DevOps. Client credentials is the production
method; the Basic-auth fallback in the script exists only for initial
developer-instance testing. The client secret goes directly into the
protected `avd-prod-servicenow` variable group (marked secret) or a vault -
never email or ticket comments.

This is only needed when ServiceNow callbacks go live. Technician-started
builds never load the ServiceNow variable group and need none of this.

### 4.2 ServiceNow-to-Azure DevOps queue identity

**What we are asking for (ADO team, when the ServiceNow flow goes live):** a
dedicated queue identity whose short-lived PAT (scope **Build: Read &
execute** only) is stored as a ServiceNow Basic credential, with `Queue
builds` granted only on this pipeline and project-wide queue rights removed.

**Why:** ServiceNow's Flow Designer calls the Azure DevOps Runs API to queue
the build with the four request fields. PAT scope alone is not a pipeline
boundary, so the pipeline-level `Queue builds` ACL is the real restriction.
Longer term this should be replaced with an Entra-backed service-to-service
identity; that design needs the ADO platform team and is not yet implemented,
so do not describe it as such.

## 5. One-time human setup

**What we are asking for:** a PIM/JIT elevation for one administrator to run
`production/infra/access.bicep` once per workload (what-if first, then
deploy). Creating role definitions and role assignments at the three resource
groups requires `Microsoft.Authorization/roleDefinitions/write` and
`roleAssignments/write` there - JIT **User Access Administrator** at those
scopes, or subscription Owner if policy prefers, dropped immediately after.

**Why:** the pipeline identities deliberately cannot grant themselves
anything, so a human has to lay down the seven custom roles and their
assignments once. The deployment is additive and GUID-namespaced; it cannot
collide with or overwrite the phase01 POC roles. Re-running it is a no-op.

Technicians additionally need Azure DevOps **Queue builds** on this pipeline
only - no Azure RBAC at all, because every Azure action runs under the three
workload identities above.

## 6. Verification checklist

- [ ] (Shared model) the identity behind the existing connection carries the
      union of Graph permissions and both ABAC-constrained Assign roles, and
      the three variable-group connection values point at it.
- [ ] (Least-privilege model) three distinct app registrations exist;
      application (client) IDs and service-principal object IDs are recorded
      separately and not confused.
- [ ] Each service connection uses workload identity federation; no client
      secrets were created.
- [ ] "Grant access permission to all pipelines" is off on all three
      connections; each is authorized only for this pipeline.
- [ ] Graph/MDE permissions show **Application** type with admin consent, and
      match the quick-reference table exactly - nothing extra.
- [ ] The seven custom roles contain no delete action
      (`az role definition list --custom-role-only true` and inspect).
- [ ] The two assignment roles carry the ABAC condition restricting
      assignable role IDs and principal type.
- [ ] Run Command and extension write are acknowledged as guest SYSTEM
      execution and their service connections are pipeline-restricted.
- [ ] The `avd-prod-<workload>` and `avd-prod-servicenow` variable groups are
      authorized only for this pipeline, with secrets marked secret.
- [ ] The administrator elevation used for `access.bicep` has been removed.

## 7. What we are not asking for

Explicitly out of scope for production, in contrast to the POC:

- **No bootstrap/platform identity.** The network, host pool, application
  group, and workspace already exist and are never deployed by this pipeline.
- **No image-builder identity.** Image builds are a separate concern; the
  pipeline only reads the existing Compute Gallery through the deploy
  identity's Compute read. If the gallery lives outside the VM resource
  group, grant the deploy identity **Reader** on the gallery resource group.
- **No decommission identity and no delete permission anywhere.** Teardown of
  a desktop is a separate, human-approved process outside this pipeline.
- **No MDE extension or Defender write access.** MDE onboarding is delivered
  by Intune policy; at most the readiness identity gets read-only
  `Machine.Read.All`, and only if the optional gate is enabled.
- **No Intune or Defender administration roles for service principals.**
  Policy, app, and EDR configuration stay with the Intune and Defender teams
  as human duties.
- **No Automation Account, Function, or runbook identity for power
  management.** Start/stop is handled by the AVD control plane's own
  service principal (autoscale, section 8) or, if the loopback option is
  chosen, by each VM's own identity scoped to itself.
- **No Conditional Access changes.**

## 8. Power management: Start VM on Connect and automatic power-off

Personal desktops should be deallocated when idle and start themselves when
the user connects. Neither function runs under the pipeline identities; the
pipeline needs no new permission for any option below.

### 8.1 Start VM on Connect

**What we are asking for:** enable the host pool's *Start VM on Connect*
setting (host-pool owner, one-time), and assign the built-in **Desktop
Virtualization Power On Contributor** role to the **Azure Virtual Desktop
first-party service principal** at **subscription scope** - Microsoft
documents that assigning it at any lower scope (resource group, host pool,
or VM) prevents Start VM on Connect from working.

Identify the service principal by its application (client) ID,
`9cdead84-a844-4324-93f2-b2e6bb768d07`, never by display name alone: it
shows as "Azure Virtual Desktop" in newer tenants and "Windows Virtual
Desktop" in tenants onboarded before the rename, and a tenant can contain
several similarly named AVD principals (the Client and ARM Provider apps,
and classic-era duplicates with the identical name).

**Portal behavior to expect:** the role-assignment member picker lists
service principals with their **object IDs**, not application IDs, and
searching the picker by GUID may return nothing. So resolve the object ID
first and match on that:

```bash
az ad sp show --id 9cdead84-a844-4324-93f2-b2e6bb768d07 \
  --query '{displayName:displayName, appId:appId, objectId:id}'
```

Record both IDs in the request ticket. In the portal, search the picker by
display name ("Azure Virtual Desktop" or "Windows Virtual Desktop"), then
confirm the selected entry's object ID equals the value resolved above
before saving the assignment.

**Why:** when a user connects to their deallocated desktop, the AVD control
plane itself powers the VM back on. It is Microsoft's own service principal -
no app registration, secret, or script of ours is involved, which is why this
is the only identity in this document we do not create. The role can start
and read VMs; it cannot stop, delete, or change them, and the subscription is
dedicated to AVD, so the subscription-wide scope reaches session hosts only.

```bash
# Resolve the first-party service principal's object ID in this tenant
az ad sp show --id 9cdead84-a844-4324-93f2-b2e6bb768d07 --query id -o tsv

az role assignment create \
  --assignee-object-id <avd-sp-object-id> \
  --assignee-principal-type ServicePrincipal \
  --role "Desktop Virtualization Power On Contributor" \
  --scope /subscriptions/<sub-id>
```

### 8.2 Considered and not adopted: personal autoscale scaling plan

AVD's native personal autoscale (a scaling plan attached to the host pool,
with the Desktop Virtualization Power On Off Contributor role granted to the
AVD service principal at subscription scope) was evaluated and rejected for
this environment. Its schedules are time-phase based and its power-off
actions key on disconnect and log-off events within those phases. These
personal workloads run 24/7, so the time phases add nothing, and the
event-driven trigger has a real gap: a host that is running with no sessions
at all - started but never connected, or up after maintenance - produces no
disconnect or log-off event and is never deallocated. The requirement is
purely usage-aware power-off, which the adopted model below provides.
Revisit only if the loopback model proves unreliable in this tenant.

### 8.3 Adopted: guest loopback self-deallocate

Each session host turns itself off when idle, using the pattern proven in a
prior organization. This is implemented in the repository:

- [access.bicep](../infra/access.bicep) defines the custom role
  **`AVD Prod Self Deallocate <workload>`** containing only
  `Microsoft.Compute/virtualMachines/read` and
  `Microsoft.Compute/virtualMachines/deallocate/action`, assignable only
  within the session-host resource group, and emits its GUID as the
  `selfDeallocateRoleDefinitionId` output.
- The assignment identity's ABAC condition permits exactly two kinds of
  grant: the two end-user roles to users, and this role to service
  principals. It still cannot grant anything else to anyone.
- Set the role GUID as `AVD_SELF_DEALLOCATE_ROLE_ID` in the workload
  variable group. The build's Assign stage then grants each new VM's
  **existing system-assigned managed identity** the role on that VM only.
  Blast radius per identity: one machine can turn itself off.
- [endpoint/Invoke-AvdSelfDeallocate.ps1](../endpoint/Invoke-AvdSelfDeallocate.ps1)
  runs on the host as SYSTEM via an Intune-deployed scheduled task (for
  example every 15 minutes). If any session exists - active or disconnected,
  so nobody's running applications are lost - it exits. Otherwise, once the
  VM has been up past the idle threshold, it reads its own compute metadata
  and a management token from IMDS (link-local, no stored credential),
  verifies the metadata names this machine, and calls deallocate on itself.
  Deallocate, not guest shutdown, is what releases compute billing.

**What we are asking for (summary):** nothing beyond what the pipeline
request already contains - the role definition arrives with the one-time
`access.bicep` deployment, the per-VM grants are made by the existing
assignment identity under its ABAC condition, and the Intune team deploys
the scheduled task alongside the other device policies.

For session hosts built before this was enabled, run the Assign stage's
grant once per existing VM (or re-run the pipeline for the RITM), since the
role grant normally happens at build time.

For copy/paste request templates (subscription, identity, ADO, ServiceNow,
Intune, Defender teams), reuse the wording in the POC's
[access request guide](../../docs/PRODUCTION-ACCESS-REQUEST-GUIDE.md) section 8,
substituting the identities and scopes from this document.
