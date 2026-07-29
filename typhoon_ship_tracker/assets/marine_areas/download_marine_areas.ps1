# Downloads all 48 JMA local marine forecast area boundary GeoJSON files
# from NII Geoshape into this folder.
#
# Source: https://geoshape.ex.nii.ac.jp/jma/resource/AreaMarineAJ/
# License: CC BY 4.0. Attribution when used:
#   NII "Japan Meteorological Agency Disaster Prevention Information
#   Announcement Area Dataset", processed from JMA "GIS data"
#
# Usage (PowerShell, from this folder):
#   .\download_marine_areas.ps1

$ErrorActionPreference = "Stop"

$codes = @(
    "1000","1010","1020","1030","1040","1050","1100","1110","1120","1130","1140","1150",
    "2000","2010","2020",
    "3000","3010","3020","3100","3110","3120","3130","3140","3200","3210","3220","3230",
    "4000","4010","4020","4030","4100","4110","4120","4130",
    "5000","5100","5110","5120","5130","5200","5210","5220","5230",
    "6000","6010","6020","6030"
)

$baseUrl = "https://geoshape.ex.nii.ac.jp/jma/resource/AreaMarineAJ/20190125"
$scriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path

$total = $codes.Count
$done = 0
$failed = @()

foreach ($code in $codes) {
    $url = "$baseUrl/$code.geojson"
    $outFile = Join-Path $scriptDir "$code.geojson"
    try {
        Invoke-WebRequest -Uri $url -OutFile $outFile -UseBasicParsing
        $done++
        Write-Host "OK  ($done/$total): $code.geojson"
    } catch {
        $failed += $code
        Write-Host "FAIL      : $code -> $($_.Exception.Message)"
    }
}

Write-Host ""
Write-Host "Done. $done of $total files downloaded to $scriptDir"
if ($failed.Count -gt 0) {
    Write-Host "Failed codes: $($failed -join ', ')"
    Write-Host "Re-run this script to retry failed codes (existing files are simply overwritten)."
}
