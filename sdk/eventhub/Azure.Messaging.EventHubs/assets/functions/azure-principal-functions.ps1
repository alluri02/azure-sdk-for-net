# Copyright (c) Microsoft Corporation. All rights reserved.
# Licensed under the MIT License.

using namespace System.Uri
using namespace Microsoft.Azure.Commands.ActiveDirectory
using namespace Microsoft.Azure.Commands.EventHub.Models

#region Principal

function GenerateRandomCredentials()
{
  <#
    .SYNOPSIS
      It creates random credentials and returns them.
  #>

  return New-Object Microsoft.Azure.Commands.ActiveDirectory.PSADPasswordCredential -Property @{StartDate=Get-Date; EndDate=Get-Date -Year 2099; Password="$(GenerateRandomPassword)"} 
}

function GenerateRandomPassword() 
{
  <#
    .SYNOPSIS
      Generates a random password that can be assigned to a service principal.
      
    .DESCRIPTION
      The password generated by this function will contain a mix of alpha,
      numeric, and special characters and will vary a small amount in its length.        
  #>

  $baseLength = (Get-Random -Minimum 28 -Maximum 37)      
  $upper = (Get-Random -Minimum 6 -Maximum ([int][Math]::Ceiling($baseLength / 3)))  
  $special = (Get-Random -Minimum 2 -Maximum 3)     
  $lower = ($baseLength - $upper - $special - $special)                                 

  $password = SelectRandomCharacters $lower "abcdefghiklmnoprstuvwxyz"
  $password += SelectRandomCharacters $upper "ABCDEFGHKLMNOPRSTUVWXYZ"
  $password += SelectRandomCharacters $special "1234567890"
  $password += SelectRandomCharacters $special "!$%&/()=?}][{@#*+"

  $scrambled = ($password.ToCharArray()) | Get-Random -Count ($password.Length)
  return (-join $scrambled)
}

function SelectRandomCharacters 
{    
  <#
    .SYNOPSIS
      Selects a number of random characters from a set.
  #>

  param
  (
    [Parameter(Mandatory=$true)]
    [int]$length, 

    [Parameter(Mandatory=$true)]
    [string]$characters
  ) 

  $random = (1..$length | ForEach { Get-Random -Maximum $characters.length })
  return (-join $characters[$random])
}

#endregion Principal

#region EventHubs

function CreateHubIfMissing()
{
  <#
    .SYNOPSIS
      It tries to retrieve the specified namespace.
      It creates if it may not be found.
  #>

  param
  (
    [Parameter(Mandatory=$true)]
    [string] $resourceGroupName,

    [Parameter(Mandatory=$true)]
    [string] $namespaceName,

    [Parameter(Mandatory=$true)]
    [string] $eventHubName
  )

  Write-Host "`t...Requesting eventHub"
  
  $eventHub = Get-AzEventHub -ResourceGroupName $resourceGroupName `
                             -NamespaceName $namespaceName `
                             -EventHubName $eventHubName `
                             -ErrorAction SilentlyContinue

  if ($eventHub -eq $null)
  {
      # Creates the Event Hub if does not exist
      Write-Host "`t...Creating new eventHub"

      New-AzEventHub -ResourceGroupName $resourceGroupName `
                     -NamespaceName $namespaceName `
                     -EventHubName $eventHubName | Out-Null

      return $true
  }

  return $false
}

