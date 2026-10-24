# Qui ouvre des fenêtres CMD ? — LECTURE SEULE. Note chaque nouveau programme lancé (cmd, powershell, python, ollama…)
# avec le programme qui l'a lancé. Laisse cette fenêtre ouverte ; quand une fenêtre CMD apparaît, attends 10 s puis ferme celle-ci.
$ErrorActionPreference = 'SilentlyContinue'
$sortie = Join-Path $PSScriptRoot ("qui-ouvre-cmd-" + (Get-Date -Format 'yyyy-MM-dd_HHmm') + ".txt")
$surveille = '^(cmd|powershell|pwsh|conhost|python|pythonw|py|pyw|wscript|cscript|ollama.*|llama.*|litellm|git|node|claude|codex|schtasks|taskeng|WindowsTerminal|OpenConsole)\.exe$'
function Masquer($t) { if (-not $t) { return '' }; ($t -replace '[A-Za-z0-9_\-]{32,}', '<long>') }
$vus = @{}
Get-CimInstance Win32_Process | ForEach-Object { $vus[$_.ProcessId] = $true }
"Surveillance démarrée le $(Get-Date -Format 'dd/MM/yyyy HH:mm:ss'). Les programmes déjà ouverts ne sont pas notés." | Tee-Object -FilePath $sortie
Write-Host "Laisse cette fenêtre ouverte. Quand une fenêtre CMD apparaît, attends 10 secondes puis ferme celle-ci." -ForegroundColor Cyan
while ($true) {
  $tous = Get-CimInstance Win32_Process
  $parId = @{}; foreach ($p in $tous) { $parId[$p.ProcessId] = $p }
  foreach ($p in $tous) {
    if ($vus.ContainsKey($p.ProcessId)) { continue }
    $vus[$p.ProcessId] = $true
    if ($p.Name -notmatch $surveille) { continue }
    $parent = $parId[$p.ParentProcessId]
    $grand = if ($parent) { $parId[$parent.ParentProcessId] } else { $null }
    $l = @(
      "",
      "$(Get-Date -Format 'HH:mm:ss')  NOUVEAU : $($p.Name) (PID $($p.ProcessId))",
      "   commande : $(Masquer $p.CommandLine)",
      "   lancé par : $(if ($parent) { "$($parent.Name) (PID $($parent.ProcessId)) — $(Masquer $parent.CommandLine)" } else { 'programme déjà fermé' })",
      "   lui-même lancé par : $(if ($grand) { "$($grand.Name) — $(Masquer $grand.CommandLine)" } else { '?' })"
    )
    $l | Tee-Object -FilePath $sortie -Append
  }
  Start-Sleep -Milliseconds 700
}
