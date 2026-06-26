# refresh.ps1 — one-command update of the Ultimate World Champion site.
#
# 1. Pull the latest ATP match data from Jeff Sackmann's GitHub (incremental).
# 2. Re-run tennis.R to regenerate the five output CSVs.
# 3. Commit and push the updated CSVs so the live GitHub Pages site refreshes.
#
# Usage:   ./refresh.ps1                      # pull data, rebuild, commit & push
#          ./refresh.ps1 -NoPush              # pull data, rebuild only (no git push)
#          ./refresh.ps1 -SourceUrl <url>     # use an alternative data repo
#
# NOTE: As of June 2026 the original source, https://github.com/JeffSackmann/tennis_atp,
#       returns 404 (made private / removed / relocated). Pass a working clone URL via
#       -SourceUrl, or update the default below, once a live source is known.

param(
  [switch]$NoPush,
  [string]$SourceUrl = "https://github.com/JeffSackmann/tennis_atp.git"
)

$ErrorActionPreference = "Stop"
$projectDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$dataDir    = Join-Path $projectDir "tennis_atp"
$upstream   = $SourceUrl

# Locate Rscript (newest installed R version).
$rscript = (Get-Command Rscript -ErrorAction SilentlyContinue).Source
if (-not $rscript) {
  $rdir = Get-ChildItem "C:\Program Files\R" -Directory -ErrorAction SilentlyContinue |
          Sort-Object Name -Descending | Select-Object -First 1
  if ($rdir) { $rscript = Join-Path $rdir.FullName "bin\Rscript.exe" }
}
if (-not $rscript -or -not (Test-Path $rscript)) {
  throw "Rscript not found. Install R or add Rscript to PATH."
}

# 1. Pull (or clone) Sackmann's data.
if (Test-Path (Join-Path $dataDir ".git")) {
  Write-Host "Pulling latest ATP data..." -ForegroundColor Cyan
  git -C $dataDir pull --ff-only
} else {
  Write-Host "Cloning Sackmann ATP data (first run, this is the slow one)..." -ForegroundColor Cyan
  git clone --depth 1 $upstream $dataDir
}

# 2. Regenerate the CSVs.
Write-Host "Running tennis.R..." -ForegroundColor Cyan
& $rscript (Join-Path $projectDir "tennis.R")

# 3. Commit & push the refreshed outputs.
if ($NoPush) {
  Write-Host "Done (outputs rebuilt; skipped git push)." -ForegroundColor Green
  return
}

Push-Location $projectDir
try {
  git add *.csv
  $changes = git status --porcelain -- *.csv
  if ($changes) {
    $stamp = Get-Date -Format "yyyy-MM-dd"
    git commit -m "Refresh outputs with latest ATP data ($stamp)"
    git push
    Write-Host "Pushed updated CSVs. GitHub Pages will refresh shortly." -ForegroundColor Green
  } else {
    Write-Host "No CSV changes — already up to date." -ForegroundColor Green
  }
} finally {
  Pop-Location
}
