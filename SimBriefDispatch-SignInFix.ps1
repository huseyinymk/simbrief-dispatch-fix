# SPDX-License-Identifier: GPL-3.0-or-later
# Copyright (C) 2026 huseyinymk

<#
.SYNOPSIS
    SimBrief Dispatch Sign-In Fix - developed by huseyinymk

.DESCRIPTION
    Fixes Navigraph "SimBrief Dispatch for MSFS" when the in-sim panel stays on the sign-in
    code screen even after the code was approved.

    The add-on keeps its login tokens in a WebAssembly module that does not answer on some
    PCs, so the panel never learns that the sign-in succeeded. This script replaces that
    token storage with the simulator's built-in DataStorage API.

    Only your own installed copy of the add-on is edited. The three files it changes are
    backed up first, and "Revert Patch" puts them back.

    Start it by double-clicking Run-SignInFix.cmd. Windows 11 blocks .ps1 files started
    with right-click > "Run with PowerShell" unless script execution was allowed before.

.PARAMETER Action
    Menu (default), Apply, Revert or Status. Apply/Revert/Status run without the menu.

.PARAMETER PackagePath
    The navigraph-simbrief-dispatch-2020 folder (or a file inside it). Found automatically if omitted.

.PARAMETER BackupRoot
    Where backups and the manually selected add-on location are kept.
    Default: Documents\SimBriefDispatchFix-Backups

.PARAMETER NoDialog
    Ask for the add-on location in the console instead of opening a file window.

.NOTES
    SimBrief Dispatch Sign-In Fix
    Copyright (C) 2026 huseyinymk

    This program is free software: you can redistribute it and/or modify
    it under the terms of the GNU General Public License as published by
    the Free Software Foundation, either version 3 of the License, or
    (at your option) any later version.

    This program is distributed in the hope that it will be useful,
    but WITHOUT ANY WARRANTY; without even the implied warranty of
    MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
    GNU General Public License for more details.

    You should have received a copy of the GNU General Public License
    along with this program.  If not, see <https://www.gnu.org/licenses/>.
#>
[CmdletBinding()]
param(
    [ValidateSet('Menu', 'Apply', 'Revert', 'Status')]
    [string]$Action = 'Menu',
    [string]$PackagePath,
    [string]$BackupRoot,
    [switch]$NoDialog
)

# Keep this file pure ASCII: Windows PowerShell 5.1 reads scripts without a BOM as ANSI.
Set-StrictMode -Version 2.0
$ErrorActionPreference = 'Stop'

$FixVersion      = '1.1.0'
$Author          = 'huseyinymk'
$PatchMarker     = 'NG-SBD-STORE-PATCH'
$PackageName     = 'navigraph-simbrief-dispatch-2020'
$IndexRelPath    = 'html_ui\Pages\Navigraph\SimBrief\index.js'
$IndexLayoutPath = 'html_ui/Pages/Navigraph/SimBrief/index.js'
$TestedVersions  = @('1.3.2')
$BackupFiles     = @($IndexRelPath, 'layout.json', 'manifest.json')
if (-not $BackupRoot) { $BackupRoot = Join-Path ([Environment]::GetFolderPath('MyDocuments')) 'SimBriefDispatchFix-Backups' }
$LocationFile    = Join-Path $BackupRoot 'addon-location.txt'

