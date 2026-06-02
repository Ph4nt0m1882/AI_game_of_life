# Script de réinitialisation Flutter pour Windows
# Force le nettoyage des processus verrouillant les fichiers de compilation

Write-Host "=== Nettoyage des processus en cours ===" -ForegroundColor Cyan

# Ajout de 'frontend' pour tuer l'application elle-même si elle tourne en arrière-plan
$processNames = @("dart", "flutter", "msbuild", "cl", "link", "ninja", "cmake", "frontend")
foreach ($name in $processNames) {
    $procs = Get-Process -Name $name -ErrorAction SilentlyContinue
    if ($procs) {
        Write-Host "Arrêt de $name..." -ForegroundColor Yellow
        Stop-Process -Name $name -Force -ErrorAction SilentlyContinue
    }
}

# Attendre un court instant que les processus se terminent
Start-Sleep -Milliseconds 500

# Trouver le sous-dossier frontend
$scriptDir = Split-Path -Parent $MyInvocation.MyCommand.Definition
if ($scriptDir -eq $null -or $scriptDir -eq "") {
    $scriptDir = Get-Location
}

$frontendDir = Join-Path $scriptDir "frontend"

if (Test-Path $frontendDir) {
    Write-Host "Navigation vers $frontendDir" -ForegroundColor Cyan
    Push-Location $frontendDir

    Write-Host "Exécution de 'flutter clean'..." -ForegroundColor Cyan
    flutter clean

    # Essayer de forcer la suppression du dossier build si flutter clean a laissé des résidus
    $buildDir = Join-Path $frontendDir "build"
    if (Test-Path $buildDir) {
        Write-Host "Le dossier 'build' existe toujours, tentative de suppression forcée..." -ForegroundColor Yellow
        try {
            Remove-Item -Recurse -Force $buildDir -ErrorAction Stop
            Write-Host "Dossier 'build' supprimé avec succès." -ForegroundColor Green
        } catch {
            Write-Host "Impossible de supprimer le dossier 'build' : $_" -ForegroundColor Red
            Write-Host "Veuillez vérifier qu'aucun autre éditeur ou outil n'est ouvert sur le projet." -ForegroundColor Yellow
        }
    }

    Write-Host "Exécution de 'flutter pub get'..." -ForegroundColor Cyan
    flutter pub get

    Pop-Location
    Write-Host "=== Réinitialisation terminée ! ===" -ForegroundColor Green
} else {
    Write-Host "Dossier 'frontend' introuvable à l'emplacement $frontendDir !" -ForegroundColor Red
}
