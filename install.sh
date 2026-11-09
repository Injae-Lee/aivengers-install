#!/usr/bin/env bash
# Aivengers Desktop 부트스트랩 설치기(공개).
#
#   curl -fsSL https://raw.githubusercontent.com/Injae-Lee/aivengers-install/main/install.sh | bash
#   curl -fsSL https://raw.githubusercontent.com/Injae-Lee/aivengers-install/main/install.sh | bash -s -- --dir ~/Aivengers-desktop --port 45280
#
# 하는 일(얇게): macOS(Apple Silicon) 확인 → git(Xcode CLT) → Node 24 → pnpm → gh 로그인 → 비공개 저장소 clone·갱신
# → 저장소 안의 scripts/install.sh(본체)로 넘긴다. 빌드·앱 놓기·설정은 본체가 한다(저장소 코드와 함께 바뀌어 판이 어긋나지 않음).
# 이 파일에는 비밀값·내부 주소를 넣지 않는다.
#
# 옵션(이 스크립트가 쓰는 것): --dir <clone 위치>(기본 ~/Aivengers-desktop), --branch <브랜치·태그>(기본 main),
#   --deploy-key(gh 대신 읽기 전용 deploy key로 받기), -h|--help. 나머지 옵션은 본체로 그대로 넘긴다
#   (--port, --data-dir, --no-launch, --repair, --applications).
# 로그: ~/.aivengers/logs/bootstrap-<시각>.log
#
# 함수 안에서만 실행한다: 내려받기가 중간에 끊겨도 반쯤 받은 스크립트가 돌지 않게 마지막 줄에서 main을 부른다.
# shellcheck disable=SC2088  # "~"는 사용자가 따옴표로 넘긴 경로를 펼치려고 글자 그대로 비교한다.
set -euo pipefail

REPO_SLUG="Injae-Lee/Aivengers"
NODE_VERSION="24.22.2"
NODE_SHA256="1f5ac075be50bed4780ea3be19a007fda95ea4d527d28d76d0b91de47d915115"
PNPM_VERSION="11.14.0"
GH_VERSION="2.103.3"
GH_SHA256="d700207eae9ae98fe2b89535c2c087c07823d4628c56364695a5a07ef311c062"

STATE_DIR="${AIVENGERS_STATE_DIR:-$HOME/.aivengers}"
RUNTIME_DIR="$STATE_DIR/runtime"
LOG_DIR="$STATE_DIR/logs"
DIR="$HOME/Aivengers-desktop"
BRANCH="main"
USE_DEPLOY_KEY=0
PASS_ARGS=()
LOG_FILE=""

say() { printf '\033[1m==>\033[0m %s\n' "$*"; }
warn() { printf '\033[33m주의:\033[0m %s\n' "$*" >&2; }
die() {
  printf '\033[31m실패:\033[0m %s\n' "$*" >&2
  [ -n "$LOG_FILE" ] && printf '로그: %s\n' "$LOG_FILE" >&2
  exit 1
}
has() { command -v "$1" >/dev/null 2>&1; }

usage() {
  sed -n '2,16p' "${BASH_SOURCE[0]:-/dev/null}" 2>/dev/null | sed 's/^# \{0,1\}//' || true
  cat <<'EOF'
사용법: install.sh [--dir <경로>] [--branch <이름>] [--deploy-key] [본체 옵션…]
EOF
}

