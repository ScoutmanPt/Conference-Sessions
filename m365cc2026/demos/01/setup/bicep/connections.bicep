param location string = resourceGroup().location
param SharePointConnectionName string
param AzureAutomationAccountName string

var shpConnectionName= toLower(SharePointConnectionName)
var aaConnectionName= toLower(AzureAutomationAccountName)

resource SharePointConnection_resource 'Microsoft.Web/connections@2016-06-01' = {
  name: shpConnectionName
  location: location
  properties: {
    displayName: 'SharePoint Online Connection'
    customParameterValues: {}
    api: {
      name: shpConnectionName
      displayName: 'SharePoint Online connection'
      id: '/subscriptions/${subscription().subscriptionId}/providers/Microsoft.Web/locations/${location}/managedApis/sharepointonline'
      type: 'Microsoft.Web/locations/managedApis'
    }
  }
}
resource AzureAutomationConnection_resource 'Microsoft.Web/connections@2016-06-01' = {
  name: aaConnectionName
  location:location
  properties: {
    displayName: 'Azure Automation Connection'
    customParameterValues: {}
    api: {
      name: aaConnectionName
      displayName: 'Azure Automation'
      description: 'Azure Automation provides tools to manage your cloud and on-premises infrastructure seamlessly.'
      iconUri: 'https://connectoricons-prod.azureedge.net/releases/v1.0.1465/1.0.1465.2409/${aaConnectionName}/icon.png'
      brandColor: '#56A0D7'
      id: '/subscriptions/${subscription().subscriptionId}/providers/Microsoft.Web/locations/${location}/managedApis/azureautomation'
      type: 'Microsoft.Web/locations/managedApis'
    }
    testLinks: []
  }
}

