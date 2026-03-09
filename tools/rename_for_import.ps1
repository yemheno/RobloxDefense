<#
.SYNOPSIS
Renames all FBX and PNG files in RobloxAssets to include the character name prefix,
updates manifest.json paths accordingly, and copies every renamed file to a flat
__BulkImport\ folder so Studio's bulk importer can grab them all at once.

.EXAMPLE
.\tools\rename_for_import.ps1 -DryRun   # preview only
.\tools\rename_for_import.ps1           # apply renames + build BulkImport folder
#>
param([switch]$DryRun)

$baseDir = "C:\Users\P_Guilleminot\Desktop\Developer\RobloxAssets"
$bulkDir = Join-Path $baseDir "__BulkImport"

if (-not $DryRun) {
    New-Item -ItemType Directory -Force -Path $bulkDir | Out-Null
}

$totalFbx = 0
$totalPng = 0

foreach ($charDir in Get-ChildItem $baseDir -Directory | Where-Object { $_.Name -ne "__BulkImport" }) {
    $char = $charDir.Name   # e.g. "Xiao", "Hu Tao", "Dvalin"

    foreach ($manifestFile in Get-ChildItem $charDir.FullName -Recurse -Filter "manifest.json") {
        $mDir    = $manifestFile.DirectoryName
        $manifest = Get-Content $manifestFile.FullName -Raw | ConvertFrom-Json
        $changed  = $false

        # ── Rename / copy FBX parts ───────────────────────────────────────────
        if ($manifest.parts) {
            foreach ($partKey in $manifest.parts.PSObject.Properties.Name) {
                $relPath = $manifest.parts.$partKey.file   # e.g. "r6\Head.fbx"
                $absPath = Join-Path $mDir $relPath
                if (-not (Test-Path $absPath)) {
                    Write-Warning "  Missing FBX: $absPath"
                    continue
                }

                $f        = Get-Item $absPath
                $subDir   = Split-Path $relPath -Parent   # e.g. "r6", ""
                $fileName = $f.Name                       # e.g. "Head.fbx"

                # Already prefixed?
                if ($f.BaseName -like "$char*") {
                    # Just copy to BulkImport
                    if (-not $DryRun) {
                        $dest = Join-Path $bulkDir $f.Name
                        if (-not (Test-Path $dest)) { Copy-Item $f.FullName $dest }
                    }
                    continue
                }

                $newName    = "${char}_${fileName}"
                $newAbsPath = Join-Path $f.DirectoryName $newName
                $newRelPath = if ($subDir -eq "") { $newName } else { "${subDir}\${newName}" }

                if ($DryRun) {
                    Write-Host "[DRY] FBX  $char  $fileName  =>  $newName"
                } else {
                    Rename-Item $f.FullName -NewName $newName
                    $manifest.parts.$partKey.file = $newRelPath
                    $changed = $true
                    $totalFbx++
                    Write-Host "FBX  $char  $fileName  =>  $newName"
                    $dest = Join-Path $bulkDir $newName
                    if (-not (Test-Path $dest)) { Copy-Item $newAbsPath $dest }
                }
            }
        }

        # ── Rename / copy PNG textures ────────────────────────────────────────
        if ($manifest.textures) {
            foreach ($texKey in $manifest.textures.PSObject.Properties.Name) {
                $relPath = $manifest.textures.$texKey   # e.g. "textures\Body_Diffuse.png"
                $absPath = Join-Path $mDir $relPath
                if (-not (Test-Path $absPath)) {
                    Write-Warning "  Missing PNG: $absPath"
                    continue
                }

                $f        = Get-Item $absPath
                $subDir   = Split-Path $relPath -Parent   # e.g. "textures"
                $fileName = $f.Name                       # e.g. "Body_Diffuse.png"

                # Already prefixed?
                if ($f.BaseName -like "$char*") {
                    if (-not $DryRun) {
                        $dest = Join-Path $bulkDir $f.Name
                        if (-not (Test-Path $dest)) { Copy-Item $f.FullName $dest }
                    }
                    continue
                }

                $newName    = "${char}_${fileName}"
                $newAbsPath = Join-Path $f.DirectoryName $newName
                $newRelPath = if ($subDir -eq "") { $newName } else { "${subDir}\${newName}" }

                if ($DryRun) {
                    Write-Host "[DRY] PNG  $char  $fileName  =>  $newName"
                } else {
                    Rename-Item $f.FullName -NewName $newName
                    $manifest.textures.$texKey = $newRelPath
                    $changed = $true
                    $totalPng++
                    Write-Host "PNG  $char  $fileName  =>  $newName"
                    $dest = Join-Path $bulkDir $newName
                    if (-not (Test-Path $dest)) { Copy-Item $newAbsPath $dest }
                }
            }
        }

        # ── Save updated manifest ─────────────────────────────────────────────
        if ($changed -and -not $DryRun) {
            $manifest | ConvertTo-Json -Depth 5 | Set-Content $manifestFile.FullName -Encoding UTF8
        }
    }
}

Write-Host ""
if ($DryRun) {
    Write-Host "[DRY RUN] No files were changed."
} else {
    Write-Host "Done.  Renamed FBX: $totalFbx   PNG: $totalPng"
    Write-Host "BulkImport folder: $bulkDir"
    Write-Host ""
    Write-Host "Next step: run  python tools/gen_manifests_lua.py  to regenerate GIManifests.lua"
}
