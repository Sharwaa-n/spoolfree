#Requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '5.0' }
# Default duplex (manifest printer.defaultSides). Run: Invoke-Pester -Path agent/tests

BeforeAll {
    Import-Module (Join-Path $PSScriptRoot '..\Spoolfree.Agent.psm1') -Force
}

Describe 'Default duplex' {
    It 'maps IPP sides keywords to Set-PrintConfiguration duplexing modes' {
        ConvertTo-SpoolfreeDuplexingMode 'one-sided' | Should -Be 'OneSided'
        ConvertTo-SpoolfreeDuplexingMode 'two-sided-long-edge' | Should -Be 'TwoSidedLongEdge'
        ConvertTo-SpoolfreeDuplexingMode 'two-sided-short-edge' | Should -Be 'TwoSidedShortEdge'
        ConvertTo-SpoolfreeDuplexingMode 'auto' | Should -BeNullOrEmpty
        ConvertTo-SpoolfreeDuplexingMode 'duplex' | Should -BeNullOrEmpty
        ConvertTo-SpoolfreeDuplexingMode '' | Should -BeNullOrEmpty
    }
    It 'reads the desired value from the manifest, auto when missing or unknown (old servers)' {
        Get-SpoolfreeDesiredSides ([pscustomobject]@{ name = 'A'; defaultSides = 'two-sided-long-edge' }) | Should -Be 'two-sided-long-edge'
        Get-SpoolfreeDesiredSides ([pscustomobject]@{ name = 'A' }) | Should -Be 'auto'
        Get-SpoolfreeDesiredSides ([pscustomobject]@{ name = 'A'; defaultSides = 'bogus' }) | Should -Be 'auto'
    }
    It 'applies only when the manifest value changes or the queue was re-created' {
        Test-SpoolfreeDuplexNeeded -Desired 'two-sided-long-edge' -Applied '' -Recreated $false | Should -BeTrue
        Test-SpoolfreeDuplexNeeded -Desired 'two-sided-long-edge' -Applied 'two-sided-long-edge' -Recreated $false | Should -BeFalse
        Test-SpoolfreeDuplexNeeded -Desired 'two-sided-long-edge' -Applied 'two-sided-long-edge' -Recreated $true | Should -BeTrue
        Test-SpoolfreeDuplexNeeded -Desired 'one-sided' -Applied 'two-sided-long-edge' -Recreated $false | Should -BeTrue
        Test-SpoolfreeDuplexNeeded -Desired 'auto' -Applied 'two-sided-long-edge' -Recreated $true | Should -BeFalse
        Test-SpoolfreeDuplexNeeded -Desired 'auto' -Applied '' -Recreated $false | Should -BeFalse
    }
    It 'calls Set-PrintConfiguration with the mapped mode' {
        Mock -ModuleName Spoolfree.Agent Set-PrintConfiguration { }
        Set-SpoolfreeQueueDuplex -Name 'Staff Copier' -Sides 'two-sided-short-edge'
        Should -Invoke -ModuleName Spoolfree.Agent Set-PrintConfiguration -Times 1 -ParameterFilter { $PrinterName -eq 'Staff Copier' -and $DuplexingMode -eq 'TwoSidedShortEdge' }
        { Set-SpoolfreeQueueDuplex -Name 'X' -Sides 'auto' } | Should -Throw
    }
}

Describe 'Installable duplex unit (0.9.5)' {
    BeforeAll {
        $script:NotInstalled = @(
            [pscustomobject]@{ PropertyName = 'Config:Memory'; Value = '512MB' },
            [pscustomobject]@{ PropertyName = 'Config:DuplexUnit'; Value = 'NotInstalled' }
        )
    }
    It 'names the duplex property only for a two-sided printer whose driver says NotInstalled' {
        Get-SpoolfreeDuplexUnitProperty -Properties $script:NotInstalled -TwoSided $true | Should -Be 'Config:DuplexUnit'
        Get-SpoolfreeDuplexUnitProperty -Properties @([pscustomobject]@{ PropertyName = 'Config:Duplexer'; Value = 'NotInstalled' }) -TwoSided $true | Should -Be 'Config:Duplexer'
    }
    It 'leaves the driver alone when the printer is one-sided or unknown (old servers, no Test)' {
        Get-SpoolfreeDuplexUnitProperty -Properties $script:NotInstalled -TwoSided $false | Should -BeNullOrEmpty
        Get-SpoolfreeDuplexUnitProperty -Properties $script:NotInstalled -TwoSided $null | Should -BeNullOrEmpty
        Get-SpoolfreeDuplexUnitProperty -Properties $script:NotInstalled -TwoSided 'true' | Should -BeNullOrEmpty
    }
    It 'never changes an Installed value or other properties' {
        Get-SpoolfreeDuplexUnitProperty -Properties @([pscustomobject]@{ PropertyName = 'Config:DuplexUnit'; Value = 'Installed' }) -TwoSided $true | Should -BeNullOrEmpty
        Get-SpoolfreeDuplexUnitProperty -Properties @([pscustomobject]@{ PropertyName = 'Config:Tray3'; Value = 'NotInstalled' }) -TwoSided $true | Should -BeNullOrEmpty
        Get-SpoolfreeDuplexUnitProperty -Properties @([pscustomobject]@{ PropertyName = 'DuplexUnit'; Value = 'NotInstalled' }) -TwoSided $true | Should -BeNullOrEmpty
        Get-SpoolfreeDuplexUnitProperty -Properties @() -TwoSided $true | Should -BeNullOrEmpty
        Get-SpoolfreeDuplexUnitProperty -Properties $null -TwoSided $true | Should -BeNullOrEmpty
    }
    It 'sets the property to Installed on the queue' {
        Mock -ModuleName Spoolfree.Agent Get-PrinterProperty { $script:NotInstalled }
        Mock -ModuleName Spoolfree.Agent Set-PrinterProperty {}
        Set-SpoolfreeDuplexUnit -Name 'Staff Color' -TwoSided $true | Should -Be 'Config:DuplexUnit'
        Should -Invoke -ModuleName Spoolfree.Agent Set-PrinterProperty -Times 1 -Exactly -ParameterFilter { $PrinterName -eq 'Staff Color' -and $PropertyName -eq 'Config:DuplexUnit' -and $Value -eq 'Installed' }
    }
    It 'does not read or change the driver for a printer that is not two-sided' {
        Mock -ModuleName Spoolfree.Agent Get-PrinterProperty { $script:NotInstalled }
        Mock -ModuleName Spoolfree.Agent Set-PrinterProperty {}
        Set-SpoolfreeDuplexUnit -Name 'Staff Mono' -TwoSided $false | Should -BeNullOrEmpty
        Should -Invoke -ModuleName Spoolfree.Agent Get-PrinterProperty -Times 0
        Should -Invoke -ModuleName Spoolfree.Agent Set-PrinterProperty -Times 0
    }
}
