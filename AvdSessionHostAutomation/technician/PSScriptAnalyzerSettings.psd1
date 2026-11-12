@{
    # Unlike the pipeline scripts, everything in endpoint/ runs on the session
    # hosts under stock Windows PowerShell 5.1 (Intune scheduled task), so the
    # 5.1 compatibility rules apply here.
    Severity = @('Error', 'Warning')
    Rules = @{
        PSUseCompatibleSyntax = @{
            Enable = $true
            TargetVersions = @('5.1')
        }
        PSUseCompatibleCommands = @{
            Enable = $true
            TargetProfiles = @(
                'win-48_x64_10.0.17763.0_5.1.17763.316_x64_4.0.30319.42000_framework'
            )
        }
    }
}
