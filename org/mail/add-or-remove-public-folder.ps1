<#
  .SYNOPSIS
  Add or remove a public folder.

  .DESCRIPTION
  Assumes you already have at least on Public Folder Mailbox. It will not provision P.F. Mailboxes.

  .NOTES
  Permissions given to the Az Automation RunAs Account:
  AzureAD Roles:
  - Exchange administrator
  Office 365 Exchange Online API
  - Exchange.ManageAsApp

  .INPUTS
  RunbookCustomization: {
        "ParameterList": [
            {
                "DisplayName": "Action",
                "DisplayBefore": "MailboxName",
                "Select": {
                    "Options": [
                        {
                            "Display": "Add a Public Folder",
                            "Customization": {
                                "Default": {
                                    "AddPublicFolder": true
                                }
                            }
                        }, {
                            "Display": "Remove a Public folder",
                            "Customization": {
                                "Default": {
                                    "AddPublicFolder": false
                                },
                                "Hide": [
                                    "MailboxName"
                                ]
                            }
                        }
                    ]
                },
                "Default": "Add a Public Folder"
            },
            {
                "Name": "CallerName",
                "Hide": true
            },
            {
                "Name": "AddPublicFolder",
                "Hide": true
            }
        ]
    }

#>

#Requires -Modules @{ModuleName = "RealmJoin.RunbookHelper"; ModuleVersion = "0.6.0" }, ExchangeOnlineManagement

param
(
    [Parameter(Mandatory = $true)] 
    [ValidateScript( { Use-RJInterface -DisplayName "Name of the Public Folder" } )]
    [string] $PublicFolderName,
    [ValidateScript( { Use-RJInterface -DisplayName "Target Public Folder Mailbox (optional)" } )]
    [string] $MailboxName,
    [Parameter(Mandatory = $true)] 
    [ValidateScript( { Use-RJInterface -DisplayName "Add a Public Folder" } )]
    [bool] $AddPublicFolder,
    # CallerName is tracked purely for auditing purposes
    [Parameter(Mandatory = $true)]
    [string] $CallerName

)

try {
    Connect-RjRbExchangeOnline
    if ($AddPublicFolder) {
        "## Trying to create Public Folder '$PublicFolderName'"
        if ($MailboxName) {
            New-PublicFolder -Name $PublicFolderName -Mailbox $MailboxName | Out-Null
        }
        else {
            New-PublicFolder -Name $PublicFolderName | Out-Null
        }
        "## Public folder '$PublicFolderName' created."
    }
    else {
        "## Trying to remove Public Folder '$PublicFolderName'"
        $folder = Get-PublicFolder -Identity $PublicFolderName -ErrorAction SilentlyContinue
        if (-not $folder) {
            $folder  = Get-PublicFolder -Identity ("\" + $PublicFolderName) -ErrorAction SilentlyContinue
        }
        if ($folder) {
            Remove-PublicFolder -Identity ($folder.Identity) -Confirm:$false | Out-Null
            "## Public folder '$PublicFolderName' removed."
        } else {
            "## Public folder '$PublicFolderName' not found."
            throw "not found"
        }
    }

}
finally {
    Disconnect-ExchangeOnline -Confirm:$false | Out-Null
}