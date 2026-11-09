# aivengers-install

Aivengers Desktop 부트스트랩 설치기. 초대받은 사람만 쓸 수 있습니다(본체 저장소는 비공개).

## 요약

- 터미널에서 한 줄을 실행하면 전제 조건을 갖추고 비공개 저장소를 받은 뒤, 저장소 안의 설치기 본체로 넘깁니다.
- 지원: macOS(Apple Silicon)만

## 설치

```sh
curl -fsSL https://raw.githubusercontent.com/Injae-Lee/aivengers-install/main/install.sh | bash
```

- 옵션을 줄 때: `curl -fsSL …/install.sh | bash -s -- --dir ~/Aivengers-desktop --port 45280`
- 전제: GitHub 계정, Aivengers 저장소 초대(또는 `--deploy-key`), Claude 구독

## 이 스크립트가 하는 일

- macOS·arm64 확인
- git(Xcode Command Line Tools 또는 Homebrew)
- Node 24 이상(PATH의 node가 24 이상이면 그것 → 없으면 Homebrew `node@24` → 공식 tarball 24, sha256 고정)
- pnpm 11.14.0(`~/.aivengers/runtime/pnpm`)
- gh 로그인(브라우저 기기 인증)과 저장소 접근 확인
- clone(기본 `~/Aivengers-desktop`) 또는 fast-forward 갱신
- 저장소의 `scripts/install.sh`(본체)로 넘김: 빌드·앱 놓기·설정·실행

## 옵션

- `--dir <경로>`: clone 위치(기본 `~/Aivengers-desktop`)
- `--branch <이름>`: 브랜치·태그(기본 `main`)
- `--deploy-key`: gh 대신 읽기 전용 deploy key. 처음에는 공개 키를 보여 주고 멈춥니다
- 나머지(`--port`, `--data-dir`, `--no-launch`, `--repair`, `--applications`)는 본체로 넘깁니다

## 로그

- `~/.aivengers/logs/bootstrap-*.log`, 본체는 `install-*.log`
- 문제가 나면 마지막 로그를 초대한 사람에게 보냅니다

## 개발

- 시험: `sh test/bootstrap.test.sh`(리눅스에서도 돎, gh·Homebrew·tarball 경로는 Mac에서만 확인)
- PR마다 shellcheck와 시험이 돕니다(`.github/workflows/check.yml`)
- 이 저장소에는 비밀값·내부 주소를 넣지 않습니다
