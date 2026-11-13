<#
.SYNOPSIS
  Aivengers docker 서버 설치기 — Windows(WSL2) 래퍼(AIV-578, 계획 AIV-574 7절 U9).

.DESCRIPTION
  WSL2 확인 → 배포판(기본 Ubuntu-24.04)의 systemd 켜기 → 권한이 필요한 준비를 root로(회사 인증서 신뢰, apt 패키지,
  docker 데몬, docker 그룹) → GitHub 인증(gh 기기 인증 또는 deploy key) → 배포판 안에 저장소 받기 → 배포판 안에서
  scripts/install.sh 실행(Linux면 scripts/install-linux.sh로 넘어가 이미지 빌드 → 서버 기동 → 헬스).
  끝나면 Windows 브라우저로 http://127.0.0.1:45180 을 연다(WSL 포트 전달).
  데이터는 WSL 배포판 안 ~/.local/share/aivengers(XDG)에 둔다. C:\(/mnt/c)에는 두지 않는다(SQLite 잠금·속도·권한).
  접속 전용 앱·호스트 실행기는 아직 없다(U9b).

  비대화형(AIV-594): root가 필요한 단계는 'wsl -u root'로 돌려 sudo 비밀번호를 묻지 않는다. WSL 안 설치기는 AIV_SUDO='sudo -n'으로
  돌아 혹시 sudo가 필요해도 기다리지 않고 실패한다. 에이전트(Claude Code 등)가 백그라운드로 돌려도 멈춰 서지 않는다.
  GitHub 로그인은 화면에 8자리 일회용 코드를 찍고 사람이 https://github.com/login/device 에서 승인할 때까지 기다린다(최대 약 15분).

  WSL부터(AIV-616): WSL이 없으면 스스로 관리자 권한을 요청(UAC)해 'wsl --install --no-distribution'(안 되면 기능 켜기)을 한다.
  재부팅이 필요하면 로그온 때 한 번 도는 이어 하기(HKCU RunOnce)를 등록하고 종료 코드 3010으로 끝난다(-RebootNow면 바로 재부팅,
  창에서 직접 돌렸으면 물어봄). 다시 로그인하면 PowerShell 창이 떠서 같은 옵션으로 설치를 이어 간다(Claude 대화가 필요 없음).
  배포판이 없으면 '--no-launch --web-download'로 깔고, 첫 실행 질문 없이 Windows 사용자 이름으로 사용자를 만들어 기본 사용자로 둔다.
  끝나면 Claude 로그인 터미널 창을 띄운다(이미 로그인돼 있으면 건너뜀). 기록: %LOCALAPPDATA%\Aivengers\logs\install-*.log

  사람 손 단계(화면 승인뿐): UAC '예'(WSL을 처음 켤 때), 재부팅(WSL 기능이 처음 켜질 때만), GitHub 기기 코드 승인(또는 deploy key 등록),
  Claude 로그인 브라우저 승인, Slack 토큰(웹 설정).

.EXAMPLE
  powershell -ExecutionPolicy Bypass -File install.ps1
.EXAMPLE
  powershell -ExecutionPolicy Bypass -File install.ps1 -Distro Ubuntu-24.04 -CaFile C:\certs\corp-root.pem
.EXAMPLE
  powershell -ExecutionPolicy Bypass -File install.ps1 -DryRun
.EXAMPLE
  powershell -ExecutionPolicy Bypass -File install.ps1 -DeployKey
#>
[CmdletBinding()]
param(
  # WSL 배포판 이름(wsl -l -v). 없으면 설치 명령을 안내하고 멈춘다.
  [string]$Distro = $(if ($env:AIVENGERS_WSL_DISTRO) { $env:AIVENGERS_WSL_DISTRO } else { 'Ubuntu-24.04' }),
  # 저장소 주소와 가지. 비공개 저장소라 배포판 안 git이 GitHub 로그인을 묻는다.
  [string]$RepoUrl = $(if ($env:AIVENGERS_REPO_URL) { $env:AIVENGERS_REPO_URL } else { 'https://github.com/Injae-Lee/Aivengers.git' }),
  [string]$Branch = 'main',
  # 서버 포트(127.0.0.1에만 게시).
  [ValidateRange(1024, 65535)][int]$Port = 45180,
  # 회사 TLS 검사 루트 인증서 PEM(Windows 경로). 주면 시스템 CA 묶음 대신 이 파일을 봇 컴퓨터·서버가 믿는다.
  # 주지 않으면 Windows 신뢰 루트 저장소(LocalMachine·CurrentUser Root)를 PEM으로 내보내 쓴다(Mac의 시스템 키체인 내보내기와 같은 뜻).
  [string]$CaFile = '',
  # Windows 신뢰 루트 내보내기를 끈다(-CaFile도 없으면 WSL 시스템 CA 묶음만).
  [switch]$NoWindowsCa,
  # 접속 앱 설정(%LOCALAPPDATA%\Aivengers\desktop.json)에 호스트 실행기를 켠다("hostRunner": true). 기본은 끔.
  [switch]$HostRunner,
  # gh 로그인 대신 읽기 전용 deploy key(배포판 안 ~/.local/state/aivengers/deploy_key). 처음에는 공개 키를 보여 주고 멈춘다
  # (종료 코드 2). 저장소 주인이 Deploy keys에 넣은 뒤 같은 명령을 다시 돌린다.
  [switch]$DeployKey,
  # 확인만 하고 바꾸지 않는다(WSL 안 설치기도 --dry-run).
  [switch]$DryRun,
  # 끝나고 브라우저를 열지 않는다.
  [switch]$NoBrowser,
  # 끝에 Claude 로그인 창을 띄우지 않는다.
  [switch]$NoClaudeLogin,
  # WSL을 켜느라 재부팅이 필요하면 묻지 않고 30초 뒤 재부팅한다(이어 하기는 그대로 등록).
  [switch]$RebootNow,
  # 내부용: 재부팅 뒤 RunOnce가 붙인다(이어 하기 표시만).
  [switch]$Resume,
  # 내부용: UAC로 올라간 관리자 프로세스가 WSL 기능만 켜고 끝난다.
  [switch]$ElevatedWslSetup
)

