param location string
param LogicAppNameTeams string
param LogicAppNameSharePoint string
param AzureAutomationAccountName string
param AzureAutomationConnID string 
param SharePointConnID string 
param SharePointSiteUrl string 
param TeamsRequestListName string 
param SharePointActionListName string 


resource workflows_lapp_teams_resource 'Microsoft.Logic/workflows@2017-07-01' = {
  name: LogicAppNameTeams
  location: location
  identity: {
    type: 'SystemAssigned'
  }
  properties: {
    state: 'Enabled'
    definition: {
      '$schema': 'https://schema.management.azure.com/providers/Microsoft.Logic/schemas/2016-06-01/workflowdefinition.json#'
      contentVersion: '1.0.0.0'
      parameters: {
        '$connections': {
          defaultValue: {}
          type: 'Object'
        }
      }
      triggers: {
        When_an_item_is_created_or_modified: {
          recurrence: {
            frequency: 'Minute'
            interval: 1
          }
          evaluatedRecurrence: {
            frequency: 'Minute'
            interval: 1
          }
          splitOn: '@triggerBody()?[\'value\']'
          type: 'ApiConnection'
          inputs: {
            host: {
              connection: {
                name: '@parameters(\'$connections\')[\'sharepointonline\'][\'connectionId\']'
              }
            }
            method: 'get'
            path: '/datasets/@{encodeURIComponent(encodeURIComponent(\'${SharePointSiteUrl}\'))}/tables/@{encodeURIComponent(encodeURIComponent(\'${TeamsRequestListName}\'))}/onupdateditems'
          }
        }
      }
      actions: {
        Create_job: {
          runAfter: {}
          type: 'ApiConnection'
          inputs: {
            host: {
              connection: {
                name: '@parameters(\'$connections\')[\'azureautomation\'][\'connectionId\']'
              }
            }
            method: 'put'
            path: '/subscriptions/${subscription().subscriptionId}/resourceGroups/${resourceGroup().name}/providers/Microsoft.Automation/automationAccounts/${AzureAutomationAccountName}/jobs'
            queries: {
              runbookName: 'Clone-Team'
              wait: false
              'x-ms-api-version': '2015-10-31'
            }
          }
        }
      }
      outputs: {}
    }
    parameters: {
      '$connections': {
        value: {
          azureautomation: {
            connectionId: AzureAutomationConnID
            connectionName: 'azureautomation'
            id: '/subscriptions/${subscription().subscriptionId}/providers/Microsoft.Web/locations/${location}/managedApis/azureautomation'
          }
          sharepointonline: {
            connectionId: SharePointConnID
            connectionName: 'sharepointonline'
            id: '/subscriptions/${subscription().subscriptionId}/providers/Microsoft.Web/locations/${location}/managedApis/sharepointonline'
          }
        }
      }
    }
  }
}
resource workflows_lapp_requestAction_name_resource 'Microsoft.Logic/workflows@2017-07-01' = {
  name: LogicAppNameSharePoint
  location: location
  identity: {
    type: 'SystemAssigned'
  }
  properties: {
    state: 'Enabled'
    definition: {
      '$schema': 'https://schema.management.azure.com/providers/Microsoft.Logic/schemas/2016-06-01/workflowdefinition.json#'
      contentVersion: '1.0.0.0'
      parameters: {
        '$connections': {
          defaultValue: {}
          type: 'Object'
        }
      }
      triggers: {
        When_an_item_is_created_or_modified: {
          recurrence: {
            frequency: 'Minute'
            interval: 1
          }
          evaluatedRecurrence: {
            frequency: 'Minute'
            interval: 1
          }
          splitOn: '@triggerBody()?[\'value\']'
          type: 'ApiConnection'
          inputs: {
            host: {
              connection: {
                name: '@parameters(\'$connections\')[\'sharepointonline\'][\'connectionId\']'
              }
            }
            method: 'get'
            path: '/datasets/@{encodeURIComponent(encodeURIComponent(\'${SharePointSiteUrl}\'))}/tables/@{encodeURIComponent(encodeURIComponent(\'${SharePointActionListName}\'))}/onupdateditems'
          }
        }
      }
      actions: {
        Compose: {
          runAfter: {}
          type: 'Compose'
          inputs: 'RunBook:@{triggerBody()?[\'RunBook\']}\nParms:@{triggerBody()?[\'Parms\']}\nRunit:@{triggerBody()?[\'Runit\']}'
        }
        Condition: {
          actions: {
            Create_job: {
              runAfter: {}
              type: 'ApiConnection'
              inputs: {
                body: {
                  properties: {
                    parameters: {
                      Parms: '@triggerBody()?[\'Parms\']'
                      Runit: '@{triggerBody()?[\'Runit\']}'
                      Runbook: '@triggerBody()?[\'RunBook\']'
                      List: SharePointActionListName
                      ID: '@triggerBody()?[\'ID\']'
                    }
                  }
                }
                host: {
                  connection: {
                    name: '@parameters(\'$connections\')[\'azureautomation\'][\'connectionId\']'
                  }
                }
                method: 'put'
                path: '/subscriptions/${subscription().subscriptionId}/resourceGroups/${resourceGroup().name}/providers/Microsoft.Automation/automationAccounts/${AzureAutomationAccountName}/jobs'
                queries: {
                  runbookName: 'DrOctopus'
                  wait: false
                  'x-ms-api-version': '2015-10-31'
                }
              }
            }
          }
          runAfter: {
            Compose: [
              'Succeeded'
            ]
          }
          expression: {
            and: [
              {
                equals: [
                  '@triggerBody()?[\'Runit\']'
                  true
                ]
              }
            ]
          }
          type: 'If'
        }
      }
      outputs: {}
    }
    parameters: {
      '$connections': {
        value: {
          azureautomation: {
            connectionId: AzureAutomationConnID
            connectionName: 'azureautomation'
            id: '/subscriptions/${subscription().subscriptionId}/providers/Microsoft.Web/locations/${location}/managedApis/azureautomation'
          }
          sharepointonline: {
            connectionId: SharePointConnID
            connectionName: 'sharepointonline'
            id: '/subscriptions/${subscription().subscriptionId}/providers/Microsoft.Web/locations/${location}/managedApis/sharepointonline'
          }
        }
      }
    }
  }
}


