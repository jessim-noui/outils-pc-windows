@echo off
chcp 65001 >nul
title Qui ouvre des CMD - laisse ouvert
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0qui-ouvre-cmd.ps1"
pause