Set-StrictMode -Version 3.0
$ErrorActionPreference = 'Stop'
# 재부팅 이어 하기에 같은 옵션을 다시 붙이려고 남긴다(함수 안의 $PSBoundParameters는 그 함수 것이다).
$BoundArgs = $PSBoundParameters
# WSL 안 출력(UTF-8)과 한국어 안내가 깨지지 않게. WSL_UTF8=1이면 wsl.exe 자체 출력도 UTF-8이다.
[Console]::OutputEncoding = [System.Text.Encoding]::UTF8
$env:WSL_UTF8 = '1'

function Write-Step([string]$Message) { Write-Host "==> $Message" }
# exit 대신 throw: 'irm … | iex'로 돌려도 사용자의 PowerShell 창을 닫지 않는다(-File이면 종료 코드 1).
function Exit-Install([string]$Message) {
  Write-Host "실패: $Message" -ForegroundColor Red
  throw "Aivengers 설치 중단: $Message"
}

# wsl.exe의 목록 출력은 UTF-16이라 PowerShell에서 글자 사이에 NUL이 낀다. 지우고 줄로 나눈다.
function Get-WslLine([string[]]$WslArgs) {
  $out = & wsl.exe @WslArgs 2>$null
  if ($null -eq $out) { return @() }
  return @($out | ForEach-Object { ($_ -replace "`0", '').Trim() } | Where-Object { $_ -ne '' })
}

# 배포판 안에서 bash 스크립트를 돌린다. 따옴표가 PowerShell·wsl.exe를 거치며 바뀌지 않게 base64로 넘긴다.
function Invoke-InDistro([string]$Script, [switch]$AsRoot) {
  $bytes = [System.Text.Encoding]::UTF8.GetBytes(($Script -replace "`r`n", "`n"))
  $b64 = [System.Convert]::ToBase64String($bytes)
  $wslArgs = @('-d', $Distro)
  if ($AsRoot) { $wslArgs += @('-u', 'root') }
  $wslArgs += @('--', 'bash', '-c', "echo $b64 | base64 -d | bash")
  # 출력은 화면으로만 보낸다(함수 반환값에 섞이지 않게).
  & wsl.exe @wslArgs | Out-Host
  return $LASTEXITCODE
}

# 배포판 안 bash 스크립트의 표준 출력(줄 목록)을 받는다(기본 사용자).
function Get-InDistroLine([string]$Script) {
  $bytes = [System.Text.Encoding]::UTF8.GetBytes(($Script -replace "`r`n", "`n"))
  $b64 = [System.Convert]::ToBase64String($bytes)
  return Get-WslLine @('-d', $Distro, '--', 'bash', '-c', "echo $b64 | base64 -d | bash")
}

# bash 작은따옴표 문자열로 감싼다.
function ConvertTo-BashQuoted([string]$Value) { return "'" + ($Value -replace "'", "'\''") + "'" }

# Windows 신뢰 루트 저장소의 인증서를 PEM 한 파일로 쓴다(회사 TLS 검사 루트가 여기 들어 있다. AIV-594·611).
# 공개 인증서뿐이라 비밀값이 아니다. 같은 지문은 한 번만, 줄은 64자, 줄바꿈은 LF(WSL·OpenSSL이 읽음).
function Export-WindowsRootCa([string]$Dest) {
  $seen = @{}
  $sb = New-Object System.Text.StringBuilder
  foreach ($store in @('Cert:\LocalMachine\Root', 'Cert:\CurrentUser\Root')) {
    foreach ($c in @(Get-ChildItem -Path $store -ErrorAction SilentlyContinue)) {
      if (-not $c.RawData -or $seen.ContainsKey($c.Thumbprint)) { continue }
      $seen[$c.Thumbprint] = $true
      $b64 = [System.Convert]::ToBase64String($c.RawData)
      [void]$sb.Append("-----BEGIN CERTIFICATE-----`n")
      for ($i = 0; $i -lt $b64.Length; $i += 64) { [void]$sb.Append($b64.Substring($i, [Math]::Min(64, $b64.Length - $i)) + "`n") }
      [void]$sb.Append("-----END CERTIFICATE-----`n")
    }
  }
  if ($seen.Count -eq 0) { return 0 }
  New-Item -ItemType Directory -Force -Path (Split-Path -Parent $Dest) | Out-Null
  [System.IO.File]::WriteAllText($Dest, $sb.ToString(), (New-Object System.Text.UTF8Encoding($false)))
  return $seen.Count
}

# 접속 앱 설정(%LOCALAPPDATA%\Aivengers\desktop.json, docs/desktop-client-mode.md 'Windows')에 이 설치의 자리를 쓴다.
# 있는 다른 키(openAtLogin·clientPort 등)는 그대로 두고 mode·dataDir·repoDir·node(있을 때)·hostRunner(켰을 때)만 바꾼다.
function Write-DesktopConfig([string]$File, [hashtable]$Values) {
  $obj = [ordered]@{}
  if (Test-Path -LiteralPath $File -PathType Leaf) {
    try {
      $old = Get-Content -LiteralPath $File -Raw -Encoding UTF8 | ConvertFrom-Json
      foreach ($p in $old.PSObject.Properties) { $obj[$p.Name] = $p.Value }
    } catch {
      Copy-Item -LiteralPath $File -Destination "$File.broken" -Force
      Write-Step "desktop.json을 읽지 못해 $File.broken 으로 남기고 새로 씁니다"
    }
  }
  foreach ($k in $Values.Keys) { $obj[$k] = $Values[$k] }
  New-Item -ItemType Directory -Force -Path (Split-Path -Parent $File) | Out-Null
  $json = ($obj | ConvertTo-Json -Depth 5)
  [System.IO.File]::WriteAllText($File, $json + "`n", (New-Object System.Text.UTF8Encoding($false)))
}

