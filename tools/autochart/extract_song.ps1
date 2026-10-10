# UNDERTOW player flow (STEM-02/04/05): turn an audio file you own into separated stems plus a
# ready-to-play song folder in your UNDERTOW Songs folder. Wraps `autochart.py extract`.
#
#   powershell -NoProfile -File tools/autochart/extract_song.ps1 -Audio "C:\Music\song.mp3" -Name "My Song" -Artist "Me"
#   powershell -NoProfile -File tools/autochart/extract_song.ps1 -Audio "C:\Music\song.mp3" -Mode lanes
#
# -Mode single (default): one instrument (-Stem other|drums|bass|vocals) over the 4 lanes.
# -Mode lanes: INSTRUMENT LANES, each lane is one instrument (bass, drums, other, vocals, left to right).
# -SongsRoot: Songs folder (default %APPDATA%\Godot\app_userdata\UNDERTOW\songs).
# -Force: replace an existing song folder of the same name.
# Needs build/autochart/venvA (run tools/autochart/setup_venv.ps1 once). Only .mp3, .ogg and .wav play in the game.
param(
    [Parameter(Mandatory = $true)][string]$Audio,
    [string]$Name,
    [string]$Artist = "Unknown",
    [ValidateSet("single", "lanes")][string]$Mode = "single",
    [ValidateSet("other", "drums", "bass", "vocals")][string]$Stem = "other",
    [string]$SongsRoot,
    [switch]$Force
)

$root = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
$python = Join-Path $root "build/autochart/venvA/Scripts/python.exe"
if (-not (Test-Path $python)) {
    Write-Host "Run tools/autochart/setup_venv.ps1 first"
    exit 2
}
$script = Join-Path $PSScriptRoot "autochart.py"

$argv = @("-I", "-B", $script, "extract", "--src", $Audio, "--artist", $Artist, "--mode", $Mode, "--stem", $Stem)
if ($Name) { $argv += @("--name", $Name) }
if ($SongsRoot) { $argv += @("--songs-root", $SongsRoot) }
if ($Force) { $argv += "--force" }

# Relative -Audio / -SongsRoot paths resolve against the caller's current folder.
& $python @argv
exit $LASTEXITCODE