# Where each simulator edition keeps UserCfg.opt, whose InstalledPackagesPath line points at the
# folder that holds Community. "Packages" is that folder's default location if UserCfg.opt is missing.
$SimEditions = @(
    @{ Name = 'MSFS 2020 (Microsoft Store / Xbox app)'
       Cfg = '%LOCALAPPDATA%\Packages\Microsoft.FlightSimulator_8wekyb3d8bbwe\LocalCache\UserCfg.opt'
       Packages = '%LOCALAPPDATA%\Packages\Microsoft.FlightSimulator_8wekyb3d8bbwe\LocalCache\Packages' },
    @{ Name = 'MSFS 2020 (Steam)'
       Cfg = '%APPDATA%\Microsoft Flight Simulator\UserCfg.opt'
       Packages = '%APPDATA%\Microsoft Flight Simulator\Packages' },
    @{ Name = 'MSFS 2024 (Microsoft Store / Xbox app)'
       Cfg = '%LOCALAPPDATA%\Packages\Microsoft.Limitless_8wekyb3d8bbwe\LocalCache\UserCfg.opt'
       Packages = '%LOCALAPPDATA%\Packages\Microsoft.Limitless_8wekyb3d8bbwe\LocalCache\Packages' },
    @{ Name = 'MSFS 2024 (Steam)'
       Cfg = '%APPDATA%\Microsoft Flight Simulator 2024\UserCfg.opt'
       Packages = '%APPDATA%\Microsoft Flight Simulator 2024\Packages' }
)

# ISO-8859-1 maps every byte to one char and back, so index.js is rewritten byte for byte
# except for the one statement that is replaced (plain ASCII).
$Latin1 = [System.Text.Encoding]::GetEncoding(28591)
$Utf8   = New-Object System.Text.UTF8Encoding($false)

# Replacement for the statement that wires the Navigraph SDK to the WASM token store.
# %%NAME%% placeholders are filled with the minified names found in the installed file.
$AdapterTemplate = @'
const %%DS_PREFIX%%%%KEYS%%=%%KEYSOBJ%%,NgSbd_mem=new Map,NgSbd_chunk=500,NgSbd_key=r=>"NG_SBD_STORE."+r,NgSbd_get=r=>{const k=NgSbd_key(r);try{if(typeof GetStoredData=="function"){const n=parseInt(GetStoredData(k+".n")||"0",10)||0;if(n>0){let s="";for(let i=0;i<n;i++)s+=GetStoredData(k+"."+i)||"";return s}}}catch(e){console.error("[NG-SBD-STORE] read error:",e)}return NgSbd_mem.has(k)?NgSbd_mem.get(k):null},NgSbd_set=(r,e)=>{const k=NgSbd_key(r),v=e==null?"":String(e);NgSbd_mem.set(k,v);try{if(typeof SetStoredData=="function"){const n=Math.ceil(v.length/NgSbd_chunk);for(let i=0;i<n;i++)SetStoredData(k+"."+i,v.slice(i*NgSbd_chunk,(i+1)*NgSbd_chunk));SetStoredData(k+".n",String(n))}}catch(e){console.error("[NG-SBD-STORE] write error:",e)}},%%STORE%%={getItem:r=>Promise.resolve(NgSbd_get(r)),setItem:(r,e)=>Promise.resolve(NgSbd_set(r,e))},%%SDK%%=%%FACTORY%%({storage:%%STORE%%,keys:%%KEYS%%});/*NG-SBD-STORE-PATCH v1: WASM CommBus datastore replaced by sim DataStore (GetStoredData/SetStoredData)*/
'@

# ------------------------------------------------------------------ output

function Write-Info([string]$Message) { Write-Host "      $Message" }
function Write-Ok([string]$Message)   { Write-Host "  OK  $Message" -ForegroundColor Green }
function Write-Warn([string]$Message) { Write-Host "  !!  $Message" -ForegroundColor Yellow }
function Write-Err([string]$Message)  { Write-Host "  XX  $Message" -ForegroundColor Red }

function Show-Banner {
    Write-Host ''
    Write-Host '  ================================================' -ForegroundColor Cyan
    Write-Host '    SimBrief Dispatch Sign-In Fix' -ForegroundColor Cyan
    Write-Host "    Developed by $Author" -ForegroundColor Cyan
    Write-Host "    Version $FixVersion" -ForegroundColor DarkGray
    Write-Host '  ================================================' -ForegroundColor Cyan
    Write-Host ''
}

# ------------------------------------------------------------------ files

function Read-Latin1([string]$Path) { return $Latin1.GetString([System.IO.File]::ReadAllBytes($Path)) }
function Write-Latin1([string]$Path, [string]$Text) { [System.IO.File]::WriteAllBytes($Path, $Latin1.GetBytes($Text)) }