# Windows의 Node 24 이상(호스트 실행기용). 없으면 빈 값(앱이 내장 Node를 씀).
function Find-WindowsNode24 {
  $cmd = Get-Command node.exe -ErrorAction SilentlyContinue | Select-Object -First 1
  if (-not $cmd) { return '' }
  $v = (& $cmd.Source -v 2>$null) -replace '^v', ''
  $major = 0
  if ($v -and [int]::TryParse(($v -split '\.')[0], [ref]$major) -and $major -ge 24) { return $cmd.Source }
  return ''
}

# ---- WSL 켜기·재부팅 이어 하기·사용자 만들기(AIV-616) ----
# 설치기 자리(%LOCALAPPDATA%\Aivengers): 기록·이어 하기 사본·desktop.json
$AppDir = Join-Path $(if ($env:LOCALAPPDATA) { $env:LOCALAPPDATA } elseif ($env:USERPROFILE) { Join-Path $env:USERPROFILE 'AppData\Local' } else { [System.IO.Path]::GetTempPath() }) 'Aivengers'

# WSL이 돌 수 있는지(기능 켜짐·재부팅 끝). 없는 기능이면 wsl --status가 0이 아니다.
function Test-WslReady {
  if (-not (Get-Command wsl.exe -ErrorAction SilentlyContinue)) { return $false }
  & wsl.exe --status *> $null
  return ($LASTEXITCODE -eq 0)
}

# 사람이 창에서 직접 돌리는지(에이전트의 백그라운드 실행이면 입출력이 넘겨져 있다).
function Test-InteractiveConsole {
  return ([Environment]::UserInteractive -and -not [Console]::IsInputRedirected -and -not [Console]::IsOutputRedirected)
}