parse_args() {
  while [ $# -gt 0 ]; do
    case "$1" in
      --dir) [ $# -ge 2 ] || die "--dir에 경로가 필요합니다"; DIR="$2"; shift 2 ;;
      --dir=*) DIR="${1#*=}"; shift ;;
      --branch) [ $# -ge 2 ] || die "--branch에 이름이 필요합니다"; BRANCH="$2"; shift 2 ;;
      --branch=*) BRANCH="${1#*=}"; shift ;;
      --deploy-key) USE_DEPLOY_KEY=1; shift ;;
      -h|--help) usage; exit 0 ;;
      *) PASS_ARGS+=("$1"); shift ;;
    esac
  done
  case "$DIR" in "~"|"~/"*) DIR="$HOME${DIR#\~}" ;; esac
  case "$DIR" in /*) ;; *) DIR="$PWD/$DIR" ;; esac
}

open_log() {
  mkdir -p "$LOG_DIR"
  LOG_FILE="$LOG_DIR/bootstrap-$(date +%Y%m%d-%H%M%S).log"
  exec > >(tee -a "$LOG_FILE") 2>&1
  say "로그: $LOG_FILE"
}

check_platform() {
  [ "${AIVENGERS_INSTALL_SKIP_PLATFORM:-}" = 1 ] && return 0
  [ "$(uname -s)" = Darwin ] || die "macOS만 지원합니다(지금 $(uname -s))"
  [ "$(uname -m)" = arm64 ] || die "Apple Silicon(arm64) Mac만 지원합니다(지금 $(uname -m))"
}

# /dev/tty가 있어야 gh 로그인·Xcode 설치 확인을 할 수 있다(curl | bash에서도 터미널에서 받는다).
have_tty() { [ -r /dev/tty ] && [ -w /dev/tty ] && : </dev/tty 2>/dev/null; }

brew_bin() {
  if has brew; then command -v brew
  elif [ -x /opt/homebrew/bin/brew ]; then echo /opt/homebrew/bin/brew
  fi
}

ensure_git() {
  if [ "${AIVENGERS_INSTALL_SKIP_PLATFORM:-}" = 1 ] || xcode-select -p >/dev/null 2>&1; then
    has git || die "git이 없습니다"
    say "git: $(git --version)"
    return 0
  fi
  local brew; brew=$(brew_bin)
  if [ -n "$brew" ]; then
    say "Homebrew로 git을 설치합니다"
    "$brew" install git
    return 0
  fi
  say "Xcode Command Line Tools 설치 창을 엽니다. 창에서 '설치'를 누르세요(최대 15분 기다립니다)"
  xcode-select --install >/dev/null 2>&1 || true
  local waited=0
  until xcode-select -p >/dev/null 2>&1; do
    [ "$waited" -ge 900 ] && die "Xcode Command Line Tools 설치가 끝나지 않았습니다. 설치를 마친 뒤 같은 명령을 다시 실행하세요"
    sleep 10; waited=$((waited + 10))
  done
  say "git: $(git --version)"
}

node_major() { "$1" --version 2>/dev/null | sed -n 's/^v\([0-9]*\)\..*/\1/p'; }

sha256_of() {
  if has shasum; then shasum -a 256 "$1" | awk '{print $1}'; else sha256sum "$1" | awk '{print $1}'; fi
}

# Node 24: PATH의 node가 v24면 그대로 쓴다. 아니면 Homebrew node@24, 없으면 공식 tarball(sha256 고정)을 ~/.aivengers/runtime에.
# 다른 판의 node는 건드리지 않는다.
NODE_BIN=""
ensure_node() {
  if has node && [ "$(node_major node)" = 24 ]; then NODE_BIN=$(command -v node)
  elif [ -x "$RUNTIME_DIR/node/bin/node" ] && [ "$(node_major "$RUNTIME_DIR/node/bin/node")" = 24 ]; then NODE_BIN="$RUNTIME_DIR/node/bin/node"
  else
    local brew; brew=$(brew_bin)
    if [ -n "$brew" ] && "$brew" list --versions node@24 >/dev/null 2>&1; then
      NODE_BIN="$("$brew" --prefix node@24)/bin/node"
    elif [ -n "$brew" ]; then
      say "Homebrew로 node@24를 설치합니다(다른 node는 건드리지 않음)"
      "$brew" install node@24
      NODE_BIN="$("$brew" --prefix node@24)/bin/node"
    else
      say "Node ${NODE_VERSION}을 내려받습니다(~/.aivengers/runtime/node)"
      local tmp url; tmp=$(mktemp -d)
      url="https://nodejs.org/dist/v$NODE_VERSION/node-v$NODE_VERSION-darwin-arm64.tar.xz"
      curl -fsSL "$url" -o "$tmp/node.tar.xz" || die "Node를 내려받지 못했습니다: $url"
      [ "$(sha256_of "$tmp/node.tar.xz")" = "$NODE_SHA256" ] || die "Node 파일 해시가 다릅니다(변조·손상)"
      mkdir -p "$RUNTIME_DIR"
      rm -rf "$RUNTIME_DIR/node.new"
      mkdir "$RUNTIME_DIR/node.new"
      tar -xJf "$tmp/node.tar.xz" -C "$RUNTIME_DIR/node.new" --strip-components 1
      rm -rf "$RUNTIME_DIR/node" "$tmp"
      mv "$RUNTIME_DIR/node.new" "$RUNTIME_DIR/node"
      NODE_BIN="$RUNTIME_DIR/node/bin/node"
    fi
  fi
  [ "$(node_major "$NODE_BIN")" = 24 ] || die "Node 24를 준비하지 못했습니다($NODE_BIN)"
  PATH="$(dirname "$NODE_BIN"):$PATH"; export PATH
  say "node: $NODE_BIN ($("$NODE_BIN" --version))"
}

