# Checks the exported exe's Windows face (05-03, D-09/D-10) before it ships:
#   - VersionInfo FileVersion and ProductVersion equal project.godot config/version + ".0" (0.7.0 -> 0.7.0.0)
#     and ProductName is UNDERTOW;
#   - the embedded icon is not Godot's (compared against the 4.7.2 debug export template's icon);
#   - with -Selftest, the exe prints BUNDLED_OK 20 with exit 0 (same pattern as dist.ps1).
# Usage: powershell -NoProfile -File tools/check_exe.ps1 [-Exe build/UNDERTOW.exe] [-Selftest] [-SkipIcon]
# Called by tools/dist.ps1 right after the export; a non-zero exit fails the build. A missing export
# template fails too (the icon check never passes silently).
param(
    [string]$Exe = "build/UNDERTOW.exe",
    [switch]$Selftest,
    [switch]$SkipIcon
)
$ErrorActionPreference = "Stop"
$root = Split-Path -Parent $PSScriptRoot
if (-not [System.IO.Path]::IsPathRooted($Exe)) { $Exe = Join-Path $root $Exe }
if (-not (Test-Path -LiteralPath $Exe)) { Write-Error "Exe not found: $Exe"; exit 1 }
$Exe = (Resolve-Path -LiteralPath $Exe).Path
# Past MAX_PATH, ExtractAssociatedIcon silently returns a generic shell icon (which would "differ" from
# Godot's and pass) and Start-Process rejects the working directory. Refuse instead of guessing.
if ($Exe.Length -ge 248) {
    Write-Error ("Exe path is {0} chars (limit 247); icon and selftest checks are unreliable there. Use a shorter path: {1}" -f $Exe.Length, $Exe)
    exit 1
}

# 1. Expected version from project.godot (same regex as dist.ps1).
$projectFile = Join-Path $root "project.godot"
if (-not (Test-Path $projectFile)) { Write-Error "project.godot not found at $projectFile"; exit 1 }
$verMatch = Select-String -Path $projectFile -Pattern 'config/version="([^"]+)"' | Select-Object -First 1
if (-not $verMatch) { Write-Error 'project.godot has no config/version="x.y.z" line'; exit 1 }
$ver = $verMatch.Matches[0].Groups[1].Value
$expected = "$ver.0"

# "0, 7, 0, 0" / "0.7.0" / "0.7.0.0" -> "0.7.0.0"
function Normalize-Version([string]$v) {
    if ($null -eq $v) { return "" }
    $parts = @($v -split '[.,\s]+' | ForEach-Object { $_.Trim() } | Where-Object { $_ -ne "" })
    while ($parts.Count -lt 4) { $parts += "0" }
    return ($parts -join ".")
}

# 2. Version info.
$info = (Get-Item -LiteralPath $Exe).VersionInfo
$fileVer = Normalize-Version $info.FileVersion
$prodVer = Normalize-Version $info.ProductVersion
$bad = @()
if ($fileVer -ne $expected) { $bad += "FileVersion '$($info.FileVersion)' (expected $expected)" }
if ($prodVer -ne $expected) { $bad += "ProductVersion '$($info.ProductVersion)' (expected $expected)" }
if ($info.ProductName -ne "UNDERTOW") { $bad += "ProductName '$($info.ProductName)' (expected UNDERTOW)" }
if ($bad.Count -gt 0) {
    Write-Error ("Exe version info mismatch in {0}: {1}" -f $Exe, ($bad -join "; "))
    exit 1
}
Write-Host "EXE VERSION OK $ver (FileVersion $fileVer, ProductVersion $prodVer, ProductName $($info.ProductName))"

# 3. Icon must differ from the Godot template's icon.
function Get-IconHash([string]$path) {
    $icon = [System.Drawing.Icon]::ExtractAssociatedIcon($path)
    if ($null -eq $icon) { throw "no icon in $path" }
    $bmp = $icon.ToBitmap()
    $ms = New-Object System.IO.MemoryStream
    try {
        $bmp.Save($ms, [System.Drawing.Imaging.ImageFormat]::Png)
        $sha = [System.Security.Cryptography.SHA256]::Create()
        return ([System.BitConverter]::ToString($sha.ComputeHash($ms.ToArray())) -replace '-', '').ToLowerInvariant()
    }
    finally {
        $ms.Dispose(); $bmp.Dispose(); $icon.Dispose()
    }
}
if (-not $SkipIcon) {
    Add-Type -AssemblyName System.Drawing
    $template = Join-Path $env:APPDATA "Godot/export_templates/4.7.2.stable/windows_debug_x86_64.exe"
    if (-not (Test-Path -LiteralPath $template)) {
        Write-Error "Godot export template not found at $template; cannot prove the exe icon is not Godot's"
        exit 1
    }
    $exeHash = Get-IconHash $Exe
    $tplHash = Get-IconHash $template
    Write-Host "  exe icon sha256:      $exeHash"
    Write-Host "  template icon sha256: $tplHash"
    if ($exeHash -eq $tplHash) {
        Write-Error "Exe still carries the Godot icon (icon hash equals the export template's)"
        exit 1
    }
    Write-Host "EXE ICON OK"
}

# 4. Optional bundled-content selftest (dist.ps1 pattern).
if ($Selftest) {
    $tmp = Join-Path ([System.IO.Path]::GetTempPath()) ("undertow_check_exe_" + [guid]::NewGuid().ToString("N"))
    New-Item -ItemType Directory -Force -Path $tmp | Out-Null
    $outFile = Join-Path $tmp "selftest.out.txt"
    $errFile = Join-Path $tmp "selftest.err.txt"
    try {
        $p = Start-Process -FilePath $Exe -ArgumentList @("--headless", "--", "--selftest-bundled") `
            -WorkingDirectory (Split-Path -Parent $Exe) -RedirectStandardOutput $outFile -RedirectStandardError $errFile `
            -PassThru -NoNewWindow
        $null = $p.Handle  # cache the handle so ExitCode survives WaitForExit
        if (-not $p.WaitForExit(120000)) {
            try { $p.Kill() } catch { }
            Write-Error "Selftest timed out after 120 s"; exit 1
        }
        $p.WaitForExit()
        $out = ""
        if (Test-Path $outFile) { $out = (Get-Content $outFile -Raw) }
        if ($null -eq $out) { $out = "" }
        $line = ($out -split "`r?`n" | Where-Object { $_ -match "BUNDLED_OK" } | Select-Object -First 1)
        if ($p.ExitCode -ne 0 -or $out -notmatch "BUNDLED_OK 20") {
            Write-Error ("Selftest did not print BUNDLED_OK 20 with exit 0 (exit {0}; output: {1})" -f $p.ExitCode, $out.Trim())
            exit 1
        }
        Write-Host $line.Trim()
    }
    finally {
        Remove-Item -LiteralPath $tmp -Recurse -Force -ErrorAction SilentlyContinue
    }
}

Write-Host "EXE CHECK OK"
exit 0