function GetFullyQualifiedDomainName()
{
  <#
    .SYNOPSIS
      It takes an access key as input.
      It returns the fully qualified domain name (FQDN).

    .DESCRIPTION
      It returns the fully qualified domain name.
      It does that using the "System.Uri" namespace.

      https://docs.microsoft.com/en-us/azure/event-hubs/event-hubs-get-connection-string
  #>
  
  param
  (
    [Parameter(Mandatory=$true)]
    [string] $resourceGroupName,

    [Parameter(Mandatory=$true)]
    [string] $namespaceName
  )

  Write-Host "`t...Retrieving fully qualified domain name"

  $nameSpace = Get-AzEventHubNamespace -ResourceGroupName "$($resourceGroupName)" -NamespaceName "$($namespaceName)"

  if($null -eq $nameSpace)
  {
    Write-Error "`t...Could not retrieve the service bus endpoint associated with the namespace"

    return -1
  }

  $serviceBusEndpoint = $namespace.ServiceBusEndpoint

  if($null -eq $serviceBusEndpoint)
  {
    Write-Error "`t...Could not retrieve the service bus endpoint associated with the namespace"

    return -1
  }

  return ([System.Uri]$serviceBusEndpoint).Host
}

function GetRootManageSharedAccessKey()
{
  <#
    .SYNOPSIS
      It returns the access keys connected to a namespace.

    .DESCRIPTION
      It calls Get-AzEventHubKey and returns the PrimaryConnectionString.
  #>

  param
  (
    [Parameter(Mandatory=$true)]
    [string] $resourceGroupName,

    [Parameter(Mandatory=$true)]
    [string] $namespaceName
  )

  Write-Host "`t...Retrieving primary connection string"

  $keys = Get-AzEventHubKey -ResourceGroupName "$($resourceGroupName)" `
                            -NamespaceName "$($namespaceName)" `
                            -AuthorizationRuleName "RootManageSharedAccessKey"

  return $keys.PrimaryConnectionString
}

function GetNamespaceInformation()
{
  <#
    .SYNOPSIS
      It returns the access keys connected to a namespace.
      It returns the fully qualified domain name (FQDN).

    .DESCRIPTION
      It returns the access keys by calling 'GetRootManageSharedAccessKey'.
      It returns the fully qualified domain name (FQDN) by calling 'GetFullyQualifiedDomainName'.

      It aggregates the values into a single anonymous object.
  #>

  param
  (
    [Parameter(Mandatory=$true)]
    [string] $resourceGroupName,
    
    [Parameter(Mandatory=$true)]
    [string] $namespaceName
  )

  return [pscustomobject] @{
    FullyQualifiedDomainName = (GetFullyQualifiedDomainName -ResourceGroupName "$($resourceGroupName)" -NamespaceName "$($namespaceName)");
    PrimaryConnectionString = (GetRootManageSharedAccessKey -ResourceGroupName "$($resourceGroupName)" -NamespaceName "$($namespaceName)");
  }
}

#endregion EventHubs

#region ResourceManagement

function CreateNamespaceIfMissing()
{
  <#
    .SYNOPSIS
      It tries to retrieve the specified namespace.
      It creates one if it may not be found.
  #>

  param
  (
    [Parameter(Mandatory=$true)]
    [string] $resourceGroupName,

    [Parameter(Mandatory=$true)]
    [string] $namespaceName,

    [Parameter(Mandatory=$true)]  
    [string] $azureRegion
  )

  # Tries to retrieve the Namespace
  Write-Host "`t...Requesting namespace"

  $nameSpace = Get-AzEventHubNamespace -ResourceGroupName "$($resourceGroupName)" `
                                       -NamespaceName "$($namespaceName)" `
                                       -ErrorAction SilentlyContinue

  if ($nameSpace -eq $null)
  {
      # Creates the Namespace if does not exist
      Write-Host "`t...Creating new namespace"
      
      New-AzEventHubNamespace -ResourceGroupName "$($resourceGroupName)" `
                              -NamespaceName "$($namespaceName)" `
                              -Location "$($azureRegion)" | Out-Null

      return $true
  }

  return $false
}