function Test-Utf8Bom([string]$Path) {
    $b = [System.IO.File]::ReadAllBytes($Path)
    return ($b.Length -ge 3 -and $b[0] -eq 0xEF -and $b[1] -eq 0xBB -and $b[2] -eq 0xBF)
}

function Read-Text([string]$Path) {
    $b = [System.IO.File]::ReadAllBytes($Path)
    if ($b.Length -ge 3 -and $b[0] -eq 0xEF -and $b[1] -eq 0xBB -and $b[2] -eq 0xBF) { return $Utf8.GetString($b, 3, $b.Length - 3) }
    return $Utf8.GetString($b)
}

function Write-Text([string]$Path, [string]$Text, [bool]$Bom) {
    $body = $Utf8.GetBytes($Text)
    if ($Bom) {
        $all = New-Object byte[] ($body.Length + 3)
        $all[0] = 0xEF; $all[1] = 0xBB; $all[2] = 0xBF
        [System.Array]::Copy($body, 0, $all, 3, $body.Length)
        $body = $all
    }
    [System.IO.File]::WriteAllBytes($Path, $body)
}

# .NET directly: Get-FileHash lives in a script module that can fail to load in some shells.
function Get-Sha256([string]$Path) {
    $sha = [System.Security.Cryptography.SHA256]::Create()
    try { return ([System.BitConverter]::ToString($sha.ComputeHash([System.IO.File]::ReadAllBytes($Path)))).Replace('-', '') }
    finally { $sha.Dispose() }
}

# ------------------------------------------------------------------ finding the add-on

function Test-SimRunning {
    foreach ($name in @('FlightSimulator', 'FlightSimulator2024')) {
        if (Get-Process -Name $name -ErrorAction SilentlyContinue) { return $true }
    }
    return $false
}

function Get-CommunityFolders {
    $result = New-Object System.Collections.Generic.List[object]
    foreach ($edition in $SimEditions) {
        $community = $null
        $cfg = [Environment]::ExpandEnvironmentVariables($edition.Cfg)
        if (Test-Path -LiteralPath $cfg) {
            # The simulator writes this file as UTF-8; fall back to the ANSI code page just in case.
            foreach ($enc in @($Utf8, [System.Text.Encoding]::Default)) {
                $m = [regex]::Match($enc.GetString([System.IO.File]::ReadAllBytes($cfg)), 'InstalledPackagesPath\s+"([^"]+)"')
                if (-not $m.Success) { continue }
                $candidate = Join-Path $m.Groups[1].Value 'Community'
                if (Test-Path -LiteralPath $candidate) { $community = $candidate; break }
            }
        }
        if (-not $community) {
            $candidate = Join-Path ([Environment]::ExpandEnvironmentVariables($edition.Packages)) 'Community'
            if (Test-Path -LiteralPath $candidate) { $community = $candidate }
        }
        if ($community) { $result.Add([pscustomobject]@{ Sim = $edition.Name; Community = $community }) }
    }
    return ,$result
}

function Find-AddonsInCommunity([string]$Community) {
    $found = New-Object System.Collections.Generic.List[string]
    $direct = Join-Path $Community $PackageName
    if (Test-Path -LiteralPath (Join-Path $direct $IndexRelPath)) { $found.Add($direct); return ,$found }
    # Fallback for a renamed folder: look for the add-on by its manifest title.
    foreach ($dir in (Get-ChildItem -LiteralPath $Community -Directory -ErrorAction SilentlyContinue)) {
        $manifest = Join-Path $dir.FullName 'manifest.json'
        if ((Test-Path -LiteralPath $manifest) -and (Test-Path -LiteralPath (Join-Path $dir.FullName $IndexRelPath))) {
            if ((Read-Text $manifest) -match 'SimBrief Dispatch') { $found.Add($dir.FullName) }
        }
    }
    return ,$found
}

