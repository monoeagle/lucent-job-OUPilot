# run-docs.ps1 — Baut die OUPilot-Doku-Site und oeffnet sie.
#
#   .\run-docs.ps1              baut + oeffnet site\index.html im Browser
#   .\run-docs.ps1 -Serve       baut + startet lokalen Server (http://localhost:8099)
#   .\run-docs.ps1 -Serve -Port 9000
#   .\run-docs.ps1 -NoOpen      nur bauen (kein Browser)
#
# Abhaengigkeitsfrei: kein Python, kein pip, kein CDN. Reines PowerShell +
# statisches HTML (docs-site\Build-DocsSite.ps1).
param(
    [switch]$Serve,
    [int]$Port = 8099,
    [switch]$NoOpen
)
$ErrorActionPreference = 'Stop'
$here    = Split-Path -Parent $MyInvocation.MyCommand.Path
$builder = Join-Path $here 'docs-site\Build-DocsSite.ps1'
$siteDir = Join-Path $here 'docs-site\site'

# Bauen.
$index = & $builder
if (-not (Test-Path $index)) { throw "Build lieferte keine index.html ($index)" }

if (-not $Serve) {
    Write-Host "Oeffne: $index"
    if (-not $NoOpen) { Start-Process $index }
    Write-Host "Fertig. (Fuer lokalen Server: .\run-docs.ps1 -Serve)"
    return
}

# Lokaler Server via HttpListener (keine externen Abhaengigkeiten).
$prefix = "http://localhost:$Port/"
$listener = New-Object System.Net.HttpListener
$listener.Prefixes.Add($prefix)
try { $listener.Start() }
catch { throw "Konnte $prefix nicht binden ($($_.Exception.Message)). Anderen Port waehlen: -Port <n>." }

Write-Host ""
Write-Host "  OUPilot-Doku laeuft auf $prefix" -ForegroundColor Cyan
Write-Host "  Beenden mit Strg+C." -ForegroundColor DarkGray
Write-Host ""
if (-not $NoOpen) { Start-Process $prefix }

$mime = @{
    '.html' = 'text/html; charset=utf-8'; '.css' = 'text/css; charset=utf-8'
    '.js' = 'application/javascript; charset=utf-8'; '.json' = 'application/json'
    '.svg' = 'image/svg+xml'; '.png' = 'image/png'; '.ico' = 'image/x-icon'
}
try {
    while ($listener.IsListening) {
        $ctx = $listener.GetContext()
        $rel = [uri]::UnescapeDataString($ctx.Request.Url.AbsolutePath.TrimStart('/'))
        if ([string]::IsNullOrWhiteSpace($rel)) { $rel = 'index.html' }
        $full = Join-Path $siteDir $rel
        # Pfad-Traversal verhindern.
        $fullResolved = [System.IO.Path]::GetFullPath($full)
        if (-not $fullResolved.StartsWith([System.IO.Path]::GetFullPath($siteDir))) {
            $ctx.Response.StatusCode = 403; $ctx.Response.Close(); continue
        }
        if (Test-Path $fullResolved -PathType Leaf) {
            $bytes = [System.IO.File]::ReadAllBytes($fullResolved)
            $ext = [System.IO.Path]::GetExtension($fullResolved).ToLower()
            $ctx.Response.ContentType = if ($mime.ContainsKey($ext)) { $mime[$ext] } else { 'application/octet-stream' }
            $ctx.Response.OutputStream.Write($bytes, 0, $bytes.Length)
        } else {
            $ctx.Response.StatusCode = 404
            $msg = [System.Text.Encoding]::UTF8.GetBytes('404 - nicht gefunden')
            $ctx.Response.OutputStream.Write($msg, 0, $msg.Length)
        }
        $ctx.Response.Close()
    }
} finally {
    $listener.Stop(); $listener.Close()
}
