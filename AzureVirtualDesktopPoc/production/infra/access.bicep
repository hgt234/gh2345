targetScope = 'subscription'

metadata description = 'Production no-delete roles for one AVD workload whose VMs, host pool, and VNet sit in separate resource groups of one subscription. Deployed once per workload by an administrator; the build pipeline never runs this.'

@description('Short workload name, matching the avd-prod-<workload> variable group.')
@minLength(1)
@maxLength(31)
param workload string

@description('Resource group that receives the VMs, NICs, and OS disks.')
param sessionHostResourceGroupName string

@description('Resource group holding the existing host pool and desktop application group.')
param hostPoolResourceGroupName string

@description('Resource group holding the existing VNet.')
param networkResourceGroupName string

@description('Object ID of the workload identity used to deploy session hosts.')
param deploymentPrincipalId string

@description('Object ID of the workload identity used for readiness checks.')
param readinessPrincipalId string

@description('Object ID of the workload identity used for final user assignment and drain.')
param assignmentPrincipalId string

// Virtual Machine User Login and Desktop Virtualization User.
var assignableRoleIds = 'fb879df8-f326-4884-b1cf-06f3ad86be52, 1d18fff3-a72a-46b5-b4a9-0b38a3cd7e63'

// Deterministic GUID of the self-deallocate role below, needed inside the
// ABAC condition before the resource itself is declared.
var selfDeallocateRoleName = guid(subscription().id, 'avd-prod', workload, 'Self Deallocate')

// Limits role-assignment writes to exactly two grants: the two end-user roles
// to users, and the self-deallocate role to service principals (each VM's own
// system-assigned identity). This identity cannot grant Owner or anything
// else. The roles have no delete action, so no delete clause is needed.
// https://learn.microsoft.com/azure/role-based-access-control/delegate-role-assignments-examples
var assignmentCondition = '((!(ActionMatches{\'Microsoft.Authorization/roleAssignments/write\'})) OR ((@Request[Microsoft.Authorization/roleAssignments:RoleDefinitionId] ForAnyOfAnyValues:GuidEquals {${assignableRoleIds}} AND @Request[Microsoft.Authorization/roleAssignments:PrincipalType] ForAnyOfAnyValues:StringEqualsIgnoreCase {\'User\'}) OR (@Request[Microsoft.Authorization/roleAssignments:RoleDefinitionId] ForAnyOfAnyValues:GuidEquals {${selfDeallocateRoleName}} AND @Request[Microsoft.Authorization/roleAssignments:PrincipalType] ForAnyOfAnyValues:StringEqualsIgnoreCase {\'ServicePrincipal\'})))'

