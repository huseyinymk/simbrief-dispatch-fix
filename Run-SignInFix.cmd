@echo off
rem SimBrief Dispatch Sign-In Fix - developed by huseyinymk
rem SPDX-License-Identifier: GPL-3.0-or-later
rem Copyright (C) 2026 huseyinymk
rem Starts SimBriefDispatch-SignInFix.ps1 with script execution allowed for this run only.
rem Windows 11 blocks .ps1 files started with right-click > "Run with PowerShell" by default.
rem No Windows setting is changed.
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0SimBriefDispatch-SignInFix.ps1" %*
if errorlevel 1 pause
