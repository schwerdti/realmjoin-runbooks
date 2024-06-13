<#
  .SYNOPSIS
  Microsoft Teams telephony offboarding
  
  .DESCRIPTION
  Remove the phone number and specific policies from a teams-enabled user. The runbook is part of the TeamsPhoneInventory.

  .NOTES
  Permissions: 
  The connection of the Microsoft Teams PowerShell module is ideally done through the Managed Identity of the Automation account of RealmJoin.
  If this has not yet been set up and the old "Service User" is still stored, the connect is still included for stability reasons. However, it should be switched to Managed Identity as soon as possible.
 
  .INPUTS
  RunbookCustomization: {
      "Parameters": {
          "AddDays": {
              "Hide": true
          },
          "SharepointURL": {
              "Hide": true,
              "Mandatory": true
          },
          "SharepointSite": {
              "Hide": true,
              "Mandatory": true
          },
          "SharepointTPIList": {
              "Hide": true,
              "Mandatory": true
          },
          "SharepointBlockExtensionList": {
              "Hide": true,
              "Mandatory": true
          },
          "CallerName": {
              "Hide": true
          }
      }
  }
#>

#Requires -Modules @{ModuleName = "RealmJoin.RunbookHelper"; ModuleVersion = "0.8.3" }, @{ModuleName = "MicrosoftTeams"; ModuleVersion = "5.9.0" }

param(
    # User which should be cleared
    [ValidateScript( { Use-RJInterface -Type Graph -Entity User -DisplayName "User" } )]
    [String] $UserName,
    #Number of days the phone number is blocked for a new assignment
    [ValidateScript( { Use-RJInterface -Type Setting -Attribute "TPI.BlockNumberforDays" } )]
    [String] $AddDays,
    
    # Define TeamsPhoneInventory SharePoint List
    [ValidateScript( { Use-RJInterface -Type Setting -Attribute "TPI.SharepointURL" } )]
    [string] $SharepointURL,
    [ValidateScript( { Use-RJInterface -Type Setting -Attribute "TPI.SharepointSite" } )]
    [string] $SharepointSite,
    [ValidateScript( { Use-RJInterface -Type Setting -Attribute "TPI.SharepointTPIList" } )]
    [string] $SharepointTPIList,
    [ValidateScript( { Use-RJInterface -Type Setting -Attribute "TPI.SharepointBlockExtensionList" } )]
    [String] $SharepointBlockExtensionList,
    

    # CallerName is tracked purely for auditing purposes
    [string] $CallerName
)


########################################################
##             function declaration
##          
########################################################
function Get-TPIList {
    param (
        [parameter(Mandatory = $true)]
        [String]
        $ListBaseURL,
        [parameter(Mandatory = $false)]
        [String]
        $ListName # Only for easier logging
    )
    
    #Get fresh status quo of the SharePoint List after updating
    
    Write-Output "GraphAPI - Get fresh StatusQuo of the SharePoint List $ListName"

    #Setup URL variables
    $GraphAPIUrl_StatusQuoSharepointList = $ListBaseURL + '/items'

    $AllItemsResponse = Invoke-RjRbRestMethodGraph -Resource $GraphAPIUrl_StatusQuoSharepointList -Method Get -UriQueryRaw 'expand=columns,items(expand=fields)' -FollowPaging
    $AllItems = $AllItemsResponse.fields

    return $AllItems

}