var roleSpecs = [
  {
    name: 'Deploy VMs'
    description: 'Deploy session hosts in the workload resource group. No delete actions. Extension write executes as SYSTEM in the guest and is restricted to the deployment pipeline.'
    resourceGroupName: sessionHostResourceGroupName
    principalId: deploymentPrincipalId
    condition: ''
    actions: [
      'Microsoft.Resources/subscriptions/resourceGroups/read'
      'Microsoft.Resources/deployments/read'
      'Microsoft.Resources/deployments/write'
      'Microsoft.Resources/deployments/validate/action'
      'Microsoft.Resources/deployments/whatIf/action'
      'Microsoft.Resources/deployments/operations/read'
      'Microsoft.Resources/deployments/operationStatuses/read'
      'Microsoft.Compute/*/read'
      'Microsoft.Compute/virtualMachines/write'
      'Microsoft.Compute/virtualMachines/extensions/write'
      'Microsoft.Compute/disks/write'
      'Microsoft.Network/networkInterfaces/read'
      'Microsoft.Network/networkInterfaces/write'
      'Microsoft.Network/networkInterfaces/join/action'
    ]
  }
  {
    name: 'Join Subnet'
    description: 'Attach session-host NICs to existing subnets. No network changes.'
    resourceGroupName: networkResourceGroupName
    principalId: deploymentPrincipalId
    condition: ''
    actions: [
      'Microsoft.Resources/subscriptions/resourceGroups/read'
      'Microsoft.Network/virtualNetworks/read'
      'Microsoft.Network/virtualNetworks/subnets/read'
      'Microsoft.Network/virtualNetworks/subnets/join/action'
    ]
  }
  {
    name: 'Register Hosts'
    description: 'Obtain or renew the existing host pool registration token. hostPools/write exists only for token renewal; the pipeline never changes any other pool property and the pool is never deployed.'
    resourceGroupName: hostPoolResourceGroupName
    principalId: deploymentPrincipalId
    condition: ''
    actions: [
      'Microsoft.DesktopVirtualization/hostPools/read'
      'Microsoft.DesktopVirtualization/hostPools/write'
      'Microsoft.DesktopVirtualization/hostPools/retrieveRegistrationToken/action'
    ]
  }
  {
    name: 'Check VMs'
    description: 'Read VM state and run the required-application inventory for readiness. Run Command executes as SYSTEM in the guest, so this identity is restricted to the readiness pipeline and its invocations are logged by Azure Activity Log.'
    resourceGroupName: sessionHostResourceGroupName
    principalId: readinessPrincipalId
    condition: ''
    actions: [
      'Microsoft.Compute/*/read'
      'Microsoft.Compute/virtualMachines/runCommand/action'
    ]
  }
  {
    name: 'Read Hosts'
    description: 'Read host pool and session-host state for readiness.'
    resourceGroupName: hostPoolResourceGroupName
    principalId: readinessPrincipalId
    condition: ''
    actions: [
      'Microsoft.DesktopVirtualization/hostPools/read'
      'Microsoft.DesktopVirtualization/hostPools/sessionHosts/read'
    ]
  }
  {
    name: 'Assign VM Login'
    description: 'Grant Virtual Machine User Login on session hosts. The ABAC condition restricts grants to the two end-user roles for users.'
    resourceGroupName: sessionHostResourceGroupName
    principalId: assignmentPrincipalId
    condition: assignmentCondition
    actions: [
      'Microsoft.Authorization/roleAssignments/read'
      'Microsoft.Authorization/roleAssignments/write'
      'Microsoft.Compute/virtualMachines/read'
    ]
  }
  {
    name: 'Assign Desktop'
    description: 'Grant desktop access, assign the session host, and drain it on failure. The ABAC condition restricts grants to the two end-user roles for users.'
    resourceGroupName: hostPoolResourceGroupName
    principalId: assignmentPrincipalId
    condition: assignmentCondition
    actions: [
      'Microsoft.Authorization/roleAssignments/read'
      'Microsoft.Authorization/roleAssignments/write'
      'Microsoft.DesktopVirtualization/hostPools/read'
      'Microsoft.DesktopVirtualization/hostPools/sessionHosts/read'
      'Microsoft.DesktopVirtualization/hostPools/sessionHosts/write'
    ]
  }
]

// The 'avd-prod' literal namespaces these GUIDs away from the phase01 role
// definitions, which omit it. Without it, a shared workload name would silently
// overwrite the phase01 role of the same spec name.
resource roles 'Microsoft.Authorization/roleDefinitions@2022-04-01' = [
  for spec in roleSpecs: {
    name: guid(subscription().id, 'avd-prod', workload, spec.name)
    properties: {
      roleName: 'AVD Prod ${spec.name} ${workload}'
      description: spec.description
      type: 'CustomRole'
      assignableScopes: [
        subscriptionResourceId('Microsoft.Resources/resourceGroups', spec.resourceGroupName)
      ]
      permissions: [
        {
          actions: spec.actions
          notActions: []
          dataActions: []
          notDataActions: []
        }
      ]
    }
  }
]

module assignments './modules/scoped-role-assignment.bicep' = [
  for (spec, index) in roleSpecs: {
    name: 'avd-prod-${index}-${uniqueString('avd-prod', workload, spec.name)}'
    scope: resourceGroup(spec.resourceGroupName)
    params: {
      principalId: spec.principalId
      roleDefinitionId: roles[index].id
      condition: spec.condition
    }
  }
]

// Usage-aware power-off: each session host's system-assigned identity is
// granted this role on its own VM only, by the assignment identity at build
// time (the ABAC condition above permits exactly that grant). A guest
// scheduled task then deallocates the VM when it has no sessions and has been
// up past the idle threshold. No deploy-time assignment exists here on
// purpose: the per-VM principal IDs do not exist until each VM is built.
resource selfDeallocateRole 'Microsoft.Authorization/roleDefinitions@2022-04-01' = {
  name: selfDeallocateRoleName
  properties: {
    roleName: 'AVD Prod Self Deallocate ${workload}'
    description: 'Lets a session host read and deallocate itself when idle. Granted per VM to that VM\'s own system-assigned identity by the build pipeline. No other action.'
    type: 'CustomRole'
    assignableScopes: [
      subscriptionResourceId('Microsoft.Resources/resourceGroups', sessionHostResourceGroupName)
    ]
    permissions: [
      {
        actions: [
          'Microsoft.Compute/virtualMachines/read'
          'Microsoft.Compute/virtualMachines/deallocate/action'
        ]
        notActions: []
        dataActions: []
        notDataActions: []
      }
    ]
  }
}

@description('Set AVD_SELF_DEALLOCATE_ROLE_ID in the workload variable group to this value.')
output selfDeallocateRoleDefinitionId string = selfDeallocateRole.name
