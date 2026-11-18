#Requires -Version 5.1
[CmdletBinding()]
param(
    [Parameter(Mandatory)]
    [ValidatePattern('^[a-zA-Z0-9][a-zA-Z0-9.-]*$')]
    [string]$VmHost,

    [Parameter(Mandatory)]
    [ValidatePattern('^[a-z_][a-z0-9_-]*$')]
    [string]$SshUser,

    [ValidateRange(1, 65535)]
    [int]$SshPort = 22,

    [Parameter(Mandatory)]
    [string]$FullChain,

    [Parameter(Mandatory)]
    [string]$PrivateKey,

    [Parameter(Mandatory)]
    [string]$RootCA
)

$ErrorActionPreference = 'Stop'
$ssh = (Get-Command ssh.exe -CommandType Application -ErrorAction SilentlyContinue).Source
$scp = (Get-Command scp.exe -CommandType Application -ErrorAction SilentlyContinue).Source
if (-not $ssh -or -not $scp) {
    throw 'Install the Windows OpenSSH Client first. See bootstrap/readme.md.'
}

$inputs = [ordered]@{
    'fullchain.pem' = $FullChain
    'privkey.pem' = $PrivateKey
    'root-ca.crt' = $RootCA
}
$files = [ordered]@{}
foreach ($name in $inputs.Keys) {
    $file = Get-Item -LiteralPath $inputs[$name]
    if ($file -isnot [System.IO.FileInfo] -or $file.Length -eq 0) {
        throw "Expected a nonempty local file for $name."
    }
    $files[$name] = $file
}

$target = "$SshUser@$VmHost"
$folder = '.sd-lab-tls-' + [guid]::NewGuid().ToString('N')
$sshOptions = @('-o', 'StrictHostKeyChecking=yes', '-p', "$SshPort", $target)
$scpOptions = @('-o', 'StrictHostKeyChecking=yes', '-P', "$SshPort")

& $ssh @sshOptions "umask 077 && mkdir -m 700 -- $folder"
if ($LASTEXITCODE -ne 0) {
    throw 'Could not create a private directory on the VM. Verify SSH access and the VM host key.'
}

try {
    foreach ($name in $files.Keys) {
        $file = $files[$name]
        # A relative source avoids interpreting a Windows drive letter as an SSH host.
        Push-Location -LiteralPath $file.DirectoryName
        try {
            & $scp @scpOptions "./$($file.Name)" "${target}:${folder}/$name"
            if ($LASTEXITCODE -ne 0) {
                throw "SCP failed for $name."
            }
        } finally {
            Pop-Location
        }
    }
    & $ssh @sshOptions "chmod 600 -- $folder/fullchain.pem $folder/privkey.pem $folder/root-ca.crt"
    if ($LASTEXITCODE -ne 0) {
        throw 'Could not set TLS file permissions on the VM.'
    }
} catch {
    & $ssh @sshOptions "rm -f -- $folder/fullchain.pem $folder/privkey.pem $folder/root-ca.crt; rmdir -- $folder"
    if ($LASTEXITCODE -ne 0) {
        Write-Warning "Check the incomplete transfer in ~/$folder on the VM."
    }
    throw
}

Write-Output ('TLS_DIR="$HOME/{0}"' -f $folder)