# Accepts the add-on folder, any file inside it (manifest.json, layout.json...), or a Community folder.
function Resolve-AddonPath([string]$Candidate) {
    if (-not $Candidate) { return $null }
    $c = $Candidate.Trim().Trim('"').Trim()
    if (-not $c -or -not (Test-Path -LiteralPath $c)) { return $null }
    $dir = (Resolve-Path -LiteralPath $c).ProviderPath
    if (Test-Path -LiteralPath $dir -PathType Leaf) { $dir = [System.IO.Path]::GetDirectoryName($dir) }
    for ($i = 0; $i -lt 8 -and $dir; $i++) {
        if (Test-Path -LiteralPath (Join-Path $dir $IndexRelPath)) { return $dir }
        $dir = [System.IO.Path]::GetDirectoryName($dir)
    }
    $inside = Find-AddonsInCommunity ((Resolve-Path -LiteralPath $c).ProviderPath)
    if ($inside.Count -ge 1) { return $inside[0] }
    return $null
}

function Get-RememberedAddon {
    if (-not (Test-Path -LiteralPath $LocationFile)) { return $null }
    return (Resolve-AddonPath (Read-Text $LocationFile))
}

function Save-RememberedAddon([string]$Path) {
    if (-not (Test-Path -LiteralPath $BackupRoot)) { New-Item -ItemType Directory -Path $BackupRoot -Force | Out-Null }
    Write-Text $LocationFile $Path $false
}

function Get-DispatchAddons {
    $found = New-Object System.Collections.Generic.List[object]
    if ($PackagePath) {
        $p = Resolve-AddonPath $PackagePath
        if (-not $p) { throw "Not a SimBrief Dispatch add-on folder: $PackagePath" }
        $found.Add([pscustomobject]@{ Sim = 'Given with -PackagePath'; Path = $p })
        return ,$found
    }
    $seen = New-Object 'System.Collections.Generic.HashSet[string]' ([System.StringComparer]::OrdinalIgnoreCase)
    foreach ($c in (Get-CommunityFolders)) {
        foreach ($p in (Find-AddonsInCommunity $c.Community)) {
            if ($seen.Add($p)) { $found.Add([pscustomobject]@{ Sim = $c.Sim; Path = $p }) }
        }
    }
    $remembered = Get-RememberedAddon
    if ($remembered -and $seen.Add($remembered)) { $found.Add([pscustomobject]@{ Sim = 'Selected manually'; Path = $remembered }) }
    return ,$found
}

function Show-ManifestPicker([string]$InitialDirectory) {
    # Returns @{ Shown = $false } when no window can be opened, so the caller can ask in the console.
    if ($NoDialog) { return @{ Shown = $false; File = $null } }
    try {
        if ([System.Threading.Thread]::CurrentThread.GetApartmentState() -ne [System.Threading.ApartmentState]::STA) { return @{ Shown = $false; File = $null } }
        Add-Type -AssemblyName System.Windows.Forms
        $dialog = New-Object System.Windows.Forms.OpenFileDialog
        $dialog.Title = 'Select manifest.json in the navigraph-simbrief-dispatch-2020 folder'
        $dialog.Filter = 'SimBrief Dispatch manifest (manifest.json)|manifest.json|All files (*.*)|*.*'
        $dialog.CheckFileExists = $true
        if ($InitialDirectory -and (Test-Path -LiteralPath $InitialDirectory)) { $dialog.InitialDirectory = $InitialDirectory }
        $owner = New-Object System.Windows.Forms.Form
        $owner.TopMost = $true
        try { $answer = $dialog.ShowDialog($owner) } finally { $owner.Dispose() }
        if ($answer -eq [System.Windows.Forms.DialogResult]::OK) { return @{ Shown = $true; File = $dialog.FileName } }
        return @{ Shown = $true; File = $null }
    } catch {
        return @{ Shown = $false; File = $null }
    }
}