function Invoke-TPIRestMethod {
    param (
        [parameter(Mandatory = $true)]
        [String]
        $Uri,
        [parameter(Mandatory = $true)]
        [String]
        $Method,
        [parameter(Mandatory = $false)]
        [hashtable]
        $Body,
        [parameter(Mandatory = $true)]
        [String]
        $ProcessPart,
        [parameter(Mandatory = $false)]
        [String]
        $SkipThrow = $false
        
    )

    #ToFetchErrors (Throw)
    $ExitError = 0

    if (($Method -like "Post") -or ($Method -like "Patch")) {
        try {
            $TPIRestMethod = Invoke-RjRbRestMethodGraph -Resource $Uri -Method $Method -Body $Body
        }
        catch {
            
            Write-Output ""
            Write-Output "GraphAPI - Error! Process part: $ProcessPart"
            $StatusCode = $_.Exception.Response.StatusCode.value__ 
            $StatusDescription = $_.Exception.Response.ReasonPhrase
            Write-Output "GraphAPI - Error! StatusCode: $StatusCode"
            Write-Output "GraphAPI - Error! StatusDescription: $StatusDescription"
            Write-Output ""

            Write-Output "GraphAPI - One Retry after 5 seconds"
            Connect-RjRbGraph -Force
            Start-Sleep -Seconds 5
            try {
                $TPIRestMethod = Invoke-RjRbRestMethodGraph -Resource $Uri -Method $Method -Body $Body
                Write-Output "GraphAPI - 2nd Run for Process part: $ProcessPart is Ok"
            } catch {
                
                # $2ndLastError = $_.Exception
                $ExitError = 1
                $StatusCode = $_.Exception.Response.StatusCode.value__ 
                $StatusDescription = $_.Exception.Response.ReasonPhrase
                Write-Output "GraphAPI - Error! Process part: $ProcessPart error is still present!"
                Write-Output "GraphAPI - Error! StatusCode: $StatusCode"
                Write-Output "GraphAPI - Error! StatusDescription: $StatusDescription"
                Write-Output ""
                $ExitError = 1
            } 
        }
    }else{
        try {
            $TPIRestMethod = Invoke-RjRbRestMethodGraph -Resource $Uri -Method $Method
        }
        catch {
            
            Write-Output ""
            Write-Output "GraphAPI - Error! Process part: $ProcessPart"
            $StatusCode = $_.Exception.Response.StatusCode.value__ 
            $StatusDescription = $_.Exception.Response.ReasonPhrase
            Write-Output "GraphAPI - Error! StatusCode: $StatusCode"
            Write-Output "GraphAPI - Error! StatusDescription: $StatusDescription"
            Write-Output ""
            Write-Output "GraphAPI - One Retry after 5 seconds"
            Connect-RjRbGraph -Force
            Start-Sleep -Seconds 5
            try {
                $TPIRestMethod = Invoke-RjRbRestMethodGraph -Resource $Uri -Method $Method
                Write-Output "GraphAPI - 2nd Run for Process part: $ProcessPart is Ok"
            } catch {
                
                # $2ndLastError = $_.Exception
                $ExitError = 1
                $StatusCode = $_.Exception.Response.StatusCode.value__ 
                $StatusDescription = $_.Exception.Response.ReasonPhrase
                Write-Output "GraphAPI - Error! Process part: $ProcessPart error is still present!"
                Write-Output "GraphAPI - Error! StatusCode: $StatusCode"
                Write-Output "GraphAPI - Error! StatusDescription: $StatusDescription"
                Write-Output ""
            } 
        }
    }

    if ($ExitError -eq 1) {
        throw "GraphAPI - Error! Process part: $ProcessPart error is still present! StatusCode: $StatusCode StatusDescription: $StatusDescription"
        $StatusCode = $null
        $StatusDescription = $null
    }

    return $TPIRestMethod
    
}

########################################################
##             Block 0 - Connect Part
##          
########################################################
# Add Caller in Verbose output
Write-RjRbLog -Message "Caller: '$CallerName'" -Verbose

# Add Parameter in Verbose output
Write-RjRbLog -Message "SharepointURL: '$SharepointURL'" -Verbose
Write-RjRbLog -Message "SharepointSite: '$SharepointSite'" -Verbose
Write-RjRbLog -Message "SharepointTPIList: '$SharepointTPIList'" -Verbose
Write-RjRbLog -Message "SharepointBlockExtensionList: '$SharepointBlockExtensionList'" -Verbose
Write-RjRbLog -Message "BlockNumberforDays: '$AddDays'" -Verbose
    
# Needs a Microsoft Teams Connection First!
$TimeStamp = ([datetime]::now).tostring("yyyy-MM-dd HH:mm:ss")
Write-Output "$TimeStamp - Connection - Connect to Microsoft Teams (PowerShell as RealmJoin managed identity)"

$VerbosePreference = "SilentlyContinue"
Connect-MicrosoftTeams -Identity -ErrorAction Stop
$VerbosePreference = "Continue"

# Check if Teams connection is active
try {
    $Test = Get-CsTenant -ErrorAction Stop | Out-Null
}
catch {
    try {
        Start-Sleep -Seconds 5
        $Test = Get-CsTenant -ErrorAction Stop | Out-Null
    }
    catch {
        $TimeStamp = ([datetime]::now).tostring("yyyy-MM-dd HH:mm:ss")
        Write-Error "$TimeStamp - Teams PowerShell session could not be established. Stopping script!" 
        Exit
    }
}

