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

  사람 손 단계: WSL 설치(관리자 권한·재부팅), 배포판 첫 실행의 사용자 만들기, GitHub 기기 코드 승인(또는 deploy key 등록),
  Claude 로그인, Slack 토큰.

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
  [switch]$NoBrowser
)

Set-StrictMode -Version 3.0
$ErrorActionPreference = 'Stop'
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

# ---- 1 Windows·WSL 확인 ----
if ($env:OS -ne 'Windows_NT') { Exit-Install 'Windows에서 돌리는 설치기입니다. Linux는 scripts/install.sh, Mac은 scripts/install.sh' }
if (-not (Get-Command wsl.exe -ErrorAction SilentlyContinue)) {
  Exit-Install "WSL이 없습니다. 관리자 PowerShell에서 'wsl --install -d $Distro' 뒤 재부팅하고, 배포판을 한 번 열어 사용자를 만든 다음 이 설치기를 다시 돌리세요"
}
& wsl.exe --status *> $null
if ($LASTEXITCODE -ne 0) {
  Exit-Install "WSL이 켜져 있지 않습니다. 관리자 PowerShell에서 'wsl --install -d $Distro' 뒤 재부팅하세요"
}

$distros = Get-WslLine @('-l', '-q')
if ($distros -notcontains $Distro) {
  $have = if ($distros.Count -gt 0) { $distros -join ', ' } else { '없음' }
  Exit-Install "WSL 배포판 '$Distro'가 없습니다(있는 것: $have). 'wsl --install -d $Distro'로 설치하고 한 번 열어 사용자를 만든 뒤 다시 돌리세요. 다른 배포판은 -Distro <이름>"
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
# 배포판 첫 실행에서 만든 사용자(보통 uid 1000). root면 사용자를 만들지 않은 것이다.
$wslUser = Get-WslLine @('-d', $Distro, '--', 'id', '-un') | Select-Object -First 1
if (-not $wslUser) { Exit-Install "배포판 '$Distro'의 기본 사용자를 읽지 못했습니다" }
if ($wslUser -eq 'root') {
  Exit-Install "배포판 '$Distro'의 기본 사용자가 root입니다. 배포판을 한 번 열어 사용자를 만든 뒤 다시 돌리세요"
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
