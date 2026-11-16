# aivengers-install

Aivengers Desktop 부트스트랩 설치기. 초대받은 사람만 쓸 수 있습니다(본체 저장소는 비공개).

## 요약

- 터미널에서 한 줄을 실행하면 전제 조건을 갖추고 비공개 저장소를 받은 뒤, 저장소 안의 설치기 본체로 넘깁니다.
- 지원: macOS(Apple Silicon) `install.sh`, Windows(WSL2) `install.ps1`
- 에이전트(Claude Code)에 한 줄만 주고 설치: 아래 'Mac(에이전트용)'·'Windows(에이전트용)'

## Mac

터미널에서(관리자 계정). Homebrew·회사 인증서가 없어도 됩니다: 설치기가 Homebrew·Colima(docker)·서버·접속 앱·Claude 로그인 창까지 합니다.

```sh
curl -fsSL https://raw.githubusercontent.com/Injae-Lee/aivengers-install/main/install.sh | bash -s -- --docker --install-docker
```

- 서버는 Colima 안 docker로 뜨고 앱(`~/Applications/Aivengers Desktop.app`)은 거기에 붙기만 합니다. 브라우저 `http://127.0.0.1:45180`
- 회사 TLS 검사 인증서는 시스템 키체인에서 가져오고, 키체인이 비어 있으면 시스템 CA 묶음을 씁니다
- 사람 손(화면 승인뿐):

| 단계 | 언제 | 할 일 |
|---|---|---|
| Mac 비밀번호 | Homebrew가 없을 때만 | 'Aivengers 설치' 비밀번호 창(터미널에서 돌렸으면 터미널)에 이 Mac의 로그인 비밀번호 |
| GitHub | 처음 한 번 | 찍힌 8자리 코드를 https://github.com/login/device 에 넣고 승인(저장소 초대 필요, 초대 수락은 설치기가 함. 초대 대신 `--deploy-key`) |
| Claude | 설치 끝 | 저절로 뜨는 Terminal 창 'Aivengers: Claude 로그인'의 주소를 브라우저에서 승인하고 코드 붙여넣기 |

- 기록: `~/.aivengers/logs/bootstrap-*.log`, `install-*.log`
- 옵션: `--no-claude-login`, `--no-login-item`, `--colima-memory <GiB>`, `--deploy-key`, `--dir <경로>`, `--branch <이름>`
- 자세한 내용: 본체 저장소 `docs/install-mac.md`

### Mac(에이전트용)

사람이 Mac Claude Code에 붙여 넣는 한 줄:

```
https://github.com/Injae-Lee/aivengers-install 의 README 'Mac(에이전트용)' 절을 읽고 그대로 따라 Aivengers를 이 Mac에 설치해 줘.
```

에이전트가 할 일:

1. `uname -sm`이 `Darwin arm64`인지 봅니다. 아니면 "Apple Silicon Mac만 지원합니다"라고 말하고 멈춥니다
2. `curl -fsSL https://raw.githubusercontent.com/Injae-Lee/aivengers-install/main/install.sh | AIVENGERS_NO_TTY=1 bash -s -- --docker --install-docker`를 **백그라운드로** 실행하고 출력을 계속 읽습니다(처음은 30분 넘게 걸릴 수 있음). Homebrew·docker를 미리 깔지 않습니다(설치기가 함)
   - `SUDO_PASSWORD_DIALOG`가 보이면: "화면에 뜬 'Aivengers 설치' 비밀번호 창에 이 Mac의 로그인 비밀번호를 넣어 주세요"라고 말합니다. 창이 한 번 더 뜰 수 있습니다
   - `one-time code: XXXX-XXXX`가 보이면 그 코드와 https://github.com/login/device 를 사람에게 보여 주고 승인을 기다립니다(브라우저는 저절로 열림, 설치기가 스스로 이어 감, 약 15분 안)
   - `저장소에 접근할 수 없습니다`가 보이면 줄에 찍힌 GitHub 계정 이름을 알려 주고 "저장소 주인에게 이 계정의 초대를 부탁해 주세요. 초대가 오면 알려 주세요"라고 말합니다. 사람이 알려 주면 2번 명령을 그대로 다시 돌립니다(초대 수락은 설치기가 함)
   - 공개 키·`Deploy keys` 안내가 보이면(`--deploy-key`) 공개 키 한 줄을 사람에게 보여 주고 멈춥니다