# Initiate RealmJoin Graph Session
$TimeStamp = ([datetime]::now).tostring("yyyy-MM-dd HH:mm:ss")
Write-Output "$TimeStamp - Connection - Initiate RealmJoin Graph Session"
Connect-RjRbGraph

########################################################
##             Block 1 - Setup base URL
##          
########################################################
Write-Output ""
Write-Output "Block 1 - Check basic connection to TPI List and build base URL"

# Setup Base URL - not only for NumberRange etc.
if (($RunMode -like "AppBased") -or ($RunMode -like "Runbook")) {
    $BaseURL = 'https://graph.microsoft.com/v1.0/sites/' + $SharepointURL + ':/teams/' + $SharepointSite + ':/lists/'
}else{
    $BaseURL = '/sites/' + $SharepointURL + ':/teams/' + $SharepointSite + ':/lists/' 
}
$TPIListURL = $BaseURL + $SharepointTPIList
try {
    Invoke-TPIRestMethod -Uri $BaseURL -Method Get -ProcessPart "Check connection to TPI List" -ErrorAction Stop | Out-Null
}
catch {
    if (($RunMode -like "AppBased") -or ($RunMode -like "Runbook")) {
        $BaseURL = 'https://graph.microsoft.com/v1.0/sites/' + $SharepointURL + ':/sites/' + $SharepointSite + ':/lists/'
    }else{
        $BaseURL = '/sites/' + $SharepointURL + ':/sites/' + $SharepointSite + ':/lists/' 
    }
    $TPIListURL = $BaseURL + $SharepointTPIList
    try {
        Invoke-TPIRestMethod -Uri $BaseURL -Method Get -ProcessPart "Check connection to TPI List" | Out-Null
    }
    catch {
        $TimeStamp = ([datetime]::now).tostring("yyyy-MM-dd HH:mm:ss")
        Write-Error "$TimeStamp - Connection - Could not connect to SharePoint TPI List!"
        throw "$TimeStamp - Could not connect to SharePoint TPI List!"
        Exit
    }
}
Write-Output "Connection - SharePoint TPI List URL: $TPIListURL"


########################################################
##             Block 2 - Getting StatusQuo
##          
########################################################

Write-Output ""
Write-Output "Block 2 - Getting StatusQuo for $UserName"
$StatusQuo = Get-CsOnlineUser $UserName

$CurrentLineUri = $StatusQuo.LineURI -replace("tel:","")
$CurrentOnlineVoiceRoutingPolicy = $StatusQuo.OnlineVoiceRoutingPolicy
$CurrentTenantDialPlan = $StatusQuo.TenantDialPlan
$CurrentCallingPolicy = $StatusQuo.TeamsCallingPolicy
$OnlineVoicemailPolicy = $StatusQuo.OnlineVoicemailPolicy

if (!($CurrentLineUri.ToString().StartsWith("+"))) {
    # Add prefix "+", if not there
    $CurrentLineUri = "+" + $CurrentLineUri
}

if ($CurrentLineUri -like "+") {
    $CurrentLineUri = "none"
}

Write-Output "StatusQuo for $UserName"
Write-Output "Current LineUri - $CurrentLineUri"
Write-Output "Current OnlineVoiceRoutingPolicy - $CurrentOnlineVoiceRoutingPolicy"
Write-Output "Current TenantDialPlan - $CurrentTenantDialPlan"
Write-Output "Current CallingPolicy - $CurrentCallingPolicy"
Write-Output "Current VoiceMailPolicy - $OnlineVoicemailPolicy"
Write-Output ""

if ($CurrentLineUri -like "none") {
    Write-Error "The user has not assigned a phone number, therefore the runbook will be terminated now." -ErrorAction Continue
    Exit
}
########################################################
##             Block 3 - Remove Number from User
##          
########################################################

Write-Output ""
Write-Output "Block 3 - Clearing Teams user"

Write-Output "Remove LineUri"
try {
    Remove-CsPhoneNumberAssignment -Identity $UserName -RemoveAll
}
catch {
    $message = $_
    Write-Error "Teams - Error: Removing the LineUri for $UserName could not be completed! Error Message: $message" -ErrorAction Continue
    throw "Teams - Error: Removing the LineUri for $UserName could not be completed!"
}

