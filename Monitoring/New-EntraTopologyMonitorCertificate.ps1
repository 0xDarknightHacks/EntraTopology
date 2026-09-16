#requires -Version 7.2
#requires -RunAsAdministrator
<#
.SYNOPSIS
Creates the local certificate used by the EntraTopology monitoring job.

.DESCRIPTION
Creates a non-exportable RSA certificate in Cert:\LocalMachine\My and exports
only the public certificate (.cer) for upload to the Microsoft Entra app registration.
#>

[CmdletBinding(SupportsShouldProcess)]
param(
    [string]$Subject = 'CN=EntraTopology Monitor',
    [ValidateRange(1, 5)]
    [int]$ValidityYears = 2,
    [string]$PublicCertificatePath = (Join-Path $env:ProgramData 'EntraTopologyMonitor\EntraTopology-Monitor.cer')
)

$ErrorActionPreference = 'Stop'

if (-not $PSCmdlet.ShouldProcess($Subject, 'Create monitoring authentication certificate')) {
    return
}

$cert = New-SelfSignedCertificate `
    -Subject $Subject `
    -CertStoreLocation 'Cert:\LocalMachine\My' `
    -KeyExportPolicy NonExportable `
    -KeySpec Signature `
    -KeyAlgorithm RSA `
    -KeyLength 2048 `
    -HashAlgorithm SHA256 `
    -NotAfter (Get-Date).AddYears($ValidityYears)

$destination = [System.IO.Path]::GetFullPath($PublicCertificatePath)
$parent = Split-Path -Parent $destination
if ($parent) {
    New-Item -ItemType Directory -Force -Path $parent | Out-Null
}

Export-Certificate -Cert $cert -FilePath $destination -Force | Out-Null

[pscustomobject][ordered]@{
    Subject               = $cert.Subject
    Thumbprint            = $cert.Thumbprint
    Store                  = 'Cert:\LocalMachine\My'
    NotAfter               = $cert.NotAfter
    PublicCertificatePath = $destination
}
