param([string]$File)

$content = [System.IO.File]::ReadAllText($File)
$ok = 0

# Rotation matrices (clean, no floating-point noise)
$rotRightY = "						<R00>0</R00>`n						<R01>0</R01>`n						<R02>1</R02>`n						<R10>0</R10>`n						<R11>1</R11>`n						<R12>0</R12>`n						<R20>-1</R20>`n						<R21>0</R21>`n						<R22>0</R22>`n"
$rotLeftY  = "						<R00>0</R00>`n						<R01>0</R01>`n						<R02>-1</R02>`n						<R10>0</R10>`n						<R11>1</R11>`n						<R12>0</R12>`n						<R20>1</R20>`n						<R21>0</R21>`n						<R22>0</R22>`n"
$rotNeck   = "						<R00>-1</R00>`n						<R01>0</R01>`n						<R02>0</R02>`n						<R10>0</R10>`n						<R11>0</R11>`n						<R12>1</R12>`n						<R20>0</R20>`n						<R21>1</R21>`n						<R22>0</R22>`n"
$rotRoot   = "						<R00>-1</R00>`n						<R01>0</R01>`n						<R02>0</R02>`n						<R10>0</R10>`n						<R11>0</R11>`n						<R12>1</R12>`n						<R20>0</R20>`n						<R21>1</R21>`n						<R22>0</R22>`n"

function Fix-Joint {
    param([string]$c0x, [string]$c0y, [string]$c0z,
          [string]$c1x, [string]$c1y, [string]$c1z,
          [string]$newRot, [string]$label)

    # Build search: identity rotation in both C0 and C1 (LF line endings)
    $idRot = "						<R00>1</R00>`n						<R01>0</R01>`n						<R02>0</R02>`n						<R10>0</R10>`n						<R11>1</R11>`n						<R12>-0</R12>`n						<R20>0</R20>`n						<R21>0</R21>`n						<R22>1</R22>`n"

    $old = "					<CoordinateFrame name=`"C0`">`n						<X>$c0x</X>`n						<Y>$c0y</Y>`n						<Z>$c0z</Z>`n$idRot					</CoordinateFrame>`n					<CoordinateFrame name=`"C1`">`n						<X>$c1x</X>`n						<Y>$c1y</Y>`n						<Z>$c1z</Z>`n$idRot					</CoordinateFrame>"

    $new = "					<CoordinateFrame name=`"C0`">`n						<X>$c0x</X>`n						<Y>$c0y</Y>`n						<Z>$c0z</Z>`n$newRot					</CoordinateFrame>`n					<CoordinateFrame name=`"C1`">`n						<X>$c1x</X>`n						<Y>$c1y</Y>`n						<Z>$c1z</Z>`n$newRot					</CoordinateFrame>"

    if ($script:content.Contains($old)) {
        $script:content = $script:content.Replace($old, $new)
        Write-Host "  $label : OK"
        $script:ok++
    } else {
        Write-Host "  $label : NOT FOUND"
    }
}

# ── 5 joints ──────────────────────────────────────────────────────────────────
Fix-Joint "0.5"          "0.899999976"  "0.200000003"  "-1"           "0.899999976"  "0.200000003"  $rotRightY "Right Shoulder"
Fix-Joint "-0.5"         "0.899999976"  "0.200000003"  "1"            "0.899999976"  "0.200000003"  $rotLeftY  "Left Shoulder"
Fix-Joint "0.300000012"  "-0.600000024" "0"            "-0.200000003" "1.39999998"   "0"            $rotRightY "Right Hip"
Fix-Joint "-0.300000012" "-0.600000024" "0"            "0.200000003"  "1.39999998"   "0"            $rotLeftY  "Left Hip"
Fix-Joint "0"            "1"            "0.200000003"  "0"            "-0.600000024" "0.200000003"  $rotNeck   "Neck"

if ($ok -gt 0) {
    [System.IO.File]::WriteAllText($File, $content)
    Write-Host "Saved $ok joint(s) in $File"
} else {
    Write-Host "Nothing changed in $File"
}