Write-Output "Remove OnlineVoiceRoutingPolicy (Set to ""global"")"
try {
    Grant-CsOnlineVoiceRoutingPolicy -Identity $UserName -PolicyName $null
}
catch {
    $message = $_
    Write-Error "Teams - Error: Removing the of OnlineVoiceRoutingPolicy for $UserName could not be completed! Error Message: $message" -ErrorAction Continue
    throw "Teams - Error: Removing the OnlineVoiceRoutingPolicy for $UserName could not be completed!"
}

Write-Output "Remove (Tenant)DialPlan (Set to ""global"")"
try {
    Grant-CsTenantDialPlan -Identity $UserName -PolicyName $null
}
catch {
    $message = $_
    Write-Error "Teams - Error: Removing the of TenantDialPlan for $UserName could not be completed!Error Message: $message" -ErrorAction Continue
    throw "Teams - Error: Removing the of TenantDialPlan for $UserName could not be completed!"
}

Write-Output "Remove Teams IP-Phone Policy (Set to ""global"")"
try {
    Grant-CsTeamsIPPhonePolicy -Identity $UserName -PolicyName $null
}
catch {
    $message = $_
    Write-Error "Teams - Error: Removing the of Teams IP-Phone Policy for $UserName could not be completed!Error Message: $message" -ErrorAction Continue
    throw "Teams - Error: Removing the of Teams IP-Phone Policy for $UserName could not be completed!"
}



########################################################
##             Block 4 - GraphAPI Part
##          
########################################################

Write-Output ""
Write-Output "Block 4 - GraphAPI Part"

#Get Status Quo of the Sharepoint List
Write-Output "Get StatusQuo of the SharePoint List"

$AllItems = Get-TPIList -ListBaseURL $TPIListURL -ListName $SharepointTPIList

Write-Output "List Analysis - Items in SharePoint List: $($AllItems.Count)"

$ID = ($AllItems | Where-Object Title -like $CurrentLineUri).ID
$GraphAPIUrl_UpdateElement = $TPIListURL + '/items/'+ $ID

if($AddDays -like ""){
    $AddDays = 30
}

$BlockDay = (([datetime]::now).AddDays($AddDays)).tostring("dd.MM.yyyy")
$Status = "TMP-BlockNumber-Until_" + $BlockDay

$HTTPBody_UpdateElement = @{
    "fields" = @{
        "Status" = $Status
        "TeamsEXT" = ""
        "UPN" = ""
        "Display_Name" = ""
        "OnlineVoiceRoutingPolicy" = ""
        "TeamsCallingPolicy" = ""
        "DialPlan" = ""
        "TenantDialPlan" = ""
    }
}
Write-Output "Clear and block current entry for $CurrentLineUri in TPI"
$TMP = Invoke-TPIRestMethod -Uri $GraphAPIUrl_UpdateElement -Method Patch -Body $HTTPBody_UpdateElement -ProcessPart "TPI List - Update item: $CurrentLineUri"

$HTTPBody_UpdateElement = $null

###################################################################################

$BlockReason = "OffboardedUser_" + $UserName
$TPIBlockExtensionListURL = $BaseURL + $SharepointBlockExtensionList
$GraphAPIUrl_NewElement = $TPIBlockExtensionListURL + "/items"

#Remove teams extension if existing
if ($CurrentLineUri -like "*;ext=*") {
    $CurrentLineUri = $CurrentLineUri.Substring(0,($CurrentLineUri.Length-($CurrentLineUri.IndexOf(";ext=")-3)))
}

$HTTPBody_NewElement = @{
    "fields" = @{
        "Title" = $CurrentLineUri
        "BlockUntil" = $BlockDay
        "BlockReason" = $BlockReason
    }
}

Write-Output "Add a temporary entry in the BlockExtension list which blocks the phone number $CurrentLineUri until $BlockDay"
$TMP = Invoke-TPIRestMethod -Uri $GraphAPIUrl_NewElement -Method Post -Body $HTTPBody_NewElement -ProcessPart "BlockExtension List - add item: $CurrentLineUri"

$HTTPBody_NewElement = $null


Disconnect-MicrosoftTeams -Confirm:$false | Out-Null
Get-PSSession | Remove-PSSession | Out-Null