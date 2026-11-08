@echo off
REM Manual launcher: starts fps_bridge.ps1 (in this folder) as Administrator.
powershell -NoProfile -Command "Start-Process powershell -Verb RunAs -ArgumentList '-NoProfile -ExecutionPolicy Bypass -NoExit -File ""%~dp0fps_bridge.ps1""'"