function Select-AddonInteractively {
    Write-Host ''
    Write-Info 'Select the file manifest.json inside the navigraph-simbrief-dispatch-2020 folder.'
    Write-Info 'It is in your simulator Community folder, for example:'
    Write-Info '...\Community\navigraph-simbrief-dispatch-2020\manifest.json'
    Write-Host ''
    $initial = $null
    foreach ($c in (Get-CommunityFolders)) { $initial = $c.Community; break }
    if (-not $initial) { $initial = $env:USERPROFILE }

    $picked = $null
    $pick = Show-ManifestPicker $initial
    if ($pick.Shown) {
        $picked = $pick.File
    } else {
        $picked = Read-Host '  Paste the full path of the add-on folder or its manifest.json (Enter to cancel)'
    }
    if (-not $picked) { Write-Warn 'No file selected.'; return $null }

    $addon = Resolve-AddonPath $picked
    if (-not $addon) {
        Write-Err "This is not the SimBrief Dispatch add-on: $picked"
        Write-Info 'The right folder contains html_ui\Pages\Navigraph\SimBrief\index.js.'
        return $null
    }
    Save-RememberedAddon $addon
    Write-Ok "Add-on selected: $addon"
    Write-Info 'This location is remembered for the next time.'
    return $addon
}

# In the menu, fall back to manual selection when nothing was found automatically.
function Get-AddonsForAction([bool]$Interactive) {
    try { $addons = Get-DispatchAddons } catch { Write-Err $_.Exception.Message; return $null }
    if ($addons.Count -gt 0) { return ,$addons }
    Write-Warn 'SimBrief Dispatch for MSFS was not found automatically.'
    if (-not $Interactive) {
        Write-Info 'Run the script with -PackagePath "<add-on folder>", or start the menu and choose 3.'
        return $null
    }
    $addon = Select-AddonInteractively
    if (-not $addon) { return $null }
    $list = New-Object System.Collections.Generic.List[object]
    $list.Add([pscustomobject]@{ Sim = 'Selected manually'; Path = $addon })
    return ,$list
}

function Get-PackageVersion([string]$Pkg) {
    try {
        $manifest = (Read-Text (Join-Path $Pkg 'manifest.json')) | ConvertFrom-Json
        if ($manifest.PSObject.Properties['package_version']) { return [string]$manifest.package_version }
    } catch { }
    return 'unknown'
}

# ------------------------------------------------------------------ patch logic

function Get-PatchPlan([string]$Js) {
    # Minified names differ between builds, so they are captured instead of hard-coded.
    $id = '[A-Za-z_$][A-Za-z0-9_$]*'
    $pattern = 'const\s+(?<ds>' + $id + ')=(?<cls>' + $id + ')\.openDataStore\("SIMBRIEF_IGP"\),' +
               '(?<keys>' + $id + ')=(?<keysobj>\{accessToken:"NG_SIMBRIEF_ACCESS_TOKEN",refreshToken:"NG_SIMBRIEF_REFRESH_TOKEN"\}),' +
               '(?<store>' + $id + ')=\{getItem:.*?\},' +
               '(?<sdk>' + $id + ')=(?<factory>' + $id + ')\(\{storage:\k<store>,keys:\k<keys>\}\);'
    $hits = [regex]::Matches($Js, $pattern)
    if ($hits.Count -ne 1) { return $null }
    $m = $hits[0]

    # Drop the datastore handle only if nothing else in the file refers to that name.
    $ds = $m.Groups['ds'].Value
    $word = '(?<![A-Za-z0-9_$])' + [regex]::Escape($ds) + '(?![A-Za-z0-9_$])'
    $dsPrefix = ''
    if ([regex]::Matches($Js, $word).Count -ne [regex]::Matches($m.Value, $word).Count) {
        $dsPrefix = $ds + '=' + $m.Groups['cls'].Value + '.openDataStore("SIMBRIEF_IGP"),'
    }

    $statement = $AdapterTemplate.Trim()
    $statement = $statement.Replace('%%DS_PREFIX%%', $dsPrefix)
    $statement = $statement.Replace('%%KEYSOBJ%%', $m.Groups['keysobj'].Value)
    $statement = $statement.Replace('%%KEYS%%', $m.Groups['keys'].Value)
    $statement = $statement.Replace('%%STORE%%', $m.Groups['store'].Value)
    $statement = $statement.Replace('%%SDK%%', $m.Groups['sdk'].Value)
    $statement = $statement.Replace('%%FACTORY%%', $m.Groups['factory'].Value)
    if ($statement.Contains('%%')) { throw 'Internal error: a template placeholder was left unreplaced.' }

    return ($Js.Substring(0, $m.Index) + $statement + $Js.Substring($m.Index + $m.Length))
}

