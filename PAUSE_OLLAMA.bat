@echo off
chcp 65001 >nul
rem PAUSE OLLAMA + JARVIS - double-clic avant de jouer.
rem  1. Arrete Ollama ET les programmes de Jarvis qui le reveillent (serveur.py, tri des mails, recherche d'offres, routeur).
rem  2. Garde la fenetre ouverte (reduite) : si quelque chose les relance, ils sont refermes dans les 10 s
rem     et le coupable est note dans pause_ollama_journal.txt (a cote de ce fichier).
rem  3. Apres ta partie : ferme cette fenetre, puis double-clic de nouveau pour tout relancer (JARVIS.bat).
rem Ne touche ni a ton jeu, ni a Discord, ni a Claude Code, ni a aucune autre appli. Ne supprime rien.
set "JOURNAL=%~dp0pause_ollama_journal.txt"
rem Dossier de Jarvis : variable JARVIS_DOSSIER (sinon, le dossier de ce fichier)
if not defined JARVIS_DOSSIER set "JARVIS_DOSSIER=%~dp0"
set "JARVIS_BAT=%JARVIS_DOSSIER%\JARVIS.bat"
set "CIBLES=serveur\.py|suivi_candidatures|analyser_offres|tout_chercher|veille\.py|litellm|routeur\\run\.bat"

call :TOURNE
if %errorlevel%==0 goto ARRETER
goto RELANCER

:ARRETER
title Pause Ollama
echo Memoire AVANT :
call :MEMOIRE
echo.
call :TUER
timeout /t 3 /nobreak >nul
echo.
echo Memoire APRES :
call :MEMOIRE
echo.
echo  ==^> Ollama et Jarvis sont en PAUSE. Tu peux jouer.
echo      SURVEILLANCE ACTIVE : laisse cette fenetre ouverte (tu peux la reduire).
echo      Si quelque chose les relance, ils sont refermes et le coupable est note ici.
echo      Apres ta partie : ferme cette fenetre, puis double-clic sur le fichier pour tout relancer.
echo.
title Pause Ollama - SURVEILLANCE (ferme la fenetre pour arreter)
:SURVEILLER
timeout /t 10 /nobreak >nul
call :TOURNE
if not %errorlevel%==0 goto SURVEILLER
echo [%date% %time:~0,8%] Relance detectee ! Qui :
powershell -NoProfile -Command "$c='%CIBLES%'; Get-CimInstance Win32_Process | Where-Object { $_.Name -like 'ollama*' -or ($_.Name -match '^(pythonw?|pyw?|litellm|cmd)\.exe$' -and $_.CommandLine -match $c) } | ForEach-Object { $e = $_; $p = Get-CimInstance Win32_Process | Where-Object { $_.ProcessId -eq $e.ParentProcessId }; $q = if ($p) { $p.Name + ' : ' + ([string]$p.CommandLine) } else { 'parent deja ferme' }; $l = '    ' + $e.Name + ' (' + ([string]$e.CommandLine) + ') <- lance par ' + $q; $l.Substring(0, [math]::Min(220, $l.Length)) }" > "%TEMP%\pause_ollama_qui.txt"
type "%TEMP%\pause_ollama_qui.txt"
echo [%date% %time:~0,8%] Relance detectee, refermee. >> "%JOURNAL%"
type "%TEMP%\pause_ollama_qui.txt" >> "%JOURNAL%"
call :TUER
echo     ==^> referme.
goto SURVEILLER

:RELANCER
title Pause Ollama
echo Ollama et Jarvis sont en pause.
call :MEMOIRE
if exist "%JOURNAL%" (
  echo.
  echo Ce qui a essaye de les relancer recemment :
  powershell -NoProfile -Command "Get-Content -LiteralPath '%JOURNAL%' -Tail 8"
)
echo.
choice /C ON /M "Tout relancer maintenant avec JARVIS.bat (O = oui, N = non)"
if errorlevel 2 goto FIN
if exist "%JARVIS_BAT%" (
  start "" "%JARVIS_BAT%"
  echo Jarvis et Ollama redemarrent.
) else (
  echo JARVIS.bat introuvable. Lance-le toi-meme depuis le dossier de Jarvis.
)
goto FIN

:TOURNE
tasklist /FI "IMAGENAME eq ollama.exe" 2>nul | find /I "ollama.exe" >nul && exit /b 0
tasklist /FI "IMAGENAME eq ollama app.exe" 2>nul | find /I "ollama app.exe" >nul && exit /b 0
powershell -NoProfile -Command "$c='%CIBLES%'; if (Get-CimInstance Win32_Process | Where-Object { $_.Name -match '^(pythonw?|pyw?|litellm)\.exe$' -and $_.CommandLine -match $c }) { exit 0 } else { exit 1 }"
exit /b %errorlevel%

:TUER
powershell -NoProfile -Command "$c='%CIBLES%'; Get-CimInstance Win32_Process | Where-Object { $_.Name -match '^(pythonw?|pyw?|litellm|cmd)\.exe$' -and $_.CommandLine -match $c } | ForEach-Object { Stop-Process -Id $_.ProcessId -Force -ErrorAction SilentlyContinue; $m = ([string]$_.CommandLine) -replace '^.*\\',''; Write-Host ('  Jarvis arrete : ' + $_.Name + ' ' + $m) }"
taskkill /F /T /IM "ollama app.exe" >nul 2>&1
taskkill /F /T /IM "ollama.exe" >nul 2>&1
taskkill /F /T /IM "ollama_llama_server.exe" >nul 2>&1
taskkill /F /T /IM "llama-server.exe" >nul 2>&1
echo   Ollama arrete.
exit /b 0

:MEMOIRE
powershell -NoProfile -Command "$o=Get-CimInstance Win32_OperatingSystem; $u=[math]::Round(100-($o.FreePhysicalMemory/$o.TotalVisibleMemorySize*100)); Write-Host ('  Memoire utilisee : ' + $u + ' %%'); Write-Host '  Ce qui en prend le plus :'; Get-Process | Sort-Object WorkingSet64 -Descending | Select-Object -First 5 | ForEach-Object { Write-Host ('    ' + $_.ProcessName + ' : ' + [math]::Round($_.WorkingSet64/1GB,1) + ' Go') }"
exit /b 0

:FIN
echo.
pause
