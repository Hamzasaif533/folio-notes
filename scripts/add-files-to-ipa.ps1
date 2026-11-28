# Makes a copy of a built Folio.ipa with a folder of files inside it (Folio.app/BundledFiles/<folder name>).
# On first launch Folio turns each PDF, Word or PowerPoint file into a notebook, in library folders
# that match the folders on disk. The files never leave this computer: nothing is uploaded.
#
# Needs 7-Zip (it adds the files without touching what's already in the IPA, so the app keeps
# its file permissions).
#
#   powershell -ExecutionPolicy Bypass -File scripts\add-files-to-ipa.ps1 -Ipa Folio.ipa -Folder C:\Path\To\Course -Out Folio-Course.ipa
param(
    [Parameter(Mandatory = $true)] [string]$Ipa,
    [Parameter(Mandatory = $true)] [string]$Folder,
    [Parameter(Mandatory = $true)] [string]$Out
)
$ErrorActionPreference = 'Stop'

$sevenZip = @("$env:ProgramFiles\7-Zip\7z.exe", "${env:ProgramFiles(x86)}\7-Zip\7z.exe") |
    Where-Object { Test-Path $_ } | Select-Object -First 1
if (-not $sevenZip) { throw "7-Zip wasn't found. Install it from https://www.7-zip.org" }

$base = (Resolve-Path $Folder).Path.TrimEnd('\', '/')
$name = Split-Path $base -Leaf
$outPath = [System.IO.Path]::GetFullPath($Out)
Copy-Item -LiteralPath (Resolve-Path $Ipa).Path -Destination $outPath -Force

# The app folder's name inside the IPA (Payload/Folio.app).
$app = & $sevenZip l -ba -slt $outPath | Select-String '^Path = (Payload[\\/][^\\/]+\.app)$' |
    Select-Object -First 1 | ForEach-Object { $_.Matches[0].Groups[1].Value -replace '\\', '/' }
if (-not $app) { throw "No Payload/*.app inside $Ipa" }

# Lay the files out as they should sit in the IPA, then add that folder.
$stage = Join-Path ([System.IO.Path]::GetTempPath()) ("folio-ipa-" + [guid]::NewGuid())
$dest = Join-Path $stage ($app + '/BundledFiles/' + $name)
New-Item -ItemType Directory -Force $dest | Out-Null
$types = '.pdf', '.docx', '.doc', '.pptx', '.ppt', '.png', '.jpg', '.jpeg', '.heic'
$count = 0
try {
    Get-ChildItem -LiteralPath $base -Recurse -File |
        Where-Object { $_.Name -notlike '.*' -and $_.Name -notlike '~$*' -and $types -contains $_.Extension.ToLower() } |
        ForEach-Object {
            $rel = $_.FullName.Substring($base.Length).TrimStart('\', '/')
            $target = Join-Path $dest $rel
            New-Item -ItemType Directory -Force (Split-Path $target -Parent) | Out-Null
            Copy-Item -LiteralPath $_.FullName -Destination $target
            $count++
        }
    Push-Location $stage
    try {
        # Remove an earlier copy of the same folder, then add.
        & $sevenZip d -tzip $outPath ($app + '/BundledFiles/' + $name) -r | Out-Null
        & $sevenZip a -tzip -mx=5 $outPath 'Payload' | Out-Null
        if ($LASTEXITCODE -ne 0) { throw "7-Zip failed ($LASTEXITCODE)" }
    } finally { Pop-Location }
} finally {
    Remove-Item -Recurse -Force -LiteralPath $stage -ErrorAction SilentlyContinue
}
$mb = [math]::Round((Get-Item -LiteralPath $outPath).Length / 1MB)
Write-Output "Added $count files from '$name' -> $outPath ($mb MB)"