function Get-PackageState([string]$Pkg) {
    $js = Read-Latin1 (Join-Path $Pkg $IndexRelPath)
    if ($js.Contains($PatchMarker)) { return 'Patched' }
    if ($null -ne (Get-PatchPlan $js)) { return 'Not patched' }
    return 'Unsupported version'
}

function Update-Layout([string]$Pkg) {
    # Keep layout.json in step with the edited file; returns the new sum of all file sizes.
    $layoutPath = Join-Path $Pkg 'layout.json'
    $index = Get-Item -LiteralPath (Join-Path $Pkg $IndexRelPath)
    $size = [string]$index.Length
    $date = [string]$index.LastWriteTimeUtc.ToFileTimeUtc()
    $bom = Test-Utf8Bom $layoutPath
    $text = Read-Text $layoutPath
    $pattern = '("path"\s*:\s*"' + [regex]::Escape($IndexLayoutPath) + '"\s*,\s*"size"\s*:\s*)\d+(\s*,\s*"date"\s*:\s*)\d+'
    $hits = [regex]::Matches($text, $pattern)
    if ($hits.Count -eq 1) {
        $h = $hits[0]
        $text = $text.Substring(0, $h.Index) + $h.Groups[1].Value + $size + $h.Groups[2].Value + $date + $text.Substring($h.Index + $h.Length)
    } else {
        $layout = $text | ConvertFrom-Json
        $entry = @($layout.content | Where-Object { $_.path -eq $IndexLayoutPath })
        if ($entry.Count -ne 1) { throw "layout.json has no single entry for $IndexLayoutPath." }
        $entry[0].size = [int64]$size
        $entry[0].date = [int64]$date
        $text = $layout | ConvertTo-Json -Depth 6 -Compress
    }
    Write-Text $layoutPath $text $bom
    $sum = [int64]0
    foreach ($e in ((Read-Text $layoutPath) | ConvertFrom-Json).content) { $sum += [int64]$e.size }
    return $sum
}

function Update-Manifest([string]$Pkg, [int64]$Total) {
    $manifestPath = Join-Path $Pkg 'manifest.json'
    $bom = Test-Utf8Bom $manifestPath
    $text = Read-Text $manifestPath
    $m = [regex]::Match($text, '("total_package_size"\s*:\s*)("?)(\d+)("?)')
    if (-not $m.Success) { return }
    $value = [string]$Total
    # Some packages store this as a zero-padded string; keep the same width.
    if ($m.Groups[2].Value -eq '"' -and $m.Groups[3].Value.Length -gt $value.Length) { $value = $value.PadLeft($m.Groups[3].Value.Length, '0') }
    $text = $text.Substring(0, $m.Index) + $m.Groups[1].Value + $m.Groups[2].Value + $value + $m.Groups[4].Value + $text.Substring($m.Index + $m.Length)
    Write-Text $manifestPath $text $bom
}

function Test-PatchedPackage([string]$Pkg) {
    $indexPath = Join-Path $Pkg $IndexRelPath
    if (-not (Read-Latin1 $indexPath).Contains($PatchMarker)) { throw 'Patch marker missing after writing index.js.' }
    $layout = (Read-Text (Join-Path $Pkg 'layout.json')) | ConvertFrom-Json
    $entry = @($layout.content | Where-Object { $_.path -eq $IndexLayoutPath })
    if ($entry.Count -ne 1 -or [int64]$entry[0].size -ne (Get-Item -LiteralPath $indexPath).Length) { throw 'layout.json size does not match index.js.' }
    $sum = [int64]0
    foreach ($e in $layout.content) { $sum += [int64]$e.size }
    $manifest = (Read-Text (Join-Path $Pkg 'manifest.json')) | ConvertFrom-Json
    if ($manifest.PSObject.Properties['total_package_size'] -and [int64]$manifest.total_package_size -ne $sum) { throw 'manifest.json total_package_size does not match layout.json.' }
}

