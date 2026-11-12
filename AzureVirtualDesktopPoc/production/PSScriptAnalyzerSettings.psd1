@{
    # These scripts run on Azure DevOps hosted agents under PowerShell 7
    # (AzureCLI@2 pscore and PowerShell@2 pwsh), so the Windows PowerShell 5.1
    # compatibility rules used by the endpoint projects do not apply here.
    Severity = @('Error', 'Warning')
}
