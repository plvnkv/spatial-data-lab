#Requires -Version 5.1
[CmdletBinding()]
param(
    [Parameter(Mandatory)]
    [string]$OutputDirectory,

    [string]$OpenSslPath = 'openssl.exe'
)

$ErrorActionPreference = 'Stop'
$openssl = (Get-Command $OpenSslPath -CommandType Application).Source
$directory = $ExecutionContext.SessionState.Path.GetUnresolvedProviderPathFromPSPath($OutputDirectory)
if (Test-Path -LiteralPath $directory) {
    throw "Choose a new output directory. It already exists: $directory"
}
if (-not [System.IO.Directory]::Exists([System.IO.Path]::GetDirectoryName($directory))) {
    throw 'Create the parent directory first.'
}

function Invoke-OpenSsl {
    & $openssl @args
    if ($LASTEXITCODE -ne 0) {
        throw "OpenSSL $($args[0]) failed with exit code $LASTEXITCODE."
    }
}

New-Item -ItemType Directory -Path $directory | Out-Null
try {
    $sid = [System.Security.Principal.WindowsIdentity]::GetCurrent().User.Value
    & icacls.exe $directory /inheritance:r /grant:r "*${sid}:(OI)(CI)F" '*S-1-5-18:(OI)(CI)F' | Out-Null
    if ($LASTEXITCODE -ne 0) {
        throw 'Could not restrict permissions on the TLS directory.'
    }

    Push-Location -LiteralPath $directory
    try {
        New-Item -ItemType Directory -Path 'ca-private' | Out-Null
        $caKey = 'ca-private/root-ca.key.pem'
        @'
[req]
distinguished_name = dn
[dn]
[ca]
basicConstraints = critical,CA:TRUE,pathlen:0
keyUsage = critical,keyCertSign,cRLSign
subjectKeyIdentifier = hash
[server]
basicConstraints = critical,CA:FALSE
keyUsage = critical,digitalSignature,keyEncipherment
extendedKeyUsage = serverAuth
subjectKeyIdentifier = hash
authorityKeyIdentifier = keyid
subjectAltName = DNS:sd.xenon.local,DNS:*.sd.xenon.local
'@ | Set-Content -LiteralPath 'tls.cnf' -Encoding Ascii

        Write-Host 'Choose and confirm a passphrase for the CA key. Enter it again when signing.'
        Invoke-OpenSsl genpkey -algorithm RSA -pkeyopt rsa_keygen_bits:3072 -aes-256-cbc -out $caKey
        Invoke-OpenSsl req -new -x509 -sha256 -days 3650 -key $caKey -subj '/CN=SD LAB Root CA' -config tls.cnf -extensions ca -out root-ca.crt
        Invoke-OpenSsl genpkey -algorithm RSA -pkeyopt rsa_keygen_bits:2048 -out privkey.pem
        Invoke-OpenSsl req -new -sha256 -key privkey.pem -subj '/CN=sd.xenon.local' -config tls.cnf -out server.csr
        $serial = Invoke-OpenSsl rand -hex 16
        Invoke-OpenSsl x509 -req -sha256 -days 365 -in server.csr -CA root-ca.crt -CAkey $caKey -set_serial "0x$serial" -extfile tls.cnf -extensions server -out fullchain.pem
        foreach ($name in 'sd.xenon.local', 'grafana.sd.xenon.local') {
            Invoke-OpenSsl verify -CAfile root-ca.crt -purpose sslserver -verify_hostname $name fullchain.pem | Out-Host
        }
        Remove-Item -LiteralPath 'tls.cnf', 'server.csr'
    } finally {
        Pop-Location
    }
} catch {
    Remove-Item -LiteralPath $directory -Recurse -Force
    throw
}

'fullchain.pem', 'privkey.pem', 'root-ca.crt' | ForEach-Object { Join-Path $directory $_ }