3. `INSTALL_DONE`이 보이면 `==> 서버 응답 200`을 확인합니다. `CLAUDE_LOGIN_WINDOW`가 있으면 "새로 뜬 Terminal 창 'Aivengers: Claude 로그인'의 주소를 브라우저에서 열어 승인하고, 받은 코드를 그 창에 붙여 넣어 주세요"라고 말합니다. 로그인 명령을 대신 치지 않습니다
4. 사람이 로그인했다고 하면 아래를 돌려 `# · PASS/FAIL · 출력 한 줄` 표로 보고합니다
   - `curl -s -o /dev/null -w "%{http_code}" http://127.0.0.1:45180/api/auth/me` → `200`
   - `ls -d ~/Applications/"Aivengers Desktop.app"` → 있음
   - `DOCKER_CONTEXT=colima /opt/homebrew/bin/docker exec aivengers-server-1 claude auth status` → `"loggedIn": true`
5. 사람이 나중에 상태를 물으면 `~/.aivengers/logs`의 가장 새 `install-*.log`(없으면 `bootstrap-*.log`) 끝 30줄을 읽어 알려 줍니다

- 멈출 조건: 0 아닌 종료 코드이거나 `실패:`가 찍히면 고치려 하지 말고 마지막 30줄과 함께 멈춥니다(같은 명령을 다시 돌리면 이어 감)
- 금지: 비밀번호를 묻거나 대신 넣기(`sudo`를 직접 돌리지 않음), 토큰·키 파일 내용 출력(`~/.config/gh/hosts.yml`, `deploy-token`, `.credentials.json`, `deploy_key`), Docker Desktop 설치, 설치기 밖에서 Homebrew·Colima 따로 설치

## Windows

PowerShell에서(관리자 아님). WSL이 없어도 됩니다: 설치기가 WSL 켜기(UAC)·재부팅 이어 하기·Ubuntu 설치·사용자 만들기까지 합니다.

```powershell
irm https://raw.githubusercontent.com/Injae-Lee/aivengers-install/main/install.ps1 -OutFile $env:TEMP\aivengers-install.ps1
powershell -NoProfile -ExecutionPolicy Bypass -File $env:TEMP\aivengers-install.ps1
```

- WSL2 배포판 안에 Docker Engine을 깔고 서버를 docker로 띄웁니다. 접속 앱(서명 없는 exe, 본체 GitHub 릴리스)을 `%LOCALAPPDATA%\Programs\Aivengers Desktop`에 깔고 엽니다(앱을 못 받으면 브라우저 `http://127.0.0.1:45180`)
- 호스트 실행기(사용자 컴퓨터에서 일하는 봇)와 로그인할 때 앱 열기(크래시 때 다시 띄움)를 기본으로 켭니다. Git for Windows가 없으면 winget으로 깝니다
- sudo 비밀번호를 묻지 않습니다(권한이 필요한 일은 `wsl -u root`). 회사 TLS 검사 인증서는 Windows 신뢰 루트에서 가져옵니다
- 사람 손(화면 승인뿐):

| 단계 | 언제 | 할 일 |
|---|---|---|
| UAC | WSL이 꺼져 있을 때만 | 사용자 계정 컨트롤 창에서 '예' |
| 재부팅 | WSL 기능을 처음 켰을 때만 | 재부팅에 동의 → 다시 로그인하면 'Aivengers 설치 이어 하기' 창이 저절로 떠서 끝까지 감 |
| GitHub | 처음 한 번 | 찍힌 8자리 코드를 https://github.com/login/device 에 넣고 승인(저장소 초대 필요, 초대 대신 `-DeployKey`) |
| Claude | 설치 끝 | 저절로 뜨는 'Claude 로그인' 창의 주소를 브라우저에서 승인하고 코드 붙여넣기 |