function TearDownResources 
{
  <#
    .SYNOPSIS
      Cleans up any Azure resources created by the script.
      
    .DESCRIPTION
      Depending on the flags passed in, it will try to remove
      in order the named Azure Event Hub, Namespace and Resource Group.

      It does that calling the helper methods TearDownEventHub, TearDownNamespace
      and TearDownResourceGroup.
  #>
    
  param
  (
    [Parameter(Mandatory=$false)]
    [string] $resourceGroupName,

    [Parameter(Mandatory=$false)]
    [string] $namespaceName,
    
    [Parameter(Mandatory=$false)]
    [string] $eventHubName,

    [Parameter(Mandatory=$false)]
    [string] $isResourceGroupCreated = $false,

    [Parameter(Mandatory=$false)]
    [string] $isNamespaceCreated = $false,

    [Parameter(Mandatory=$false)]
    [string] $isEventHubCreated = $false
  )

  if($isEventHubCreated -eq $true)
  {
    TearDownEventHub -ResourceGroupName "$($resourceGroupName)" `
                     -NamespaceName "$($namespaceName)" `
                     -EventHubName "$($eventHubName)"
  }

  if($isNamespaceCreated -eq $true)
  {
    TearDownNamespace -ResourceGroupName "$($resourceGroupName)" `
                      -NamespaceName "$($namespaceName)"
  }

  if ($isResourceGroupCreated -eq $true)
  {
    TearDownResourceGroup -ResourceGroupName "$($resourceGroupName)"
  }
}

function TearDownEventHub()
{
  <#
    .SYNOPSIS
      Cleans up a named Azure Event Hub.
  #>

  param
  (
    [Parameter(Mandatory=$true)]
    [string] $resourceGroupName,

    [Parameter(Mandatory=$true)]
    [string] $namespaceName,

    [Parameter(Mandatory=$true)]
    [string] $eventHubName
  )

  try
  {
    Write-Host "`t...Removing event hub `"$($eventHubName)`""
    Remove-AzEventHub -ResourceGroupName "$($resourceGroupName)" `
                      -Namespace "$($namespaceName)" `
                      -Name "$($eventHubName)" | Out-Null
  }
  catch 
  {
    Write-Error "The event hub: $($eventHubName) could not be removed.  You will need to delete this manually."
    Write-Error ""            
    Write-Error $_.Exception.Message
  }
}

function TearDownNamespace()
{
  <#
    .SYNOPSIS
      Cleans up a named Azure Event Hub Namespace.
  #>

  param
  (
    [Parameter(Mandatory=$true)]
    [string] $resourceGroupName,

    [Parameter(Mandatory=$true)]
    [string] $namespaceName
  )

  try
  {
    Write-Host "`t...Removing namespace `"$($namespaceName)`""
    Remove-AzEventHubNamespace -Name "$($namespaceName)" `
                               -ResourceGroupName "$($resourceGroupName)" | Out-Null
  }
  catch 
  {
    Write-Error "The namespace: $($namespaceName) could not be removed.  You will need to delete this manually."
    Write-Error ""            
    Write-Error $_.Exception.Message
  }
}

