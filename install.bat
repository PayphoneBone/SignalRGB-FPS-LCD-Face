@echo off
REM Double-click to install. Runs install.ps1 from this folder.
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0install.ps1" %*
