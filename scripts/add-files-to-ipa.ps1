# Makes a copy of a built Folio.ipa with a folder of files inside it (Folio.app/BundledFiles/<folder name>).
# On first launch Folio turns each PDF, Word or PowerPoint file into a notebook, in library folders
# that match the folders on disk. The files never leave this computer: nothing is uploaded.
#
#   powershell -ExecutionPolicy Bypass -File scripts\add-files-to-ipa.ps1 -Ipa Folio.ipa -Folder C:\Path\To\Course -Out Folio-Course.ipa
param(
    [Parameter(Mandatory = $true)] [string]$Ipa,
    [Parameter(Mandatory = $true)] [string]$Folder,
    [Parameter(Mandatory = $true)] [string]$Out
)
$ErrorActionPreference = 'Stop'
Add-Type -AssemblyName System.IO.Compression
Add-Type -AssemblyName System.IO.Compression.FileSystem

$base = (Resolve-Path $Folder).Path.TrimEnd('\', '/')
$name = Split-Path $base -Leaf
$outPath = [System.IO.Path]::GetFullPath($Out)
Copy-Item -LiteralPath (Resolve-Path $Ipa).Path -Destination $outPath -Force

$zip = [System.IO.Compression.ZipFile]::Open($outPath, [System.IO.Compression.ZipArchiveMode]::Update)
try {
    $first = $zip.Entries | Where-Object { $_.FullName -match '^Payload/[^/]+\.app/' } | Select-Object -First 1
    if (-not $first) { throw "No Payload/*.app inside $Ipa" }
    $app = $first.FullName -replace '^(Payload/[^/]+\.app/).*$', '$1'
    $prefix = $app + 'BundledFiles/' + $name + '/'

    # Replace an earlier copy of the same folder.
    @($zip.Entries | Where-Object { $_.FullName.StartsWith($prefix) }) | ForEach-Object { $_.Delete() }

    $count = 0
    $types = '.pdf', '.docx', '.doc', '.pptx', '.ppt', '.png', '.jpg', '.jpeg', '.heic'
    Get-ChildItem -LiteralPath $base -Recurse -File |
        Where-Object { $_.Name -notlike '.*' -and $_.Name -notlike '~$*' -and $types -contains $_.Extension.ToLower() } |
        ForEach-Object {
            $rel = $_.FullName.Substring($base.Length).TrimStart('\', '/') -replace '\\', '/'
            $entry = [System.IO.Compression.ZipFileExtensions]::CreateEntryFromFile(
                $zip, $_.FullName, $prefix + $rel, [System.IO.Compression.CompressionLevel]::Optimal)
            $entry.ExternalAttributes = 0x81A40000   # regular file, rw-r--r--
            $count++
        }
} finally {
    $zip.Dispose()
}
$mb = [math]::Round((Get-Item -LiteralPath $outPath).Length / 1MB)
Write-Output "Added $count files from '$name' -> $outPath ($mb MB)"
