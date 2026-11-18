#Requires -RunAsAdministrator
[CmdletBinding(DefaultParameterSetName = 'Configure')]
param(
    [Parameter(Mandatory)]
    [uint32]$InterfaceIndex,

    [Parameter(Mandatory, ParameterSetName = 'Configure')]
    [System.Net.IPAddress[]]$DnsServer,

    [Parameter(Mandatory, ParameterSetName = 'Configure')]
    [string]$ZoneName,

    [Parameter(Mandatory, ParameterSetName = 'Reset')]
    [switch]$Reset,

    [Parameter(ParameterSetName = 'Configure')]
    [ValidateScript({ Test-Path -LiteralPath $_ -PathType Leaf })]
    [string]$RootCA
)

$ErrorActionPreference = 'Stop'
if ($Reset) {
    Set-DnsClientServerAddress -InterfaceIndex $InterfaceIndex -ResetServerAddresses
    Clear-DnsClientCache
    return
}

$names = $ZoneName, "martin.$ZoneName", "titiler.$ZoneName", "rustfs.$ZoneName", "s3.$ZoneName",
    "grafana.$ZoneName", "prometheus.$ZoneName", "alertmanager.$ZoneName"
foreach ($server in $DnsServer) {
    foreach ($name in $names) {
        $result = Resolve-DnsName -Name "$name." -Type A -Server $server.ToString() -DnsOnly
        if (-not ($result | Where-Object Type -eq 'A')) {
            throw "DNS server $server has no A record for $name."
        }
    }
}

if ($RootCA) {
    Import-Certificate -FilePath (Resolve-Path -LiteralPath $RootCA).Path -CertStoreLocation Cert:\LocalMachine\Root | Out-Null
}
Set-DnsClientServerAddress -InterfaceIndex $InterfaceIndex -ServerAddresses @($DnsServer | ForEach-Object { $_.ToString() })
Clear-DnsClientCache
Resolve-DnsName -Name "$ZoneName." -Type A -DnsOnly
