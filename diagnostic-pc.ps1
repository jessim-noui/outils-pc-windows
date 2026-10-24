# Diagnostic PC — LECTURE SEULE : rien n'est supprimé, déplacé, installé ni modifié.
# Cherche pourquoi un jeu (Valorant) se ferme : plantages, carte graphique, mémoire, Vanguard, IA locale qui occupe la carte.
# Écrit seulement un rapport texte à côté de ce script.
$ErrorActionPreference = 'SilentlyContinue'
$jours = 14
$depuis = (Get-Date).AddDays(-$jours)
$rapport = Join-Path $PSScriptRoot ("diagnostic-" + (Get-Date -Format 'yyyy-MM-dd_HHmm') + ".txt")
$L = New-Object System.Collections.Generic.List[string]
$alertes = New-Object System.Collections.Generic.List[string]
function T($t) { $L.Add(''); $L.Add("=== $t ==="); Write-Host "`n$t" -ForegroundColor Cyan }
function A($t) { $L.Add($t); Write-Host $t }

A ("Diagnostic du " + (Get-Date -Format 'dd/MM/yyyy HH:mm') + " — période : $jours derniers jours")

T "1. Le PC"
$os = Get-CimInstance Win32_OperatingSystem
$cpu = Get-CimInstance Win32_Processor | Select-Object -First 1
A ("Windows : " + $os.Caption + " (build " + $os.BuildNumber + ")")
A ("Allumé depuis : " + [math]::Round(((Get-Date) - $os.LastBootUpTime).TotalHours, 1) + " h")
A ("Processeur : " + $cpu.Name.Trim())
$ramTot = [math]::Round($os.TotalVisibleMemorySize / 1MB, 1); $ramLibre = [math]::Round($os.FreePhysicalMemory / 1MB, 1)
A ("Mémoire vive : $ramLibre Go libres sur $ramTot Go")
if ($ramLibre -lt 3) { $alertes.Add("Mémoire vive presque pleine ($ramLibre Go libres) : ferme Jarvis/Ollama et le navigateur avant de jouer.") }
Get-CimInstance Win32_LogicalDisk -Filter "DriveType=3" | ForEach-Object {
  $libre = [math]::Round($_.FreeSpace / 1GB, 1); $tot = [math]::Round($_.Size / 1GB, 1)
  A ("Disque " + $_.DeviceID + " : $libre Go libres sur $tot Go")
  if ($_.DeviceID -eq 'C:' -and $libre -lt 20) { $alertes.Add("Disque C: presque plein ($libre Go) : Windows et les jeux plantent quand il manque de place.") }
}
$pf = Get-CimInstance Win32_PageFileUsage
if ($pf) { $pf | ForEach-Object { A ("Fichier d'échange : " + $_.Name + " · " + $_.AllocatedBaseSize + " Mo") } }
else { A "Fichier d'échange : AUCUN"; $alertes.Add("Pas de fichier d'échange : les jeux peuvent se fermer quand la mémoire est pleine. Remets-le en « géré par le système ».") }

T "2. La carte graphique"
$smi = "$env:SystemRoot\System32\nvidia-smi.exe"
if (-not (Test-Path $smi)) { $smi = (Get-Command nvidia-smi -ErrorAction SilentlyContinue).Source }
if ($smi) {
  $g = & $smi --query-gpu=name,driver_version,memory.total,memory.used,temperature.gpu,power.draw --format=csv,noheader,nounits
  foreach ($ligne in $g) {
    $p = $ligne -split ',\s*'
    A ("Carte : " + $p[0] + " · pilote " + $p[1])
    A ("Mémoire vidéo : " + $p[3] + " Mo utilisés sur " + $p[2] + " Mo · " + $p[4] + " °C")
    if ([int]$p[3] -gt 0.5 * [int]$p[2]) { $alertes.Add("La mémoire vidéo est déjà occupée à plus de 50 % hors jeu (" + $p[3] + " Mo). Valorant peut manquer de place et se fermer.") }
    if ([int]$p[4] -ge 83) { $alertes.Add("Carte graphique chaude (" + $p[4] + " °C) sans jeu lancé : vérifie la ventilation.") }
  }
  A "Programmes qui utilisent la carte :"
  & $smi --query-compute-apps=process_name,used_memory --format=csv,noheader | ForEach-Object { A ("  " + $_) }
} else { A "nvidia-smi introuvable : pilote NVIDIA absent ou mal installé."; $alertes.Add("Le pilote NVIDIA semble absent ou abîmé : réinstalle-le depuis nvidia.com.") }

