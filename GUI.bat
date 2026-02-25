@echo off
:: Change directory to where this batch file is located
cd /d "%~dp0"
:: Runs the PowerShell GUI without requiring the user to mess with Execution Policies
powershell.exe -ExecutionPolicy Bypass -File "gui.ps1"
