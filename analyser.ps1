# Analyse du PC — LECTURE SEULE : ce script ne supprime, ne déplace et ne modifie aucun fichier.
# Il écrit seulement son rapport dans analyse-pc\inventaire.js (à côté de ce script).
# OneDrive, Windows, Program Files et les dossiers de jeux ne sont pas fouillés fichier par fichier.
$ErrorActionPreference = 'SilentlyContinue'
$out = Join-Path $PSScriptRoot 'inventaire.js'
$home2 = $env:USERPROFILE
$exclus = 'OneDrive|\\AppData\\|\\Windows\\|Program Files|\$RECYCLE\.BIN|System Volume Information|WindowsApps|SteamLibrary|Epic Games|Riot Games|XboxGames|\\Recovery\\|\\\.'

$racines = @()
Get-ChildItem $home2 -Directory | Where-Object { $_.FullName -notmatch $exclus -and $_.Name -notmatch '^(AppData|OneDrive)' } | ForEach-Object { $racines += $_.FullName }
Get-PSDrive -PSProvider FileSystem | Where-Object { $_.Root -ne 'C:\' -and $_.Used -gt 0 } | ForEach-Object {
  Get-ChildItem $_.Root -Directory | Where-Object { $_.FullName -notmatch $exclus } | ForEach-Object { $racines += $_.FullName }
}

Write-Host "Lecture des dossiers (ça peut prendre quelques minutes)..." -ForegroundColor Cyan
$tous = foreach($r in $racines){ Get-ChildItem $r -File -Recurse -Force | Where-Object { $_.FullName -notmatch $exclus } }
Write-Host ("{0} fichiers trouvés." -f $tous.Count)

$ilya2ans = (Get-Date).AddYears(-2)
$dossiers = $racines | ForEach-Object {
  $r = $_; $f = $tous | Where-Object { $_.FullName.StartsWith($r + '\') }
  [pscustomobject]@{ n = $r; t = [int64](($f | Measure-Object Length -Sum).Sum); c = @($f).Count }
} | Sort-Object t -Descending

$gros = $tous | Sort-Object Length -Descending | Select-Object -First 80 | ForEach-Object {
  [pscustomobject]@{ n = $_.FullName; t = $_.Length; d = $_.LastWriteTime.ToString('dd/MM/yyyy') } }

$vieux = $tous | Where-Object { $_.LastWriteTime -lt $ilya2ans -and $_.Length -gt 5MB } | Sort-Object Length -Descending | Select-Object -First 80 | ForEach-Object {
  [pscustomobject]@{ n = $_.FullName; t = $_.Length; d = $_.LastWriteTime.ToString('dd/MM/yyyy') } }

$install = $tous | Where-Object { $_.Extension -match '^\.(exe|msi)$' -and $_.DirectoryName -match 'Downloads|Téléchargements' } | Sort-Object Length -Descending | ForEach-Object {
  [pscustomobject]@{ n = $_.FullName; t = $_.Length; d = $_.LastWriteTime.ToString('dd/MM/yyyy') } }

# Doublons exacts : même taille, puis même empreinte (hash). Seulement les fichiers de plus de 1 Mo.
Write-Host "Recherche des doublons exacts..." -ForegroundColor Cyan
$doublons = $tous | Where-Object { $_.Length -gt 1MB } | Group-Object Length | Where-Object Count -gt 1 | ForEach-Object {
  $_.Group | ForEach-Object { [pscustomobject]@{ f = $_; h = (Get-FileHash $_.FullName -Algorithm MD5).Hash } } | Group-Object h | Where-Object Count -gt 1 | ForEach-Object {
    $l = $_.Group.f | Sort-Object LastWriteTime
    [pscustomobject]@{ garder = $l[0].FullName; copies = @($l | Select-Object -Skip 1 | ForEach-Object FullName); taille = $l[0].Length; gain = $l[0].Length * ($l.Count - 1) }
  }
} | Sort-Object gain -Descending | Select-Object -First 150

# Photos et vidéos : regroupées par dossier et par année
$medias = $tous | Where-Object { $_.Extension -match '^\.(jpe?g|png|heic|gif|webp|mp4|mov|mkv|avi)$' } | Group-Object { $_.DirectoryName } | ForEach-Object {
  [pscustomobject]@{ n = $_.Name; c = $_.Count; t = [int64](($_.Group | Measure-Object Length -Sum).Sum)
    ans = (($_.Group | Group-Object { $_.LastWriteTime.Year } | Sort-Object Name | ForEach-Object { "$($_.Name): $($_.Count)" }) -join ', ') }
} | Sort-Object t -Descending | Select-Object -First 60

# Applications installées (lues dans le registre, rien n'est désinstallé)
$cles = 'HKLM:\Software\Microsoft\Windows\CurrentVersion\Uninstall\*','HKLM:\Software\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall\*','HKCU:\Software\Microsoft\Windows\CurrentVersion\Uninstall\*'
$apps = Get-ItemProperty $cles | Where-Object { $_.DisplayName -and -not $_.SystemComponent } | Sort-Object DisplayName -Unique | ForEach-Object {
  [pscustomobject]@{ n = $_.DisplayName; v = "$($_.DisplayVersion)"; e = "$($_.Publisher)"; t = [int64]($_.EstimatedSize) * 1KB; d = "$($_.InstallDate)" } }

$disques = Get-PSDrive -PSProvider FileSystem | Where-Object Used | ForEach-Object { [pscustomobject]@{ n = $_.Root; libre = [int64]$_.Free; utilise = [int64]$_.Used } }

$r = [pscustomobject]@{ date = (Get-Date).ToString('dd/MM/yyyy HH:mm'); nb = $tous.Count; disques = $disques; dossiers = $dossiers
  gros = $gros; vieux = $vieux; installeurs = $install; doublons = $doublons; medias = $medias; apps = $apps }
'window.INVENTAIRE = ' + ($r | ConvertTo-Json -Depth 5 -Compress) + ';' | Out-File $out -Encoding utf8
Write-Host "Terminé. Rapport écrit dans $out" -ForegroundColor Green