# pnpm: 저장소 packageManager와 같은 판. 전역 npm 폴더를 건드리지 않게 ~/.aivengers/runtime/pnpm에 둔다.
PNPM_BIN=""
ensure_pnpm() {
  if has pnpm && [ "$(pnpm --version 2>/dev/null)" = "$PNPM_VERSION" ]; then PNPM_BIN=$(command -v pnpm)
  elif [ -x "$RUNTIME_DIR/pnpm/bin/pnpm" ]; then PNPM_BIN="$RUNTIME_DIR/pnpm/bin/pnpm"
  else
    say "pnpm ${PNPM_VERSION}을 설치합니다(~/.aivengers/runtime/pnpm)"
    "$(dirname "$NODE_BIN")/npm" install -g --prefix "$RUNTIME_DIR/pnpm" "pnpm@$PNPM_VERSION" >/dev/null
    PNPM_BIN="$RUNTIME_DIR/pnpm/bin/pnpm"
  fi
  [ "$("$PNPM_BIN" --version)" = "$PNPM_VERSION" ] || die "pnpm ${PNPM_VERSION}을 준비하지 못했습니다($PNPM_BIN)"
  PATH="$(dirname "$PNPM_BIN"):$PATH"; export PATH
  say "pnpm: $PNPM_BIN ($PNPM_VERSION)"
}

GH_BIN=""
ensure_gh() {
  if has gh; then GH_BIN=$(command -v gh)
  elif [ -x "$RUNTIME_DIR/gh/bin/gh" ]; then GH_BIN="$RUNTIME_DIR/gh/bin/gh"
  else
    local brew; brew=$(brew_bin)
    if [ -n "$brew" ]; then
      say "Homebrew로 gh를 설치합니다"
      "$brew" install gh
      GH_BIN=$("$brew" --prefix)/bin/gh
    else
      say "gh ${GH_VERSION}을 내려받습니다(~/.aivengers/runtime/gh)"
      local tmp; tmp=$(mktemp -d)
      curl -fsSL "https://github.com/cli/cli/releases/download/v$GH_VERSION/gh_${GH_VERSION}_macOS_arm64.zip" -o "$tmp/gh.zip" \
        || die "gh를 내려받지 못했습니다"
      [ "$(sha256_of "$tmp/gh.zip")" = "$GH_SHA256" ] || die "gh 파일 해시가 다릅니다(변조·손상)"
      (cd "$tmp" && unzip -q gh.zip)
      rm -rf "$RUNTIME_DIR/gh"
      mkdir -p "$RUNTIME_DIR"
      mv "$tmp/gh_${GH_VERSION}_macOS_arm64" "$RUNTIME_DIR/gh"
      rm -rf "$tmp"
      GH_BIN="$RUNTIME_DIR/gh/bin/gh"
    fi
  fi
  PATH="$(dirname "$GH_BIN"):$PATH"; export PATH
  if ! "$GH_BIN" auth status -h github.com >/dev/null 2>&1; then
    have_tty || die "GitHub 로그인이 필요한데 터미널이 없습니다. 터미널 앱에서 다시 실행하세요"
    say "GitHub에 로그인합니다. 화면의 8자리 코드를 브라우저(github.com/login/device)에 넣으세요"
    "$GH_BIN" auth login -h github.com --web --git-protocol https </dev/tty
  fi
  "$GH_BIN" auth setup-git -h github.com
  "$GH_BIN" repo view "$REPO_SLUG" --json name >/dev/null 2>&1 \
    || die "$REPO_SLUG 저장소에 접근할 수 없습니다. 저장소 주인에게 초대를 받은 뒤(메일에서 수락) 다시 실행하세요. 초대 대신 --deploy-key를 쓸 수도 있습니다"
  say "gh: 로그인됨, 저장소 접근 확인"
}