# ------------------------------------------------------------------ backups

function New-FixBackup([string]$Pkg) {
    $dir = Join-Path (Join-Path $BackupRoot (Split-Path $Pkg -Leaf)) (Get-Date -Format 'yyyyMMdd-HHmmss')
    New-Item -ItemType Directory -Path $dir -Force | Out-Null
    $files = @()
    foreach ($rel in $BackupFiles) {
        $src = Join-Path $Pkg $rel
        $name = ($rel -replace '[\\/]', '__')
        Copy-Item -LiteralPath $src -Destination (Join-Path $dir $name) -Force
        $files += [pscustomobject]@{ file = $rel; backup = $name; sha256 = (Get-Sha256 $src) }
    }
    $info = [pscustomobject]@{
        fixVersion     = $FixVersion
        packagePath    = $Pkg
        packageVersion = (Get-PackageVersion $Pkg)
        created        = (Get-Date).ToString('o')
        files          = $files
    }
    Write-Text (Join-Path $dir 'backup-info.json') ($info | ConvertTo-Json -Depth 4) $false
    foreach ($f in $files) {
        if ((Get-Sha256 (Join-Path $dir $f.backup)) -ne $f.sha256) { throw "Backup copy of $($f.file) is not identical to the original." }
    }
    return $dir
}

function Find-LatestBackup([string]$Pkg) {
    $root = Join-Path $BackupRoot (Split-Path $Pkg -Leaf)
    if (-not (Test-Path -LiteralPath $root)) { return $null }
    foreach ($d in (Get-ChildItem -LiteralPath $root -Directory | Sort-Object Name -Descending)) {
        $infoPath = Join-Path $d.FullName 'backup-info.json'
        if (-not (Test-Path -LiteralPath $infoPath)) { continue }
        $info = (Read-Text $infoPath) | ConvertFrom-Json
        if ([string]::Equals([string]$info.packagePath, $Pkg, [System.StringComparison]::OrdinalIgnoreCase)) { return $d.FullName }
    }
    return $null
}

function Restore-FixBackup([string]$Pkg, [string]$BackupDir) {
    $info = (Read-Text (Join-Path $BackupDir 'backup-info.json')) | ConvertFrom-Json
    foreach ($f in $info.files) {
        $dst = Join-Path $Pkg $f.file
        Copy-Item -LiteralPath (Join-Path $BackupDir $f.backup) -Destination $dst -Force
        if ((Get-Sha256 $dst) -ne $f.sha256) { throw "Restored $($f.file) does not match the backup." }
    }
}

# ------------------------------------------------------------------ actions

function Show-Status {
    try { $addons = Get-DispatchAddons } catch { Write-Warn $_.Exception.Message; Write-Host ''; return }
    if ($addons.Count -eq 0) {
        Write-Warn 'SimBrief Dispatch for MSFS was not found automatically.'
        Write-Info 'Choose 3 to select its folder yourself.'
        Write-Host ''
        return
    }
    foreach ($a in $addons) {
        Write-Host "  Simulator : $($a.Sim)"
        Write-Host "  Add-on    : $($a.Path)"
        Write-Host "  Version   : $(Get-PackageVersion $a.Path)"
        $state = Get-PackageState $a.Path
        $color = 'Yellow'
        if ($state -eq 'Patched') { $color = 'Green' }
        Write-Host '  Status    : ' -NoNewline
        Write-Host $state -ForegroundColor $color
        Write-Host ''
    }
}