- 기록: `%LOCALAPPDATA%\Aivengers\logs\install-*.log`
- 옵션: `-DryRun`, `-NoBrowser`, `-NoClaudeLogin`, `-RebootNow`, `-Distro <이름>`, `-Port <번호>`, `-CaFile <PEM>`, `-NoWindowsCa`, `-DeployKey`, `-Branch <이름>`
- 앱·실행기 옵션: `-NoApp`, `-AppZip <zip>`, `-AppRelease <태그>`, `-NoHostRunner`, `-NoLoginItem`, `-NoGit`(`-HostRunner`는 옛 명령 호환용, 이제 기본)
- 업데이트: 설치 뒤에는 접속 앱의 설정 › 시스템 › 업데이트 [업데이트하고 다시 열기]가 서버·앱을 새 판으로 바꿉니다. 이 설치기의 `-AppOnly`(WSL·서버 단계 없이 앱만 최신 릴리스로)는 그 버튼이 부릅니다
- 자세한 내용: 본체 저장소 `docs/install-windows.md`

### Windows(에이전트용)

사람이 Windows Claude Code에 붙여 넣는 한 줄:

```
https://github.com/Injae-Lee/aivengers-install 의 README 'Windows(에이전트용)' 절을 읽고 그대로 따라 Aivengers를 이 Windows에 설치해 줘.
```

에이전트가 할 일:

1. `irm https://raw.githubusercontent.com/Injae-Lee/aivengers-install/main/install.ps1 -OutFile $env:TEMP\aivengers-install.ps1`
2. `powershell -NoProfile -ExecutionPolicy Bypass -File $env:TEMP\aivengers-install.ps1 -NoBrowser`를 **백그라운드로** 실행하고 출력을 계속 읽습니다(수십 분). WSL이 없어도 미리 설치하지 않습니다(설치기가 함)
   - `UAC`·`"예"`가 보이면: "화면에 뜬 사용자 계정 컨트롤 창에서 '예'를 눌러 주세요"라고 말합니다
   - `REBOOT_REQUIRED`(종료 코드 3010)이면 이렇게 말하고 답을 기다립니다: "WSL을 켜려면 재부팅이 한 번 필요합니다. 재부팅 뒤 다시 로그인하면 'Aivengers 설치 이어 하기' 창이 저절로 떠서 끝까지 진행합니다. GitHub 코드와 Claude 로그인도 그 창에서 안내합니다. 이 대화로 돌아오지 않아도 됩니다. 지금 재부팅할까요?" → 예면 `shutdown.exe /r /t 30`을 실행하고 끝냅니다
   - `one-time code: XXXX-XXXX`가 보이면 그 코드와 https://github.com/login/device 를 사람에게 보여 주고 승인을 기다립니다(설치기가 스스로 이어 감, 약 15분 안)
   - 공개 키·`Deploy keys` 안내가 보이면(`-DeployKey`) 공개 키 한 줄을 사람에게 보여 주고 멈춥니다
3. `INSTALL_DONE`이 보이면 `==> 서버 응답 200`을 확인합니다. `APP_STARTED`면 접속 앱이 떴습니다. `APP_NOT_INSTALLED`면 그 앞 줄(종료 코드·이유)을 사람에게 알립니다(서버는 브라우저로 쓸 수 있음). `CLAUDE_LOGIN_WINDOW`가 있으면 "새로 뜬 'Claude 로그인' 창의 주소를 브라우저에서 열어 승인하고, 받은 코드를 그 창에 붙여 넣어 주세요"라고 말합니다. 로그인 명령을 대신 치지 않습니다
4. 재부팅 뒤 사람이 이 대화로 돌아와 물으면 `%LOCALAPPDATA%\Aivengers\logs`의 가장 새 `install-*.log` 끝 30줄을 읽어 상태를 알려 줍니다
5. 사람이 로그인했다고 하면 아래를 돌려 `# · PASS/FAIL · 출력 한 줄` 표로 보고합니다
   - `curl.exe -s -o NUL -w "%{http_code}" http://127.0.0.1:45180/api/auth/me` → `200`
   - `curl.exe -s -o NUL -w "%{http_code}" http://localhost:45180/api/auth/me` → `200`
   - `wsl -d Ubuntu-24.04 -- ls -ln ~/.local/share/aivengers/data` → 소유자 `1000 1000`, `deploy-token`이 `-rw-------`