# 읽기 전용 deploy key: 키를 만들고 공개 키를 보여 준다. 저장소 주인이 저장소 Deploy keys에 넣은 뒤 다시 실행한다.
GIT_URL=""
ensure_deploy_key() {
  local key="$STATE_DIR/deploy_key"
  mkdir -p "$STATE_DIR"
  if [ ! -f "$key" ]; then
    ssh-keygen -q -t ed25519 -N "" -C "aivengers-desktop $(whoami)@$(hostname -s)" -f "$key"
  fi
  export GIT_SSH_COMMAND="ssh -i $key -o IdentitiesOnly=yes -o StrictHostKeyChecking=accept-new"
  if ! git ls-remote "git@github.com:$REPO_SLUG.git" HEAD >/dev/null 2>&1; then
    say "아래 공개 키를 저장소 주인에게 보내 저장소 Deploy keys(읽기 전용)에 넣어 달라고 하세요. 넣은 뒤 같은 명령을 다시 실행합니다"
    cat "$key.pub"
    exit 2
  fi
  GIT_URL="git@github.com:$REPO_SLUG.git"
}

clone_or_update() {
  if [ -d "$DIR/.git" ]; then
    local url; url=$(git -C "$DIR" remote get-url origin 2>/dev/null || true)
    case "$url" in
      *"$REPO_SLUG"*|*"$REPO_SLUG.git") ;;
      *) if [ -z "${AIVENGERS_REPO_URL:-}" ] || [ "$url" != "$AIVENGERS_REPO_URL" ]; then
           die "${DIR}는 다른 저장소입니다($url). --dir로 다른 위치를 고르세요"
         fi ;;
    esac
    if [ -n "$(git -C "$DIR" status --porcelain --untracked-files=no)" ]; then
      die "${DIR}에 고친 파일이 있어 갱신하지 않습니다. 그 변경을 정리한 뒤 다시 실행하세요"
    fi
    say "저장소 갱신: $DIR ($BRANCH)"
    git -C "$DIR" fetch --tags origin
    git -C "$DIR" checkout -q "$BRANCH"
    if git -C "$DIR" symbolic-ref -q HEAD >/dev/null; then git -C "$DIR" pull -q --ff-only origin "$BRANCH"; fi
  else
    [ -e "$DIR" ] && [ -n "$(ls -A "$DIR" 2>/dev/null)" ] && die "${DIR}가 비어 있지 않은 폴더입니다. --dir로 다른 위치를 고르세요"
    say "저장소 받기: $DIR"
    git clone -q --branch "$BRANCH" "$GIT_URL" "$DIR"
  fi
  say "커밋: $(git -C "$DIR" log -1 --format='%h %s')"
}

main() {
  parse_args "$@"
  open_log
  check_platform
  ensure_git
  ensure_node
  ensure_pnpm
  if [ -n "${AIVENGERS_REPO_URL:-}" ]; then GIT_URL="$AIVENGERS_REPO_URL"   # 시험용
  elif [ "$USE_DEPLOY_KEY" = 1 ]; then ensure_deploy_key
  else ensure_gh; GIT_URL="https://github.com/$REPO_SLUG.git"
  fi
  clone_or_update
  local body="$DIR/scripts/install.sh"
  [ -f "$body" ] || die "본체 설치기($body)가 없습니다. --branch를 확인하세요"
  say "본체 설치기로 넘깁니다"
  AIVENGERS_NODE="$NODE_BIN" AIVENGERS_PNPM="$PNPM_BIN" AIVENGERS_STATE_DIR="$STATE_DIR" \
    exec "${BASH:-bash}" "$body" --dir "$DIR" --from-bootstrap "${PASS_ARGS[@]+"${PASS_ARGS[@]}"}"
}

main "$@"