function Invoke-Apply([bool]$Interactive) {
    if (Test-SimRunning) { Write-Err 'Microsoft Flight Simulator is running. Close it completely and try again.'; return $false }
    $addons = Get-AddonsForAction $Interactive
    if ($null -eq $addons) { return $false }
    $ok = $true
    foreach ($a in $addons) {
        $pkg = $a.Path
        Write-Host "  Add-on: $pkg"
        $version = Get-PackageVersion $pkg
        if ($TestedVersions -notcontains $version) { Write-Warn "Version $version has not been tested. It is only patched if the code matches exactly." }
        $indexPath = Join-Path $pkg $IndexRelPath
        $js = Read-Latin1 $indexPath
        if ($js.Contains($PatchMarker)) { Write-Ok 'Already patched. Nothing to do.'; continue }
        $newJs = Get-PatchPlan $js
        if ($null -eq $newJs) {
            Write-Warn 'The code this patch replaces was not found. Navigraph may have changed or fixed it in this version. Nothing was changed.'
            $ok = $false
            continue
        }
        $backupDir = $null
        try {
            $backupDir = New-FixBackup $pkg
            Write-Ok "Backup saved to $backupDir"
            Write-Latin1 $indexPath $newJs
            Update-Manifest $pkg (Update-Layout $pkg)
            Test-PatchedPackage $pkg
            Write-Ok 'Patch applied. Start the simulator, open SimBrief Dispatch and sign in again.'
            Write-Info 'A Navigraph Hub update of the add-on removes the patch. Apply it again after updating.'
        } catch {
            Write-Err "Could not apply the patch: $($_.Exception.Message)"
            if ($backupDir) {
                try { Restore-FixBackup $pkg $backupDir; Write-Warn 'The original files were restored.' }
                catch { Write-Err "Restoring the backup failed too. Reinstall the add-on with Navigraph Hub. ($($_.Exception.Message))" }
            }
            $ok = $false
        }
    }
    return $ok
}

function Invoke-Revert([bool]$Interactive) {
    if (Test-SimRunning) { Write-Err 'Microsoft Flight Simulator is running. Close it completely and try again.'; return $false }
    $addons = Get-AddonsForAction $Interactive
    if ($null -eq $addons) { return $false }
    $ok = $true
    foreach ($a in $addons) {
        $pkg = $a.Path
        Write-Host "  Add-on: $pkg"
        if (-not (Read-Latin1 (Join-Path $pkg $IndexRelPath)).Contains($PatchMarker)) { Write-Ok 'The add-on is not patched. Nothing to do.'; continue }
        $backupDir = Find-LatestBackup $pkg
        if (-not $backupDir) {
            Write-Warn "No backup was found in $BackupRoot."
            Write-Warn 'Reinstall SimBrief Dispatch with Navigraph Hub to get the original files back.'
            $ok = $false
            continue
        }
        try {
            Restore-FixBackup $pkg $backupDir
            Write-Ok "Original files restored from $backupDir"
        } catch {
            Write-Err "Could not restore the backup: $($_.Exception.Message)"
            $ok = $false
        }
    }
    return $ok
}

# ------------------------------------------------------------------ entry point

if ($Action -ne 'Menu') {
    Show-Banner
    $result = $true
    switch ($Action) {
        'Apply'  { $result = Invoke-Apply $false }
        'Revert' { $result = Invoke-Revert $false }
        'Status' { Show-Status }
    }
    Write-Host ''
    if ($result) { exit 0 } else { exit 1 }
}

while ($true) {
    try { Clear-Host } catch { }
    Show-Banner
    Show-Status
    Write-Host '  1- Apply Patch'
    Write-Host '  2- Revert Patch'
    Write-Host '  3- Select add-on folder manually'
    Write-Host '  4- Exit'
    Write-Host ''
    $choice = Read-Host '  Select an option'
    if ($null -eq $choice) { break }
    Write-Host ''
    switch ($choice.Trim()) {
        '1' { [void](Invoke-Apply $true) }
        '2' { [void](Invoke-Revert $true) }
        '3' { [void](Select-AddonInteractively) }
        '4' { exit 0 }
        default { Write-Warn 'Please type 1, 2, 3 or 4.' }
    }
    Write-Host ''
    $wait = Read-Host '  Press Enter to return to the menu'
    if ($null -eq $wait) { break }
}
