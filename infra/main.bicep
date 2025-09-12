targetScope = 'resourceGroup'

@minLength(1)
@maxLength(64)
@description('Name of the environment that can be used as part of naming resource convention, the name of the resource group for your application will use this name, prefixed with rg-')
param environmentName string

@minLength(1)
@description('The location used for all deployed resources')
param location string

@description('Id of the user or app to assign application roles')
param principalId string = ''


var tags = {
  'azd-env-name': environmentName
}

module resources 'resources.bicep' = {
  name: 'resources'
  params: {
    location: location
    tags: tags
    principalId: principalId
    environmentName: environmentName
  }
}

module key_vault 'key-vault/key-vault.module.bicep' = {
  name: 'key-vault'
  params: {
    location: location
  }
}
module key_vault_roles 'key-vault-roles/key-vault-roles.module.bicep' = {
  name: 'key-vault-roles'
  params: {
    key_vault_outputs_name: key_vault.outputs.name
    location: location
    principalId: resources.outputs.MANAGED_IDENTITY_PRINCIPAL_ID
    principalType: 'ServicePrincipal'
  }
}

output MANAGED_IDENTITY_CLIENT_ID string = resources.outputs.MANAGED_IDENTITY_CLIENT_ID
output MANAGED_IDENTITY_NAME string = resources.outputs.MANAGED_IDENTITY_NAME
output KEY_VAULT_VAULTURI string = key_vault.outputs.vaultUri