T "3. L'IA locale (Ollama) de Jarvis"
try {
  $ps = Invoke-RestMethod -Uri 'http://127.0.0.1:11434/api/ps' -TimeoutSec 3
  if ($ps.models.Count -eq 0) { A "Ollama tourne, aucun modèle chargé en ce moment." }
  foreach ($m in $ps.models) {
    $vram = [math]::Round($m.size_vram / 1GB, 1)
    A ("Modèle chargé : " + $m.name + " · $vram Go dans la carte graphique · libéré à " + $m.expires_at)
    if ($vram -gt 4) { $alertes.Add("L'IA locale " + $m.name + " occupe $vram Go de la carte graphique. Si tu lances Valorant en même temps, il peut manquer de mémoire vidéo et se fermer. Ferme Jarvis ou mets le Directeur en pause avant de jouer.") }
  }
} catch { A "Ollama n'est pas lancé (bien pour jouer)." }

T "4. Fermetures de Valorant et des programmes Riot"
$jeu = 'VALORANT|ShooterGame|RiotClient|vgc|vgk|Riot'
$app = Get-WinEvent -FilterHashtable @{LogName='Application'; Id=1000,1001,1002; StartTime=$depuis} | Where-Object { $_.Message -match $jeu }
if ($app) {
  A ("$(@($app).Count) événement(s) de plantage ou de blocage :")
  $app | Select-Object -First 15 | ForEach-Object { A ("  " + $_.TimeCreated.ToString('dd/MM HH:mm') + " · ID " + $_.Id + " · " + (($_.Message -split "`n")[0..2] -join ' ').Trim()) }
  $alertes.Add("Windows a noté $(@($app).Count) plantage(s) de Valorant/Riot. Le détail (module en faute) est dans la partie 4 du rapport.")
} else { A "Aucun plantage de Valorant noté par Windows (le jeu a peut-être été fermé par Vanguard ou par le pilote graphique : voir partie 5)." }

T "5. Pilote graphique et système"
$sys = @()
$sys += Get-WinEvent -FilterHashtable @{LogName='System'; ProviderName='nvlddmkm'; StartTime=$depuis}
$sys += Get-WinEvent -FilterHashtable @{LogName='System'; ProviderName='Display'; Id=4101; StartTime=$depuis}
$tdr = @($sys).Count
A ("Pilote graphique qui a cessé de répondre (nvlddmkm / Display 4101) : $tdr fois")
@($sys) | Sort-Object TimeCreated -Descending | Select-Object -First 8 | ForEach-Object { A ("  " + $_.TimeCreated.ToString('dd/MM HH:mm') + " · " + $_.ProviderName + " " + $_.Id) }
if ($tdr -gt 0) { $alertes.Add("Le pilote graphique a planté $tdr fois. Causes fréquentes : mémoire vidéo pleine (IA locale), pilote abîmé (réinstallation propre avec DDU), carte overclockée ou trop chaude.") }
$live = Get-WinEvent -FilterHashtable @{LogName='Application'; ProviderName='Windows Error Reporting'; Id=1001; StartTime=$depuis} | Where-Object { $_.Message -match 'LiveKernelEvent' }
A ("Erreurs matérielles du pilote (LiveKernelEvent) : " + @($live).Count)
if (@($live).Count -gt 0) { $alertes.Add("Windows a vu " + @($live).Count + " LiveKernelEvent (souvent code 141/117 = carte graphique qui ne répond plus).") }
$kp = Get-WinEvent -FilterHashtable @{LogName='System'; ProviderName='Microsoft-Windows-Kernel-Power'; Id=41; StartTime=$depuis}
A ("Redémarrages brutaux (Kernel-Power 41) : " + @($kp).Count)
$whea = Get-WinEvent -FilterHashtable @{LogName='System'; ProviderName='Microsoft-Windows-WHEA-Logger'; StartTime=$depuis}
A ("Erreurs matérielles (WHEA) : " + @($whea).Count)
if (@($whea).Count -gt 0) { $alertes.Add("Erreurs matérielles WHEA : processeur, mémoire ou carte instable (overclock, XMP trop haut, chaleur).") }
$bsod = Get-WinEvent -FilterHashtable @{LogName='System'; ProviderName='Microsoft-Windows-WER-SystemErrorReporting'; StartTime=$depuis}
A ("Écrans bleus : " + @($bsod).Count)

