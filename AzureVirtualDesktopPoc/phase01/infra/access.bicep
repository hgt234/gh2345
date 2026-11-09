targetScope = 'subscription'

metadata description = 'Phase 01 no-delete roles for one workload whose VMs, host pool, and VNet sit in separate resource groups of one subscription.'

@description('Short workload name, matching the avd-phase01-<workload> variable group.')
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

// Limits role-assignment writes to those two roles for users, so this identity
// cannot grant Owner. The roles have no delete action, so no delete clause is needed.
// https://learn.microsoft.com/azure/role-based-access-control/delegate-role-assignments-examples
var assignmentCondition = '((!(ActionMatches{\'Microsoft.Authorization/roleAssignments/write\'})) OR (@Request[Microsoft.Authorization/roleAssignments:RoleDefinitionId] ForAnyOfAnyValues:GuidEquals {${assignableRoleIds}} AND @Request[Microsoft.Authorization/roleAssignments:PrincipalType] ForAnyOfAnyValues:StringEqualsIgnoreCase {\'User\'}))'

var roleSpecs = [
  {
    name: 'Deploy VMs'
    description: 'Deploy session hosts in the workload resource group. No delete actions.'
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
    description: 'Obtain or renew the existing host pool registration token.'
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
    name: 'Read VMs'
    description: 'Read VM state for readiness. No Run Command.'
    resourceGroupName: sessionHostResourceGroupName
    principalId: readinessPrincipalId
    condition: ''
    actions: [
      'Microsoft.Compute/*/read'
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
    description: 'Grant Virtual Machine User Login on session hosts.'
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
    description: 'Grant desktop access, assign the session host, and drain it on failure.'
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

resource roles 'Microsoft.Authorization/roleDefinitions@2022-04-01' = [
  for spec in roleSpecs: {
    name: guid(subscription().id, workload, spec.name)
    properties: {
      roleName: 'AVD Phase01 ${spec.name} ${workload}'
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
    name: 'avd-phase01-${index}-${uniqueString(workload, spec.name)}'
    scope: resourceGroup(spec.resourceGroupName)
    params: {
      principalId: spec.principalId
      roleDefinitionId: roles[index].id
      condition: spec.condition
    }
  }
]
