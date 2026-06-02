# Script de recherche de fichiers verrouillés pour Windows (sans compilation C#)

$TargetDir = Join-Path (Split-Path -Parent $MyInvocation.MyCommand.Definition) "frontend\build"

if (-not (Test-Path $TargetDir)) {
    Write-Host "Le dossier build n'existe pas : $TargetDir" -ForegroundColor Yellow
    exit
}

Write-Host "Recherche de verrous dans $TargetDir (via ouverture exclusive)..." -ForegroundColor Cyan

$files = Get-ChildItem -Path $TargetDir -Recurse -File -ErrorAction SilentlyContinue
$lockedCount = 0

foreach ($file in $files) {
    $path = $file.FullName
    $locked = $false
    try {
        # Tenter une ouverture exclusive. Échoue si un autre processus détient un verrou.
        $stream = [System.IO.File]::Open($path, [System.IO.FileMode]::Open, [System.IO.FileAccess]::ReadWrite, [System.IO.FileShare]::None)
        $stream.Close()
    } catch {
        $locked = $true
    }

    if ($locked) {
        Write-Host "Fichier verrouillé : $path" -ForegroundColor Yellow
        $lockedCount++
        
        # Chercher via tasklist avec le nom du fichier
        $name = $file.Name
        $taskOutput = tasklist /m $name 2>&1 | Out-String
        if ($taskOutput -match "\.exe") {
            Write-Host "  -> Processus détecté par tasklist :" -ForegroundColor Red
            Write-Host $taskOutput.Trim() -ForegroundColor Red
        } else {
            Write-Host "  -> Impossible de déterminer le processus (souvent un verrou d'éditeur type VS Code, de compilation ou d'antivirus)." -ForegroundColor Cyan
        }
    }
}

if ($lockedCount -eq 0) {
    Write-Host "Aucun fichier verrouillé détecté dans le dossier 'build'." -ForegroundColor Green
} else {
    Write-Host "`nTotal de fichiers verrouillés : $lockedCount" -ForegroundColor Orange
}
