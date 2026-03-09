# run_batch_export.ps1
# ─────────────────────────────────────────────────────────────────────────────
# Batch-exports ~51 GI character FBX files via gi_to_roblox.py across all
# four pipeline modes so every pipeline path is exercised before Studio import.
#
# SELECTION (51 exports):
#   npc   / mob      (20) -- horde enemies, 2 000-face merged mesh
#   npc   / boss     ( 5) -- solo bosses,   9 000-face merged mesh
#   r6    / player   ( 8) -- player costumes, 6 R6 parts each, 6 000 faces total
#   head_only / player ( 9) -- character-creation head catalog
#   body_only / player ( 9) -- character-creation body/costume catalog
#
# OUTPUT: C:\Users\P_Guilleminot\Desktop\Developer\RobloxAssets\<char>\<mode>\
#
# USAGE:
#   .\tools\run_batch_export.ps1
#   .\tools\run_batch_export.ps1 -DryRun
#   .\tools\run_batch_export.ps1 -Resume          # skip already-exported
# ─────────────────────────────────────────────────────────────────────────────
param(
    [switch] $DryRun,                  # Print what would run, don't execute Blender
    [switch] $Resume,                  # Skip entries whose manifest.json already exists

    [string] $GIAssetsDir = "C:\Users\P_Guilleminot\Desktop\Developer\GIAssets\Models\Characters",
    [string] $OutBaseDir  = "C:\Users\P_Guilleminot\Desktop\Developer\RobloxAssets",
    [string] $BlenderExe  = "C:\Program Files\Blender Foundation\Blender 5.0\blender.exe",
    [string] $ScriptPath  = "$PSScriptRoot\gi_to_roblox.py"
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Continue"

# ── Export list -- [CharacterName, Mode, Target] ───────────────────────────────
# Each entry becomes one Blender run and one manifest.json.
$exports = @(

    # ── NPC / MOB  (20 entries) ─────────────────────────────────────────────
    # Small/medium characters that work well as generic horde mobs.
    # Merged to one draw-call mesh, decimated to 2 000 faces.

    @{ Char="Bennett";           Mode="npc"; Target="mob" },
    @{ Char="Chongyun";          Mode="npc"; Target="mob" },
    @{ Char="Collei";            Mode="npc"; Target="mob" },
    @{ Char="Diona";             Mode="npc"; Target="mob" },
    @{ Char="Dori";              Mode="npc"; Target="mob" },
    @{ Char="Faruzan";           Mode="npc"; Target="mob" },
    @{ Char="Gorou";             Mode="npc"; Target="mob" },
    @{ Char="Kachina";           Mode="npc"; Target="mob" },
    @{ Char="Layla";             Mode="npc"; Target="mob" },
    @{ Char="Linette";           Mode="npc"; Target="mob" },
    @{ Char="Mika";              Mode="npc"; Target="mob" },
    @{ Char="Noelle";            Mode="npc"; Target="mob" },
    @{ Char="Paimon";            Mode="npc"; Target="mob" },
    @{ Char="Qiqi";              Mode="npc"; Target="mob" },
    @{ Char="Razor";             Mode="npc"; Target="mob" },
    @{ Char="Sayu";              Mode="npc"; Target="mob" },
    @{ Char="Sucrose";           Mode="npc"; Target="mob" },
    @{ Char="Thoma";             Mode="npc"; Target="mob" },
    @{ Char="Xiangling";         Mode="npc"; Target="mob" },
    @{ Char="YaoYao";            Mode="npc"; Target="mob" },

    # ── NPC / BOSS  (5 entries) ─────────────────────────────────────────────
    # Bosses / villain NPCs -- 9 000-face merged mesh.

    @{ Char="Dvalin";            Mode="npc"; Target="boss" },
    @{ Char="Asmoday";           Mode="npc"; Target="boss" },
    @{ Char="IlCapitano";        Mode="npc"; Target="boss" },
    @{ Char="IlDotorre";         Mode="npc"; Target="boss" },
    @{ Char="La Signora";        Mode="npc"; Target="boss" },

    # ── R6 / PLAYER COSTUMES  (8 entries) ──────────────────────────────────
    # Split into 6 rigid limbs, 6 000 total faces.
    # Produces Head/Torso/LeftArm/RightArm/LeftLeg/RightLeg.fbx per character.

    @{ Char="Xiao";              Mode="r6"; Target="player" },
    @{ Char="Hu Tao";            Mode="r6"; Target="player" },
    @{ Char="Eula";              Mode="r6"; Target="player" },
    @{ Char="Arlecchino";        Mode="r6"; Target="player" },
    @{ Char="Zhongli";           Mode="r6"; Target="player" },
    @{ Char="Venti";             Mode="r6"; Target="player" },
    @{ Char="Raiden Shogun";     Mode="r6"; Target="player" },
    @{ Char="Skirk";             Mode="r6"; Target="player" },

    # ── HEAD ONLY  (9 entries) ──────────────────────────────────────────────
    # Character-creation head catalog -- bone-weighted head region +
    # Face / Face_Eye / Brow meshes merged. Budget 1 800 faces.

    @{ Char="Lumine";            Mode="head_only"; Target="player" },
    @{ Char="Aether";            Mode="head_only"; Target="player" },
    @{ Char="Kujou Sara";        Mode="head_only"; Target="player" },
    @{ Char="Yae Miko";          Mode="head_only"; Target="player" },
    @{ Char="Nahida";            Mode="head_only"; Target="player" },
    @{ Char="Wanderer";          Mode="head_only"; Target="player" },
    @{ Char="Mavuika";           Mode="head_only"; Target="player" },
    @{ Char="Neuvillette";       Mode="head_only"; Target="player" },
    @{ Char="Clorinde";          Mode="head_only"; Target="player" },

    # ── BODY ONLY  (9 entries) ──────────────────────────────────────────────
    # Character-creation body / costume catalog -- Torso + 4 limbs (no Head).
    # Budget 4 200 faces across 5 parts.

    @{ Char="Xiao";              Mode="body_only"; Target="player" },
    @{ Char="Hu Tao";            Mode="body_only"; Target="player" },
    @{ Char="Eula";              Mode="body_only"; Target="player" },
    @{ Char="Zhongli";           Mode="body_only"; Target="player" },
    @{ Char="Venti";             Mode="body_only"; Target="player" },
    @{ Char="Mavuika";           Mode="body_only"; Target="player" },
    @{ Char="Childe";            Mode="body_only"; Target="player" },
    @{ Char="Cyno";              Mode="body_only"; Target="player" },
    @{ Char="Wriothesley";       Mode="body_only"; Target="player" }
)

# ── Validate tooling ──────────────────────────────────────────────────────────
if (-not (Test-Path $BlenderExe)) { Write-Error "Blender not found: $BlenderExe"; exit 1 }
if (-not (Test-Path $ScriptPath)) { Write-Error "Script not found: $ScriptPath";  exit 1 }
New-Item -ItemType Directory -Force -Path $OutBaseDir | Out-Null

$total   = $exports.Count
$success = 0
$skipped = 0
$failed  = [System.Collections.Generic.List[string]]::new()
$startAll = Get-Date

Write-Host ""
Write-Host ("═" * 65) -ForegroundColor Cyan
Write-Host "  GI Assets Batch Export  --  $total jobs" -ForegroundColor Cyan
$modeStr = if ($DryRun) { "DRY RUN" } elseif ($Resume) { "RESUME" } else { "FULL" }
Write-Host "  Mode: $modeStr   Output: $OutBaseDir" -ForegroundColor Cyan
Write-Host ("═" * 65) -ForegroundColor Cyan
Write-Host ""

$i = 0
foreach ($entry in $exports) {
    $i++
    $char   = $entry.Char
    $mode   = $entry.Mode
    $target = $entry.Target
    $label  = "[$i/$total] $char  ($mode / $target)"

    # ── Path setup ─────────────────────────────────────────────────────────
    $charDir  = Join-Path $GIAssetsDir $char
    $outDir   = Join-Path $OutBaseDir  "$char\$mode"
    $manifest = Join-Path $outDir "manifest.json"

    if (-not (Test-Path $charDir)) {
        Write-Warning "$label  -> character folder missing, skipping"
        $failed.Add("$char ($mode/$target) -- folder missing")
        continue
    }
    $fbxFiles = Get-ChildItem -Path $charDir -Filter "*.fbx" -EA SilentlyContinue
    if (-not $fbxFiles) {
        Write-Warning "$label  -> no FBX found, skipping"
        $failed.Add("$char ($mode/$target) -- no FBX")
        continue
    }

    # ── Resume check ───────────────────────────────────────────────────────
    if ($Resume -and (Test-Path $manifest)) {
        Write-Host "  SKIP  $label  (manifest exists)" -ForegroundColor DarkGray
        $skipped++
        continue
    }

    Write-Host "► $label" -ForegroundColor Yellow
    if ($DryRun) {
        Write-Host "  char_dir : $charDir"
        Write-Host "  out_dir  : $outDir"
        $success++
        continue
    }

    New-Item -ItemType Directory -Force -Path $outDir | Out-Null
    $startJob = Get-Date

    $blenderArgs = @(
        "--background",
        "--python", $ScriptPath,
        "--",
        "--char_dir", $charDir,
        "--out_dir",  $outDir,
        "--mode",     $mode,
        "--target",   $target,
        "--lod",      "0"
    )

    $result = & $BlenderExe @blenderArgs 2>&1

    # Filter output to relevant lines
    $result | Where-Object { $_ -match "\[gi_to_roblox\]|ERROR|error:|Traceback|Warning" } |
        ForEach-Object { Write-Host "    $_" -ForegroundColor Gray }

    $elapsed = [math]::Round(((Get-Date) - $startJob).TotalSeconds, 1)

    # Success = manifest.json exists (Blender sometimes exits 1 due to deprecation warnings)
    if (Test-Path $manifest) {
        # Parse face counts from manifest for a quick summary
        try {
            $m = Get-Content $manifest | ConvertFrom-Json
            $partCount  = ($m.parts.PSObject.Properties | Measure-Object).Count
            $totalFaces = ($m.parts.PSObject.Properties.Value | ForEach-Object { $_.faces } | Measure-Object -Sum).Sum
            Write-Host "  ✓  $elapsed s  --  $partCount part(s), $totalFaces faces total  ->  $outDir" -ForegroundColor Green
        } catch {
            Write-Host "  ✓  $elapsed s  ->  $outDir" -ForegroundColor Green
        }
        $success++
    } else {
        Write-Host "  ✗  Failed (exit $LASTEXITCODE, ${elapsed}s)  ->  $outDir" -ForegroundColor Red
        $failed.Add("$char ($mode/$target)")
    }
    Write-Host ""
}

# ── Summary ────────────────────────────────────────────────────────────────────
$totalTime = [math]::Round(((Get-Date) - $startAll).TotalMinutes, 1)

Write-Host ""
Write-Host ("═" * 65) -ForegroundColor Cyan
Write-Host "  DONE in ${totalTime} min  --  $success/$total OK   $skipped skipped   $($failed.Count) failed" -ForegroundColor Cyan
Write-Host ("═" * 65) -ForegroundColor Cyan

if ($failed.Count -gt 0) {
    Write-Host ""
    Write-Host "Failed exports:" -ForegroundColor Red
    $failed | ForEach-Object { Write-Host "  - $_" -ForegroundColor Red }
}

Write-Host ""
Write-Host "Output directory: $OutBaseDir" -ForegroundColor White
Write-Host "Next step: import FBX files into Roblox Studio, then File > Export Selection as .rbxmx" -ForegroundColor DarkCyan