function TearDownResourceGroup()
{
  <#
    .SYNOPSIS
      Cleans up a named Azure Resource Group.
  #>

  param
  (
    [Parameter(Mandatory=$true)]
    [string] $resourceGroupName
  )

  try 
  {
    Write-Host "`t...Removing resource group `"$($resourceGroupName)`""
    Remove-AzResourceGroup -Name "$($resourceGroupName)" -Force | Out-Null
  }
  catch 
  {
    Write-Error "The resource group: $($resourceGroupName) could not be removed.  You will need to delete this manually."
    Write-Error ""            
    Write-Error $_.Exception.Message
  }
}

function CreateServicePrincipalAndWait 
{
  <#
    .SYNOPSIS
      Creates a service principal on Azure Active Directory
      
    .DESCRIPTION
      Creates a service principal on Azure Active Directory
      with the specified name and credentials.

      It waits 60 seconds to allow the principal to be made available
      on Azure Active Directory for Role Base Access Control.
  #>

  param
  (
    [Parameter(Mandatory=$true)]
    [string] $servicePrincipalName,

    [Parameter(Mandatory=$true)]
    [PSADPasswordCredential] $credentials
  )

  Write-Host "`t...Creating new service principal"
  Start-Sleep 1

  $principal = New-AzADServicePrincipal -DisplayName "$($servicePrincipalName)" `
                                        -PasswordCredential $credentials `
                                        -ErrorAction SilentlyContinue

  if ($principal -eq $null)
  {
      Write-Error "Unable to create the service principal: $($ServicePrincipalName)"
      exit -1
  }

  Write-Host "`t...Waiting for identity propagation"

  Start-Sleep 60

  return $principal
}

function GetSubscriptionAndSetAzureContext
{
  <#
    .SYNOPSIS
      Get an Azure Subscription and sets the context using it.
      
    .DESCRIPTION
      Tries getting an Azure Subscription by name.
      It raises an error if not found. It sets the context 
      using its information otherwise.
  #>

  param
  (
    [Parameter(Mandatory=$true)]
    [string] $subscriptionName
  )

  # Capture the subscription.  The cmdlet will error if there was no subscription, 
  # so no need to validate.

  Write-Host ""
  Write-Host "Working:"
  Write-Host "`t...Requesting subscription"
  $subscription = Get-AzSubscription -SubscriptionName "$($subscriptionName)" -ErrorAction SilentlyContinue

  if ($subscription -eq $null)
  {
      Write-Error "Unable to locate the requested Azure subscription: $($subscriptionName)"
      exit -1
  }

  Set-AzContext -SubscriptionId "$($subscription.Id)" -Scope "Process" | Out-Null

  return $subscription
}

function CreateResourceGroupIfMissing()
{
  <#
    .SYNOPSIS
      It tries to retrieve the specified resource group.
      It creates if it may not be found.

    .DESCRIPTION
      It tries to retrieve the specified resource group.
      It creates if it may not be found.
  #>

  param
  (
    [Parameter(Mandatory=$true)]
    [string] $resourceGroupName,

    [Parameter(Mandatory=$true)]  
    [string] $azureRegion
  )

  # Create the resource group, if needed.

  Write-Host "`t...Requesting resource group"

  $createResourceGroup = $false
  $resourceGroup = (Get-AzResourceGroup -ResourceGroupName "$($resourceGroupName)" -ErrorAction SilentlyContinue)

  if ($resourceGroup -eq $null)
  {
      $createResourceGroup = $true
  }

  if ($createResourceGroup)
  {
      Write-Host "`t...Creating new resource group"
      $resourceGroup = (New-AzResourceGroup -Name "$($resourceGroupName)" -Location "$($azureRegion)")
  }

  if ($resourceGroup -eq $null)
  {
      Write-Error "Unable to locate or create the resource group: $($resourceGroupName)"
      exit -1
  }

  return $createResourceGroup
}

function AssignRole()
{
  <#
    .SYNOPSIS
      It tries to assign a role to an existing principal.

    .DESCRIPTION
      Using the principal and the resource passed as input,
      it tries to assign the specified role for the principal and the resource.
  #>

  param
  (
    [Parameter(Mandatory=$true)]
    [string] $applicationId,

    [Parameter(Mandatory=$true)]
    [string] $roleDefinitionName,

    [Parameter(Mandatory=$true)]
    [string] $resourceGroupName
  )

  # The propagation of the identity is non-deterministic.  Attempt to retry once after waiting for another minute if
  # the initial attempt fails.

  try 
  {
      Write-Host "`t...Assigning role '$roleDefinitionName' to resource group"

      New-AzRoleAssignment -ApplicationId "$($principal.ApplicationId)" `
                           -RoleDefinitionName "$($roleDefinitionName)" `
                           -ResourceGroupName "$($resourceGroupName)" | Out-Null
  }
  catch 
  {
      Write-Host "`t...Still waiting for identity propagation (this will take a moment)"
      Start-Sleep 60

      New-AzRoleAssignment -ApplicationId "$($principal.ApplicationId)" `
                           -RoleDefinitionName "$($roleDefinitionName)" `
                           -ResourceGroupName "$($resourceGroupName)" | Out-Null
      
      exit -1
  }    
}

function AssignRoleToNamespace()
{
  <#
    .SYNOPSIS
      It tries to assign a role to an existing principal and eventhubs namespace.
      
    .DESCRIPTION
      Using the principal and the resource passed as input,
      it tries to assign the specified role for the principal and the resource.

      It assigns the role to the named eventhubs namespace.
  #>

  param
  (
    [Parameter(Mandatory=$true)]
    [string] $applicationId,

    [Parameter(Mandatory=$true)]
    [string] $roleDefinitionName,

    [Parameter(Mandatory=$true)]
    [string] $resourceGroupName,

    [Parameter(Mandatory=$true)]
    [string] $namespaceName
  )

  try
  {
      Write-Host "`t...Assigning role '$roleDefinitionName' to namespace"

      New-AzRoleAssignment -ApplicationId "$($principal.ApplicationId)" `
                           -RoleDefinitionName "$($roleDefinitionName)" `
                           -ResourceGroupName "$($resourceGroupName)" `
                           -ResourceName "$($namespaceName)" `
                           -ResourceType "Microsoft.EventHub/namespaces" | Out-Null
  }
  catch 
  {
      Write-Host "`t...Still waiting for identity propagation (this will take a moment)"
      Start-Sleep 60

      New-AzRoleAssignment -ApplicationId "$($principal.ApplicationId)" `
                           -RoleDefinitionName "$($roleDefinitionName)" `
                           -ResourceGroupName "$($resourceGroupName)" `
                           -ResourceName "$($namespaceName)" `
                           -ResourceType "Microsoft.EventHub/namespaces" | Out-Null
      
      exit -1
  }    
}

#endregion ResourceManagement

#region Validation

function ValidateParameters() 
{
  <#
    .SYNOPSIS
      Checks if a region provides Azure Event Hubs
      
    .DESCRIPTION
      Lists all the regions that provide Azure Event Hubs
      and looks for the one passed in as a parameter. It returns 
      true if found or false otherwise. It outputs an error message listing 
      all the available regions if the one chosen could not be found.
  #>

  param
  (
    [Parameter(Mandatory=$true)]
    [string] $servicePrincipalName,

    [Parameter(Mandatory=$true)]
    [string] $azureRegion
  )

  ValidateServicePrincipal -ServicePrincipalName "$($servicePrincipalName)"
  ValidateAzureRegion -AzureRegion "$($azureRegion)"
}

function ValidateServicePrincipal() 
{
  <#
    .SYNOPSIS
      It validates the service principal name.
      
    .DESCRIPTION
      Checks if the service principal contains any space.
      It returns an error if any is found.
  #>

  param
  (
    [Parameter(Mandatory=$true)]
    [string] $servicePrincipalName
  )

  # Disallow principal names with a space.
  if ($servicePrincipalName.Contains(" ")) 
  {
    Write-Error "The principal name may not contain spaces."
    exit -1
  }
}

function ValidateAzureRegion 
{
  <#
    .SYNOPSIS
      Checks if a region provides Azure Event Hubs.
      
    .DESCRIPTION
      Lists all the regions that provide Azure Event Hubs
      and looks for the one passed in as a parameter. It returns 
      true if found or false otherwise. It outputs an error message listing 
      all the available regions if the one chosen could not be found.
  #>

  param
  (
    [Parameter(Mandatory=$true)]
    [string] $azureRegion
  )

  # Verify the location is valid for an Event Hubs namespace.

  $validLocations = @{ }

  Get-AzLocation | where { $_.Providers.Contains("Microsoft.EventHub") } | ForEach { $validLocations[$_.Location] = $_.Location }

  $isValidLocation = $validLocations.Contains($azureRegion)

  if (!$isValidLocation) 
  {
    Write-Error "The Azure region must be one of: `n$($validLocations.Keys -join ", ")`n`n" 

    exit -1
  }
}

#endregion Validation