# 이 실행의 옵션을 다시 붙일 인자 문자열(내부용 스위치는 뺌).
function Get-PassThroughArg {
  $skip = @('Resume', 'RebootNow', 'ElevatedWslSetup', 'DryRun')
  $parts = @()
  foreach ($k in $script:BoundArgs.Keys) {
    if ($skip -contains $k) { continue }
    $v = $script:BoundArgs[$k]
    if ($v -is [System.Management.Automation.SwitchParameter]) { if ($v.IsPresent) { $parts += "-$k" } }
    else { $parts += "-$k `"$($v -replace '"', '')`"" }
  }
  return ($parts -join ' ')
}

# UAC로 같은 스크립트를 관리자 권한으로 띄워 WSL 기능만 켠다. 종료 코드(1223 = UAC 거절).
function Invoke-ElevatedWslSetup {
  if (-not $PSCommandPath) { Exit-Install "파일로 받아 '-File'로 돌려야 관리자 단계를 띄울 수 있습니다(irm … -OutFile 뒤 powershell -File)" }
  try {
    $p = Start-Process -FilePath 'powershell.exe' -Verb RunAs -Wait -PassThru `
      -ArgumentList "-NoProfile -ExecutionPolicy Bypass -File `"$PSCommandPath`" -ElevatedWslSetup"
    return $p.ExitCode
  } catch {
    Write-Host "관리자 권한을 받지 못했습니다: $($_.Exception.Message)"
    return 1223
  }
}

# 재부팅 뒤 로그온 때 한 번 도는 이어 하기(HKCU RunOnce → resume.cmd → 이 스크립트 사본 -Resume). RunOnce 값은 260자 한도라 cmd로 감싼다.
function Register-ResumeAfterReboot {
  $copy = Join-Path $AppDir 'install.ps1'
  if ($PSCommandPath -and ((Resolve-Path -LiteralPath $PSCommandPath).Path -ne $copy)) {
    New-Item -ItemType Directory -Force -Path $AppDir | Out-Null
    Copy-Item -LiteralPath $PSCommandPath -Destination $copy -Force
  }
  $cmd = Join-Path $AppDir 'resume.cmd'
  $line = "powershell.exe -NoProfile -ExecutionPolicy Bypass -NoExit -File `"$copy`" $(Get-PassThroughArg) -Resume"
  $text = "@echo off`r`nchcp 65001 >nul`r`ntitle Aivengers 설치 이어 하기`r`n$line`r`n"
  [System.IO.File]::WriteAllText($cmd, $text, (New-Object System.Text.UTF8Encoding($false)))
  $key = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\RunOnce'
  if (-not (Test-Path $key)) { New-Item -Path $key -Force | Out-Null }
  New-ItemProperty -Path $key -Name 'AivengersInstall' -Value "`"$cmd`"" -PropertyType String -Force | Out-Null
  Write-Step "이어 하기 등록: $cmd (로그온 때 한 번)"
}

# Windows 사용자 이름 → 리눅스 사용자 이름(소문자·영숫자·_-, 32자, 예약 이름 피함). 못 쓰면 aivengers.
function ConvertTo-LinuxUserName([string]$Name) {
  $n = ("$Name".ToLowerInvariant() -replace '[^a-z0-9_-]', '')
  $n = $n -replace '^[^a-z_]+', ''
  if ($n.Length -gt 32) { $n = $n.Substring(0, 32) }
  if (-not $n -or @('root', 'docker', 'daemon', 'bin', 'sys', 'nobody', 'ubuntu', 'admin', 'sudo') -contains $n) { $n = 'aivengers' }
  return $n
}

# 배포판 사용자 만들기(root로). 첫 사용자라 uid 1000(봇 컴퓨터와 같음). 비밀번호는 잠가 둔다(관리는 'wsl -u root').
$NewUserScript = @'
set -eu
U=__USER__
if ! id "$U" >/dev/null 2>&1; then
  useradd -m -s /bin/bash -G sudo "$U"
fi
f=${AIV_WSL_CONF:-/etc/wsl.conf}
touch "$f"
if grep -q '^\[user\]' "$f"; then
  sed -i '/^\[user\]/,/^\[/{/^default[[:space:]]*=/d}' "$f"
  sed -i "/^\[user\]/a default=$U" "$f"
else
  printf '\n[user]\ndefault=%s\n' "$U" >> "$f"
fi
echo "==> 사용자 $U (uid $(id -u "$U")), 기본 사용자로 둠"
'@

# Claude 로그인 창(배포판 터미널). docker exec -it라 표준 입력이 터미널이어야 해서 스크립트를 파일로 쓴 뒤 bash로 돌린다.
$ClaudeLoginScript = @'
echo "Aivengers: Claude 로그인"
echo "아래 주소를 브라우저에서 열어 승인하고, 받은 코드를 이 창에 붙여 넣으세요."
docker exec -it aivengers-server-1 claude auth login --claudeai
echo
docker exec aivengers-server-1 claude auth status 2>/dev/null | grep -E 'loggedIn' || true
read -r -p "끝나면 Enter로 이 창을 닫으세요 " _
'@

function Open-ClaudeLoginWindow {
  $logged = Get-InDistroLine "docker exec aivengers-server-1 claude auth status 2>/dev/null | grep -Eq '`"loggedIn`"[[:space:]]*:[[:space:]]*true' && echo yes || echo no"
  if ($logged -contains 'yes') { Write-Step 'Claude 로그인 돼 있음(건너뜀)'; return }
  $b64 = [System.Convert]::ToBase64String([System.Text.Encoding]::UTF8.GetBytes(($ClaudeLoginScript -replace "`r`n", "`n")))
  Start-Process -FilePath 'wsl.exe' -ArgumentList "-d $Distro -- bash -c `"echo $b64 | base64 -d > /tmp/aivengers-claude-login.sh; exec bash /tmp/aivengers-claude-login.sh`""
  Write-Step 'Claude 로그인 창을 띄웠습니다. 그 창의 주소를 브라우저에서 열어 승인하고 코드를 붙여 넣으세요'
  Write-Host 'CLAUDE_LOGIN_WINDOW: 새 터미널 창에서 로그인을 마치세요'
}

# ---- 0 관리자 단계(UAC로 올라온 프로세스, AIV-616) ----
# WSL 기능만 켜고 끝난다. 0 = 됨(재부팅 필요 여부는 부른 쪽이 wsl --status로 판단), 그 밖 = 실패.
if ($ElevatedWslSetup) {
  $log = Join-Path $AppDir ("logs\install-admin-{0:yyyyMMdd-HHmmss}.log" -f (Get-Date))
  New-Item -ItemType Directory -Force -Path (Split-Path -Parent $log) | Out-Null
  Start-Transcript -Path $log -Append | Out-Null
  try {
    Write-Step 'WSL 켜기(관리자): wsl --install --no-distribution'
    & wsl.exe --install --no-distribution
    if ($LASTEXITCODE -ne 0) {
      # 옛 Windows 10은 --no-distribution을 모른다. 기능 두 개를 직접 켠다(재부팅 뒤 wsl --update).
      Write-Step 'wsl --install이 실패해 Windows 기능을 직접 켭니다(Microsoft-Windows-Subsystem-Linux, VirtualMachinePlatform)'
      foreach ($f in @('Microsoft-Windows-Subsystem-Linux', 'VirtualMachinePlatform')) {
        & dism.exe /online /enable-feature /featurename:$f /all /norestart
        # 3010 = 켰고 재부팅 필요
        if ($LASTEXITCODE -ne 0 -and $LASTEXITCODE -ne 3010) { Write-Host "실패: $f 기능을 켜지 못했습니다(dism $LASTEXITCODE)"; exit 1 }
      }
    }
    try { & wsl.exe --update | Out-Null } catch { Write-Host "wsl --update 건너뜀: $($_.Exception.Message)" }
    exit 0
  } finally { Stop-Transcript | Out-Null }
}

# 설치 기록(에이전트·사람이 나중에 읽음). 비밀값은 찍지 않는다(gh 토큰은 배포판 안에만 있음).
New-Item -ItemType Directory -Force -Path (Join-Path $AppDir 'logs') | Out-Null
$LogFile = Join-Path $AppDir ("logs\install-{0:yyyyMMdd-HHmmss}.log" -f (Get-Date))
Start-Transcript -Path $LogFile -Append | Out-Null
Write-Step "설치 기록: $LogFile"
if ($Resume) { Write-Step '재부팅 뒤 설치를 이어 갑니다' }

# ---- 1 Windows·WSL 확인(없으면 켜기, AIV-616) ----
if ($env:OS -ne 'Windows_NT') { Exit-Install 'Windows에서 돌리는 설치기입니다. Linux는 scripts/install.sh, Mac은 scripts/install.sh' }
if ([Environment]::OSVersion.Version.Build -lt 19041) {
  Exit-Install "Windows 10 2004(빌드 19041) 이상이 필요합니다(지금 $([Environment]::OSVersion.Version)). Windows 업데이트 뒤 다시 돌리세요"
}

if (-not (Test-WslReady)) {
  if ($DryRun) { Write-Step '(dry-run) WSL이 없음 → 관리자 권한 요청(UAC) → wsl --install --no-distribution → 필요하면 재부팅·이어 하기 등록' }
  else {
    Write-Step 'WSL이 꺼져 있습니다. 관리자 권한을 요청합니다 — 화면의 사용자 계정 컨트롤(UAC)에서 "예"를 누르세요'
    $code = Invoke-ElevatedWslSetup
    if ($code -ne 0) { Exit-Install "WSL을 켜지 못했습니다(관리자 단계 종료 코드 $code). UAC에서 '아니요'를 눌렀다면 다시 돌리세요. 기록: $(Join-Path $AppDir 'logs')" }
    if (-not (Test-WslReady) -and $Resume) {
      # 재부팅을 한 번 했는데도 안 되면 다시 재부팅을 돌지 않고 멈춘다(가상화 꺼짐 등).
      Exit-Install "재부팅 뒤에도 WSL이 돌지 않습니다. BIOS 가상화(VT-x/AMD-V)가 켜져 있는지, 'wsl --status' 출력을 확인하세요"
    }
    if (-not (Test-WslReady)) {
      # 기능을 처음 켰으면 재부팅해야 WSL이 돈다. 로그온 때 이어 하도록 등록하고 끝낸다.
      Register-ResumeAfterReboot
      Write-Step '재부팅이 필요합니다. 다시 로그인하면 PowerShell 창이 떠서 설치를 저절로 이어 갑니다(Claude 대화 없이)'
      Stop-Transcript | Out-Null
      if ($RebootNow) {
        & shutdown.exe /r /t 30 /c 'Aivengers 설치: WSL을 켜려고 재부팅합니다. 다시 로그인하면 설치가 이어집니다'
      } elseif (Test-InteractiveConsole) {
        $ans = Read-Host '지금 재부팅할까요? (y/N)'
        if ($ans -match '^(y|yes|예|ㅇ)$') { & shutdown.exe /r /t 10 /c 'Aivengers 설치: 재부팅 뒤 이어집니다' }
      }
      Write-Host 'REBOOT_REQUIRED: 재부팅 뒤 로그인하면 설치가 이어집니다(종료 코드 3010)'
      exit 3010
    }
  }
}

$distros = Get-WslLine @('-l', '-q')
if ($distros -notcontains $Distro) {
  if ($DryRun) { Write-Step "(dry-run) wsl --install -d $Distro --no-launch --web-download → 사용자 만들기" }
  else {
    Write-Step "WSL 배포판 $Distro 설치(첫 실행 창 없이, 몇 분)"
    & wsl.exe --install -d $Distro --no-launch --web-download
    if ($LASTEXITCODE -ne 0) {
      # 옛 wsl.exe는 --web-download를 모를 수 있다(스토어로 받음).
      & wsl.exe --install -d $Distro --no-launch
    }
    $distros = Get-WslLine @('-l', '-q')
    if ($distros -notcontains $Distro) { Exit-Install "배포판 $Distro 를 설치하지 못했습니다. 'wsl --list --online'으로 이름을 확인하거나 -Distro <이름>" }
  }
}
if ($DryRun -and ((-not (Test-WslReady)) -or ($distros -notcontains $Distro))) {
  Write-Step '(dry-run) WSL·배포판이 아직 없어 나머지(배포판 안 확인)는 실제 설치 때 합니다'
  Stop-Transcript | Out-Null
  exit 0
}

# 버전(1·2). 'wsl -l -v'의 마지막 칸.
$verLine = Get-WslLine @('-l', '-v') | Where-Object { ($_ -replace '^\*\s*', '') -match "^$([regex]::Escape($Distro))\s" } | Select-Object -First 1
if ($verLine -and ($verLine -split '\s+')[-1] -eq '1') {
  if ($DryRun) { Write-Step "(dry-run) wsl --set-version $Distro 2" }
  else {
    Write-Step "$Distro 를 WSL2로 바꿉니다(몇 분)"
    & wsl.exe --set-version $Distro 2
    if ($LASTEXITCODE -ne 0) { Exit-Install "WSL2로 바꾸지 못했습니다. 'wsl --set-version $Distro 2'를 직접 돌려 보세요" }
  }
}
Write-Step "WSL 배포판 $Distro (WSL2)"

# ---- 2 systemd(docker 데몬용) ----
$systemdCheck = @'
grep -Eqs '^[[:space:]]*systemd[[:space:]]*=[[:space:]]*true' /etc/wsl.conf
'@
if ((Invoke-InDistro $systemdCheck -AsRoot) -ne 0) {
  if ($DryRun) { Write-Step '(dry-run) /etc/wsl.conf에 [boot] systemd=true 넣고 배포판 다시 시작' }
  else {
    Write-Step 'systemd를 켭니다(/etc/wsl.conf [boot] systemd=true) 뒤 배포판을 다시 시작'
    $enable = @'
set -e
f=/etc/wsl.conf
touch "$f"
if grep -q '^\[boot\]' "$f"; then
  sed -i '/^\[boot\]/a systemd=true' "$f"
else
  printf '\n[boot]\nsystemd=true\n' >> "$f"
fi
'@
    if ((Invoke-InDistro $enable -AsRoot) -ne 0) { Exit-Install '/etc/wsl.conf를 고치지 못했습니다' }
    & wsl.exe --terminate $Distro | Out-Null
    Start-Sleep -Seconds 3
  }
}

# ---- 3 기본 사용자 ----
# 배포판 첫 실행에서 만든 사용자(보통 uid 1000). root면(--no-launch로 깔아 첫 실행 질문을 건너뜀) 대화 없이 만든다(AIV-616):
# Windows 사용자 이름을 리눅스 규칙에 맞춘 이름, 비밀번호 없음(잠김. 관리 작업은 Windows에서 'wsl -u root'), /etc/wsl.conf [user] default.
$wslUser = Get-WslLine @('-d', $Distro, '--', 'id', '-un') | Select-Object -First 1
if (-not $wslUser) { Exit-Install "배포판 '$Distro'의 기본 사용자를 읽지 못했습니다" }
if ($wslUser -eq 'root') {
  $newUser = ConvertTo-LinuxUserName $env:USERNAME
  if ($DryRun) { Write-Step "(dry-run) 사용자 $newUser 만들기(uid 1000 자리), /etc/wsl.conf [user] default=$newUser" }
  else {
    Write-Step "배포판 사용자 $newUser 를 만듭니다(첫 실행 질문 없이)"
    $mkUser = $NewUserScript.Replace('__USER__', (ConvertTo-BashQuoted $newUser))
    if ((Invoke-InDistro $mkUser -AsRoot) -ne 0) { Exit-Install "사용자 $newUser 를 만들지 못했습니다" }
    & wsl.exe --terminate $Distro | Out-Null
    Start-Sleep -Seconds 3
    $wslUser = Get-WslLine @('-d', $Distro, '--', 'id', '-un') | Select-Object -First 1
    if ($wslUser -ne $newUser) { Exit-Install "기본 사용자가 $newUser 로 바뀌지 않았습니다(지금 '$wslUser'). /etc/wsl.conf의 [user] 절을 확인하세요" }
  }
}
Write-Step "WSL 사용자 $wslUser"

$wslCa = ''
if (-not $CaFile -and -not $NoWindowsCa) {
  # 회사 TLS 검사 루트는 보통 Windows 신뢰 루트에만 있다. 내보내 WSL 신뢰 목록·서버 컨테이너(host-ca.pem → SSL_CERT_FILE 묶음, AIV-611)에 넣는다.
  $winCa = Join-Path $(if ($env:LOCALAPPDATA) { $env:LOCALAPPDATA } else { $env:TEMP }) 'Aivengers\host-ca-windows.pem'
  if ($DryRun) { Write-Step "(dry-run) Windows 신뢰 루트 → $winCa" }
  else {
    $n = Export-WindowsRootCa $winCa
    if ($n -gt 0) { Write-Step "Windows 신뢰 루트 $n 개 → $winCa"; $CaFile = $winCa }
    else { Write-Step 'Windows 신뢰 루트를 읽지 못해 WSL 시스템 CA 묶음만 씁니다(회사망이면 -CaFile <PEM>)' }
  }
}
if ($CaFile) {
  if (-not (Test-Path -LiteralPath $CaFile -PathType Leaf)) { Exit-Install "-CaFile 파일이 없습니다: $CaFile" }
  $full = (Resolve-Path -LiteralPath $CaFile).Path
  # Windows 경로 → WSL 경로(/mnt/c/...). 읽기만 하므로 Windows 드라이브여도 된다(설치기가 데이터 폴더로 복사).
  $wslCa = Get-WslLine @('-d', $Distro, '--', 'wslpath', '-a', ($full -replace '\\', '/')) | Select-Object -First 1
  if (-not $wslCa) { Exit-Install "WSL 경로로 바꾸지 못했습니다: $full" }
}
$dryFlag = if ($DryRun) { '1' } else { '0' }

# ---- 4 준비(root, AIV-594 G2) ----
# sudo 비밀번호 없이 끝나게 권한이 필요한 일은 여기서 'wsl -u root'로 한다. 이미 돼 있으면 건너뛴다(멱등).
# - 회사 인증서: apt·git·gh가 회사 TLS 검사 너머 GitHub에 붙게 배포판 신뢰 목록에 더함
# - 패키지: install-linux.sh --install-docker가 까는 것과 같은 목록 + gh(GitHub 기기 인증)
# - docker 데몬 켜기(systemd), 기본 사용자를 docker 그룹에
$prep = @'
set -eu
DRY=__DRY__
USER_NAME=__USER__
CA=__CA__
act() { if [ "$DRY" = 1 ]; then echo "  (dry-run) $*"; else "$@"; fi; }
# 회사 인증서: update-ca-certificates는 파일 하나에 인증서 하나씩 받으므로 나눠 넣는다. 원본 사본과 같으면 건너뛴다.
if [ -n "$CA" ]; then
  dir=${AIV_CA_DIR:-/usr/local/share/ca-certificates/aivengers}
  src=${AIV_CA_SRC:-/etc/aivengers/host-ca-source.pem}
  if ! cmp -s "$CA" "$src" 2>/dev/null; then
    echo "==> 회사 인증서를 배포판 신뢰 목록에 더함($dir, $(grep -c -- '-----BEGIN CERTIFICATE-----' "$CA")개)"
    if [ "$DRY" = 1 ]; then
      echo "  (dry-run) $CA → $dir/host-NNN.crt, update-ca-certificates"
    else
      rm -rf "$dir"; mkdir -p "$dir" "$(dirname "$src")"
      awk -v d="$dir" '/-----BEGIN CERTIFICATE-----/ { n++; f = sprintf("%s/host-%03d.crt", d, n) } f { print > f } /-----END CERTIFICATE-----/ { close(f); f = "" }' "$CA"
      chmod 644 "$dir"/*.crt
      update-ca-certificates >/dev/null
      install -m 0644 "$CA" "$src"
    fi
  fi
fi
need=""
for p in git:git gh:gh curl:curl openssl:openssl sqlite3:sqlite3 ssh-keygen:openssh-client docker:docker.io; do
  command -v "${p%%:*}" >/dev/null 2>&1 || need="$need ${p#*:}"
done
docker compose version >/dev/null 2>&1 || need="$need docker-compose-v2"
docker buildx version >/dev/null 2>&1 || need="$need docker-buildx"
if [ -n "$need" ]; then
  echo "==> apt 설치(root):$need"
  act apt-get update -q
  # shellcheck disable=SC2086
  act env DEBIAN_FRONTEND=noninteractive apt-get install -y -q $need ca-certificates
fi
if systemctl cat docker.service >/dev/null 2>&1; then
  if ! systemctl is-active -q docker; then
    echo "==> docker 데몬 켜기(systemd)"
    act systemctl enable --now docker
  fi
elif [ "$DRY" = 0 ]; then
  echo "주의: docker.service가 없습니다(Docker Desktop 연동?). WSL 안 Docker Engine을 권합니다" >&2
fi
if getent group docker >/dev/null && ! id -nG "$USER_NAME" | tr ' ' '\n' | grep -qx docker; then
  echo "==> $USER_NAME 를 docker 그룹에 넣음"
  act usermod -aG docker "$USER_NAME"
fi
'@
$prep = $prep.Replace('__DRY__', $dryFlag).Replace('__USER__', (ConvertTo-BashQuoted $wslUser)).Replace('__CA__', (ConvertTo-BashQuoted $wslCa))
Write-Step '준비(root): 인증서·패키지·docker 데몬·docker 그룹'
if ((Invoke-InDistro $prep -AsRoot) -ne 0) { Exit-Install '준비 단계(root)가 실패했습니다. 위 출력을 확인하세요' }
# docker 그룹은 새 세션부터 적용된다. 기본 사용자가 아직 docker에 못 붙으면 배포판을 다시 시작한다(docker는 systemd가 다시 켬).
if (-not $DryRun -and (Invoke-InDistro 'docker info >/dev/null 2>&1') -ne 0) {
  Write-Step 'docker 그룹 적용을 위해 배포판을 다시 시작'
  & wsl.exe --terminate $Distro | Out-Null
  Start-Sleep -Seconds 3
}

# ---- 5 GitHub 인증(AIV-594 G3) → 저장소(배포판 안, XDG 데이터 폴더 옆) → 설치기 ----
# 인증: 이미 접근되면 그대로 / -DeployKey면 읽기 전용 deploy key / 아니면 gh 기기 인증(코드를 찍고 승인을 기다림).
# 토큰은 화면에 찍지 않는다(gh가 배포판 안 ~/.config/gh에 둠).
$install = @'
set -euo pipefail
REPO_URL=__REPO__
BRANCH=__BRANCH__
DRY=__DRY__
DEPLOY_KEY=__DEPLOYKEY__
INSTALL_ARGS=(__ARGS__)
export GIT_TERMINAL_PROMPT=0
SRC="${XDG_DATA_HOME:-$HOME/.local/share}/aivengers-src"
case "$SRC" in /mnt/[A-Za-z]/*) echo "실패: 저장소 자리 $SRC 가 Windows 드라이브입니다" >&2; exit 1 ;; esac
command -v git >/dev/null 2>&1 || { echo "실패: git이 없습니다(준비 단계 확인)" >&2; exit 1; }
SLUG=""
case "$REPO_URL" in https://github.com/*) SLUG=${REPO_URL#https://github.com/}; SLUG=${SLUG%.git} ;; esac
CLONE_URL=$REPO_URL
CLONE_OPTS=()

if [ -d "$SRC/.git" ] && git -C "$SRC" ls-remote -q origin HEAD >/dev/null 2>&1; then
  echo "==> GitHub 접근 확인(받은 저장소)"
elif [ "$DEPLOY_KEY" = 1 ]; then
  [ -n "$SLUG" ] || { echo "실패: -DeployKey는 https://github.com/<주인>/<저장소> 주소에서만 됩니다" >&2; exit 1; }
  state="${XDG_STATE_HOME:-$HOME/.local/state}/aivengers"
  key="$state/deploy_key"
  if [ ! -f "$key" ]; then
    if [ "$DRY" = 1 ]; then echo "  (dry-run) deploy key 만들기 $key"; exit 0; fi
    mkdir -p "$state"; chmod 700 "$state"
    ssh-keygen -q -t ed25519 -N "" -C "aivengers-wsl $(id -un)@$(hostname)" -f "$key"
  fi
  export GIT_SSH_COMMAND="ssh -i $key -o IdentitiesOnly=yes -o StrictHostKeyChecking=accept-new"
  CLONE_URL="git@github.com:$SLUG.git"
  if ! git ls-remote -q "$CLONE_URL" HEAD >/dev/null 2>&1; then
    echo "==> 아래 공개 키를 저장소 주인에게 보내 $SLUG 의 Deploy keys(읽기 전용)에 넣어 달라고 하세요. 넣은 뒤 같은 명령을 다시 돌립니다"
    cat "$key.pub"
    exit 2
  fi
  CLONE_OPTS=(--config "core.sshCommand=$GIT_SSH_COMMAND")
  echo "==> GitHub 접근 확인(deploy key)"
elif git ls-remote -q "$REPO_URL" HEAD >/dev/null 2>&1; then
  echo "==> GitHub 접근 확인"
elif [ -n "$SLUG" ]; then
  command -v gh >/dev/null 2>&1 || { echo "실패: gh가 없습니다(준비 단계 확인)" >&2; exit 1; }
  if ! gh auth status -h github.com >/dev/null 2>&1; then
    if [ "$DRY" = 1 ]; then echo "  (dry-run) GitHub 기기 인증(gh auth login --web) 뒤 저장소 받기"; exit 0; fi
    echo "==> GitHub 로그인: 아래 8자리 코드를 https://github.com/login/device 에 넣고 승인하세요(승인할 때까지 기다림, 약 15분)"
    # 표준 입력을 막아 gh가 Enter·질문을 기다리지 않게 한다. 배포판에서 브라우저를 못 열면 주소만 찍는다.
    command -v wslview >/dev/null 2>&1 || export GH_BROWSER=true
    gh auth login -h github.com --web --git-protocol https </dev/null
  fi
  gh auth setup-git -h github.com
  if ! gh repo view "$SLUG" --json name >/dev/null 2>&1; then
    echo "실패: $SLUG 저장소에 접근할 수 없습니다. 저장소 주인에게 초대를 받아(메일에서 수락) 다시 돌리거나 -DeployKey를 쓰세요" >&2
    exit 1
  fi
  echo "==> GitHub 로그인됨, 저장소 접근 확인"
else
  echo "실패: $REPO_URL 에 접근할 수 없습니다" >&2
  exit 1
fi

if [ -d "$SRC/.git" ]; then
  echo "==> 저장소 받기: $SRC"
  git -C "$SRC" fetch -q origin "$BRANCH"
  git -C "$SRC" checkout -q "$BRANCH"
  git -C "$SRC" merge --ff-only -q "origin/$BRANCH"
else
  echo "==> 저장소 받기(처음): $SRC"
  mkdir -p "$(dirname "$SRC")"
  git clone -q "${CLONE_OPTS[@]+"${CLONE_OPTS[@]}"}" --branch "$BRANCH" "$CLONE_URL" "$SRC"
fi
echo "==> 커밋: $(git -C "$SRC" log -1 --format='%h %s')"
cd "$SRC"
# sudo가 필요해져도 비밀번호를 기다리지 않고 실패하게(준비 단계에서 끝냈어야 함).
export AIV_SUDO="${AIV_SUDO:-sudo -n}"
exec bash scripts/install.sh "${INSTALL_ARGS[@]}"
'@
$installArgs = @('--install-docker', '--port', "$Port")
if ($wslCa) { $installArgs += @('--ca-file', $wslCa) }
if ($DryRun) { $installArgs += '--dry-run' }
$install = $install.Replace('__REPO__', (ConvertTo-BashQuoted $RepoUrl)).Replace('__BRANCH__', (ConvertTo-BashQuoted $Branch))
$install = $install.Replace('__DRY__', $dryFlag).Replace('__DEPLOYKEY__', $(if ($DeployKey) { '1' } else { '0' }))
$install = $install.Replace('__ARGS__', (($installArgs | ForEach-Object { ConvertTo-BashQuoted $_ }) -join ' '))

Write-Step 'WSL 안에서 GitHub 인증 → 저장소 받기 → 설치기(비밀번호를 묻지 않음, GitHub 승인은 기다림)'
$code = Invoke-InDistro $install
if ($code -eq 2) { Exit-Install 'deploy key를 저장소에 넣은 뒤 같은 명령을 다시 돌리세요(공개 키는 위 출력)' }
if ($code -ne 0) { Exit-Install "WSL 안 설치기가 실패했습니다(종료 코드 $code). 위 출력을 확인하세요" }

# ---- 6 접속 앱 설정(AIV-581·594) ----
# 접속 앱(Windows, --win 빌드)과 호스트 실행기가 읽는 자리. 앱은 이 설치기가 깔지 않는다(따로 빌드·복사).
# dataDir·repoDir는 WSL 공유 경로(\\wsl.localhost\<배포판>\...). 실행기는 의존성이 없어 repoDir의 packages/host-runner를 그대로 돌린다.
$cfgDir = Join-Path $(if ($env:LOCALAPPDATA) { $env:LOCALAPPDATA } else { Join-Path $env:USERPROFILE 'AppData\Local' }) 'Aivengers'
$cfgFile = Join-Path $cfgDir 'desktop.json'
$paths = Get-InDistroLine 'wslpath -w "${XDG_DATA_HOME:-$HOME/.local/share}/aivengers"; wslpath -w "${XDG_DATA_HOME:-$HOME/.local/share}/aivengers-src"'
if ($DryRun) { Write-Step "(dry-run) $cfgFile 에 mode·dataDir·repoDir·node 쓰기" }
elseif ($paths.Count -ge 2) {
  $vals = @{ mode = 'client'; dataDir = $paths[0]; repoDir = $paths[1] }
  $node = Find-WindowsNode24
  if ($node) { $vals['node'] = $node }
  if ($HostRunner) { $vals['hostRunner'] = $true }
  Write-DesktopConfig $cfgFile $vals
  Write-Step "접속 앱 설정: $cfgFile (dataDir $($paths[0]), repoDir $($paths[1])$(if ($node) { ", node $node" }))"
} else {
  Write-Step "주의: WSL 경로를 읽지 못해 $cfgFile 을 쓰지 않았습니다(접속 앱·실행기에만 필요)"
}

$url = "http://127.0.0.1:$Port"
Write-Step "끝. 브라우저: $url"
if (-not $DryRun -and -not $NoBrowser) { Start-Process $url }
# Claude 로그인(사람 손: 브라우저 승인·코드 붙여넣기). 새 터미널 창이라 에이전트가 대신 치지 않는다.
if (-not $DryRun -and -not $NoClaudeLogin) { Open-ClaudeLoginWindow }
Write-Host 'INSTALL_DONE'
Stop-Transcript | Out-Null
