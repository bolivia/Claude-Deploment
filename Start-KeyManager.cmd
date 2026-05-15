@echo off
pushd "%~dp0"
powershell.exe -ExecutionPolicy Bypass -File "Manage-ClaudeKeys.ps1"
popd