- 멈출 조건: 3010이 아닌 0 아닌 종료 코드이거나 `실패:`가 찍히면 고치려 하지 말고 마지막 30줄과 함께 멈춥니다
- 금지: 토큰·키 파일 내용 출력(`~/.config/gh/hosts.yml`, `deploy-token`, `.credentials.json`, `deploy_key`), 관리자 PowerShell을 따로 열라고 하기(설치기가 UAC로 요청), 사람 동의 없이 재부팅, Docker Desktop 설치, `C:` 아래로 데이터 옮기기

## Mac 서버 내장 설치(예전 방식)

```sh
curl -fsSL https://raw.githubusercontent.com/Injae-Lee/aivengers-install/main/install.sh | bash
```

- 앱이 서버를 직접 띄우는 방식입니다. 새 설치는 위 'Mac'(`--docker --install-docker`)을 씁니다
- 옵션을 줄 때: `curl -fsSL …/install.sh | bash -s -- --dir ~/Aivengers-desktop --port 45280`
- 전제: GitHub 계정, Aivengers 저장소 초대(또는 `--deploy-key`), Claude 구독

## 이 스크립트가 하는 일(install.sh)

- macOS·arm64 확인
- `--install-docker`면 Homebrew(없을 때 공식 스크립트 비대화형, 비밀번호는 터미널 또는 비밀번호 창)
- git(Xcode Command Line Tools 또는 Homebrew)
- Node 24 이상(PATH의 node가 24 이상이면 그것 → 없으면 Homebrew `node@24` → 공식 tarball 24, sha256 고정)
- pnpm 11.14.0(`~/.aivengers/runtime/pnpm`)
- gh 로그인(브라우저 기기 인증, 터미널이 없어도 코드를 찍고 기다림), 저장소 초대가 와 있으면 수락, 접근 확인
- clone(기본 `~/Aivengers-desktop`) 또는 fast-forward 갱신
- 저장소의 `scripts/install.sh`(본체)로 넘김: 빌드·앱 놓기·설정·실행

## 옵션

- `--dir <경로>`: clone 위치(기본 `~/Aivengers-desktop`)
- `--branch <이름>`: 브랜치·태그(기본: 최신 `desktop-v*` 태그. `--channel main`이거나 지난 설치가 main 채널이면 `main`, 태그가 없으면 `main`). 지금 판이 최신 태그보다 앞서면 내려가지 않음
- `--deploy-key`: gh 대신 읽기 전용 deploy key. 처음에는 공개 키를 보여 주고 멈춥니다
- 나머지(`--docker`, `--install-docker`, `--no-claude-login`, `--no-login-item`, `--port`, `--data-dir`, `--no-launch`, `--repair`, `--applications`)는 본체로 넘깁니다

## 로그

- `~/.aivengers/logs/bootstrap-*.log`, 본체는 `install-*.log`
- 문제가 나면 마지막 로그를 초대한 사람에게 보냅니다

## 개발

- 시험: `sh test/bootstrap.test.sh`(리눅스에서도 돎. Homebrew 설치는 가짜 설치 스크립트로 보고, gh·tarball·실제 Homebrew는 Mac에서만 확인)
- `install.sh`의 Homebrew 함수는 본체 `scripts/lib/brew-install.sh`와 같은 동작입니다. 바뀌면 같이 고칩니다
- PR마다 shellcheck와 시험이 돕니다(`.github/workflows/check.yml`). `install.ps1`은 Windows job에서 PSScriptAnalyzer·PowerShell 5.1 파서로 봅니다
- `install.ps1`은 본체 저장소 `scripts/install.ps1`의 사본입니다(본체가 Windows 쪽만 쓰고 WSL 안에서 clone하므로 그대로 돎). 본체가 바뀌면 같이 갱신합니다. 기준: 본체 `470e024`(AIV-668·671)
- 이 저장소에는 비밀값·내부 주소를 넣지 않습니다