T "6. Riot Vanguard (l'anti-triche)"
foreach ($s in 'vgc','vgk') {
  $svc = Get-CimInstance Win32_Service -Filter "Name='$s'"
  if ($svc) { A ("Service $s : " + $svc.State + " · démarrage " + $svc.StartMode) } else { A "Service $s : ABSENT"; $alertes.Add("Le service Vanguard $s est absent : Valorant se ferme sans lui. Réinstalle Riot Vanguard (des dossiers supprimés ont pu l'abîmer).") }
}
foreach ($d in "$env:ProgramFiles\Riot Vanguard", "C:\Riot Games\VALORANT\live", "C:\Riot Games\Riot Client") {
  A ("Dossier " + $d + " : " + $(if (Test-Path $d) { 'présent' } else { 'ABSENT' }))
}
if (-not (Test-Path "$env:ProgramFiles\Riot Vanguard")) { $alertes.Add("Le dossier Riot Vanguard est introuvable : réinstalle Vanguard depuis le client Riot.") }
$vglog = Get-ChildItem "$env:ProgramFiles\Riot Vanguard\Logs" -File | Sort-Object LastWriteTime -Descending | Select-Object -First 3
foreach ($f in $vglog) { A ("Journal Vanguard récent : " + $f.Name + " · " + $f.LastWriteTime.ToString('dd/MM HH:mm')) }

T "7. Traces de Valorant"
$crash = Get-ChildItem "$env:LOCALAPPDATA\VALORANT\Saved\Crashes" -Directory | Where-Object { $_.LastWriteTime -gt $depuis }
A ("Dossiers de plantage du jeu ($jours j) : " + @($crash).Count)
@($crash) | Sort-Object LastWriteTime -Descending | Select-Object -First 5 | ForEach-Object { A ("  " + $_.LastWriteTime.ToString('dd/MM HH:mm') + " · " + $_.Name) }
if (@($crash).Count -gt 0) { $alertes.Add("Valorant a écrit " + @($crash).Count + " rapport(s) de plantage : le jeu a vraiment planté (pas une simple fermeture).") }
$log = "$env:LOCALAPPDATA\VALORANT\Saved\Logs\ShooterGame.log"
if (Test-Path $log) {
  A "Dernières erreurs dans ShooterGame.log :"
  Select-String -Path $log -Pattern 'Fatal|Error:|Crash|D3D|GPU|out of memory|OutOfMemory' | Select-Object -Last 12 | ForEach-Object { A ("  " + $_.Line.Trim().Substring(0, [math]::Min(200, $_.Line.Trim().Length))) }
  if (Select-String -Path $log -Pattern 'out of memory|OutOfMemory|DXGI_ERROR_DEVICE_REMOVED|DEVICE_HUNG' -Quiet) { $alertes.Add("Le journal de Valorant parle de mémoire vidéo pleine ou de carte qui ne répond plus (DEVICE_REMOVED/HUNG).") }
} else { A "ShooterGame.log introuvable." }

T "8. Ce qui tourne en ce moment (les 12 plus gourmands en mémoire)"
Get-Process | Sort-Object WorkingSet64 -Descending | Select-Object -First 12 | ForEach-Object { A ("  " + $_.ProcessName.PadRight(28) + [math]::Round($_.WorkingSet64 / 1MB) + " Mo") }
$jv = Get-Process | Where-Object { $_.ProcessName -match '^(ollama|python|litellm|pythonw)' }
if ($jv) { A ("Jarvis / IA en arrière-plan : " + (($jv | Select-Object -ExpandProperty ProcessName -Unique) -join ', ')) }

T "VERDICT"
if ($alertes.Count -eq 0) { A "Rien d'anormal trouvé. Lance ce diagnostic juste APRÈS une fermeture de Valorant pour attraper la cause." }
else { $i = 1; foreach ($a in $alertes) { A ("$i. $a"); $i++ } }

$L | Out-File -FilePath $rapport -Encoding utf8
Write-Host "`nRapport écrit : $rapport" -ForegroundColor Green
Write-Host "Envoie-le à Claude si tu veux qu'il l'analyse."
