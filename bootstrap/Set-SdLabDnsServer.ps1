#Requires -RunAsAdministrator
[CmdletBinding()]
param(
    [Parameter(Mandatory)]
    [ValidatePattern('^[a-zA-Z0-9]([a-zA-Z0-9-]{0,61}[a-zA-Z0-9])?(\.[a-zA-Z0-9]([a-zA-Z0-9-]{0,61}[a-zA-Z0-9])?)+$')]
    [string]$ZoneName,

    [Parameter(Mandatory)]
    [System.Net.IPAddress]$VmAddress
)

$ErrorActionPreference = 'Stop'
if ($VmAddress.AddressFamily -ne [System.Net.Sockets.AddressFamily]::InterNetwork) {
    throw 'VmAddress must be IPv4.'
}

if (-not (Get-WindowsFeature -Name DNS).Installed) {
    $result = Install-WindowsFeature -Name DNS -IncludeManagementTools
    if (-not $result.Success -or $result.RestartNeeded -eq 'Yes') {
        throw 'Finish DNS role installation, restart if required, then run this script again.'
    }
}

Import-Module DnsServer
$zone = Get-DnsServerZone | Where-Object ZoneName -eq $ZoneName
if (-not $zone) {
    Add-DnsServerPrimaryZone -Name $ZoneName -ZoneFile "$ZoneName.dns" -DynamicUpdate None
} elseif ($zone.ZoneType -ne 'Primary' -or $zone.IsReadOnly) {
    throw "DNS zone $ZoneName must be a writable primary zone."
}

$names = '@', 'martin', 'titiler', 'rustfs', 's3', 'grafana', 'prometheus', 'alertmanager'
$missing = @()
$records = @(Get-DnsServerResourceRecord -ZoneName $ZoneName)
foreach ($name in $names) {
    $existing = @($records | Where-Object {
        $_.HostName -eq $name -and $_.RecordType -in 'A', 'AAAA', 'CNAME'
    })
    if ($existing.Count -eq 0) {
        $missing += $name
    } elseif ($existing.Count -ne 1 -or $existing[0].RecordType -ne 'A' -or
            $existing[0].RecordData.IPv4Address -ne $VmAddress) {
        throw "Conflicting record for '$name' in '$ZoneName'. Review it before rerunning."
    }
}

foreach ($name in $missing) {
    Add-DnsServerResourceRecordA -ZoneName $ZoneName -Name $name -IPv4Address $VmAddress -TimeToLive 00:05:00
}
Write-Output "Configured DNS records for $ZoneName -> $VmAddress"
