metadata description = 'One role assignment in this resource group, with an optional ABAC condition.'

param principalId string
param roleDefinitionId string

@description('ABAC condition. Leave empty for an unconditional assignment.')
param condition string = ''

resource assignment 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  name: guid(resourceGroup().id, principalId, roleDefinitionId)
  properties: {
    principalId: principalId
    principalType: 'ServicePrincipal'
    roleDefinitionId: roleDefinitionId
    condition: empty(condition) ? null : condition
    conditionVersion: empty(condition) ? null : '2.0'
  }
}
