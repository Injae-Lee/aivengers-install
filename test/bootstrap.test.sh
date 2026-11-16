#!/bin/sh
# shellcheck disable=SC2016,SC2034,SC2088  # check는 eval로 늦게 펼친다. '~'는 따옴표 친 ~ 펼침 시험용.
# install.sh(부트스트랩) 흐름 시험. 플랫폼 확인을 건너뛰고(AIVENGERS_INSTALL_SKIP_PLATFORM=1) Node 24·pnpm 11.14.0으로 보이는
# 가짜 실행 파일과 로컬 bare 저장소(AIVENGERS_REPO_URL)를 쓴다. gh 로그인·Homebrew·tarball 경로는 Mac에서만 확인한다.
# 사용법: sh test/bootstrap.test.sh   (BOOT_BASH=/bin/bash로 macOS 기본 bash 3.2에서 돌린다)
set -eu

HERE=$(cd "$(dirname "$0")" && pwd)
BOOT=$HERE/../install.sh
FAILS=0
PASSES=0
ok() { PASSES=$((PASSES + 1)); echo "PASS $*"; }
ng() { FAILS=$((FAILS + 1)); echo "FAIL $*"; }
check() { if eval "$1"; then ok "$2"; else ng "$2 ($1)"; fi; }

T=$(mktemp -d)
trap 'rm -rf "$T"' EXIT
H=$T/home
mkdir -p "$H" "$T/bin" "$T/src/scripts"
printf '#!/bin/sh\n[ "$1" = --version ] && { echo "${FAKE_NODE_VER:-v24.22.2}"; exit 0; }\nexit 0\n' >"$T/bin/node"
printf '#!/bin/sh\n[ "$1" = --version ] && { echo 11.14.0; exit 0; }\nexit 0\n' >"$T/bin/pnpm"
chmod +x "$T/bin/"*
# 본체 자리: 받은 인자·환경을 남긴다
cat >"$T/src/scripts/install.sh" <<EOF
#!/usr/bin/env bash
printf '%s\n' "\$@" >"$T/body-args"
printf 'node=%s\npnpm=%s\nstate=%s\n' "\$AIVENGERS_NODE" "\$AIVENGERS_PNPM" "\$AIVENGERS_STATE_DIR" >"$T/body-env"
EOF
git -C "$T/src" init -q -b main
git -C "$T/src" -c user.email=t@t -c user.name=t add -A
git -C "$T/src" -c user.email=t@t -c user.name=t commit -qm init
git clone -q --bare "$T/src" "$T/remote.git"

run() {
  set +e
  env HOME="$H" PATH="$T/bin:$PATH" AIVENGERS_INSTALL_SKIP_PLATFORM=1 AIVENGERS_REPO_URL="$T/remote.git" \
    "${BOOT_BASH:-bash}" "$BOOT" "$@" >"$T/out" 2>&1
  RC=$?
  set -e
}

run --dir "$H/Aivengers-desktop" --port 45280 --no-launch
check '[ "$RC" -eq 0 ]' "첫 실행 성공"
check '[ -f "$H/Aivengers-desktop/scripts/install.sh" ]' "clone"
check '[ "$(tr "\n" " " <"$T/body-args")" = "--dir $H/Aivengers-desktop --from-bootstrap --port 45280 --no-launch " ]' "본체에 --dir과 나머지 옵션을 넘김"
check 'grep -q "^node=$T/bin/node$" "$T/body-env" && grep -q "^pnpm=$T/bin/pnpm$" "$T/body-env" && grep -q "^state=$H/.aivengers$" "$T/body-env"' "본체에 node·pnpm·상태 폴더 넘김"
check 'ls "$H/.aivengers/logs"/bootstrap-*.log >/dev/null' "로그 파일"

# Node 24 이상이면 PATH의 node를 그대로 쓴다(26 포함, AIV-271 후속)
export FAKE_NODE_VER=v26.13.0
run --dir "$H/Aivengers-desktop" --no-launch
check '[ "$RC" -eq 0 ] && grep -q "^node=$T/bin/node$" "$T/body-env" && grep -q "v26.13.0" "$T/out"' "Node 26은 PATH의 것을 그대로 씀"
unset FAKE_NODE_VER

echo b >"$T/src/new.txt"
git -C "$T/src" -c user.email=t@t -c user.name=t add -A
git -C "$T/src" -c user.email=t@t -c user.name=t commit -qm two
git -C "$T/src" push -q "$T/remote.git" main
run --dir "$H/Aivengers-desktop"
check '[ "$RC" -eq 0 ] && [ -f "$H/Aivengers-desktop/new.txt" ]' "두 번째 실행은 fast-forward로 갱신"

# 브랜치로 받은 기존 설치를 기본 실행(--branch 없음 = main)이 main으로 옮기는지
git -C "$T/src" checkout -q -b feat-x
echo f >"$T/src/feat.txt"
git -C "$T/src" -c user.email=t@t -c user.name=t add -A
git -C "$T/src" -c user.email=t@t -c user.name=t commit -qm feat
git -C "$T/src" push -q "$T/remote.git" feat-x
git -C "$T/src" checkout -q main
run --dir "$H/Aivengers-desktop" --branch feat-x
check '[ "$RC" -eq 0 ] && [ "$(git -C "$H/Aivengers-desktop" rev-parse --abbrev-ref HEAD)" = feat-x ]' "--branch로 다른 브랜치 checkout"
run --dir "$H/Aivengers-desktop"
check '[ "$RC" -eq 0 ] && [ "$(git -C "$H/Aivengers-desktop" rev-parse --abbrev-ref HEAD)" = main ] && [ ! -f "$H/Aivengers-desktop/feat.txt" ]' "기본 실행은 main으로 돌아옴"

: >"$H/Aivengers-desktop/aivengers-desktop-0.0.0.tgz"
run --dir "$H/Aivengers-desktop"
check '[ "$RC" -eq 0 ]' "추적하지 않는 파일(지난 실패의 tarball)은 갱신을 막지 않음"
rm -f "$H/Aivengers-desktop/aivengers-desktop-0.0.0.tgz"

echo dirty >>"$H/Aivengers-desktop/scripts/install.sh"
run --dir "$H/Aivengers-desktop"
check '[ "$RC" -ne 0 ] && grep -q "고친 파일이 있어" "$T/out"' "고친 checkout은 갱신하지 않고 멈춤"
git -C "$H/Aivengers-desktop" checkout -q -- scripts/install.sh

mkdir -p "$H/other"
echo x >"$H/other/file"
run --dir "$H/other"
check '[ "$RC" -ne 0 ] && grep -q "비어 있지 않은 폴더" "$T/out"' "비어 있지 않은 폴더 거절"

run --dir '~/Aivengers-desktop'
check '[ "$RC" -eq 0 ] && grep -q "^--dir$" "$T/body-args" && grep -q "^$H/Aivengers-desktop$" "$T/body-args"' "따옴표 친 ~ 펼침"

# tag 채널(AIV-662): --branch가 없으면 새 clone은 최신 desktop-v* 태그를 받는다. --channel main이면 main. 앞선 판은 내려가지 않음
git -C "$T/src" -c user.email=t@t -c user.name=t tag -a desktop-v0.1.0 -m t HEAD
TAG1=$(git -C "$T/src" rev-parse HEAD)
echo m >"$T/src/main-ahead.txt"
git -C "$T/src" -c user.email=t@t -c user.name=t add -A
git -C "$T/src" -c user.email=t@t -c user.name=t commit -qm ahead
git -C "$T/src" push -q "$T/remote.git" main --tags
run --dir "$H/tagged"
check '[ "$RC" -eq 0 ] && [ "$(git -C "$H/tagged" rev-parse HEAD)" = "$TAG1" ] && [ ! -f "$H/tagged/main-ahead.txt" ]' "새 clone은 최신 desktop-v* 태그를 받음(main이 앞서도)"
run --dir "$H/mainch" --channel main
check '[ "$RC" -eq 0 ] && [ -f "$H/mainch/main-ahead.txt" ] && grep -q "^--channel$" "$T/body-args"' "--channel main이면 main(옵션은 본체로)"
run --dir "$H/mainch"
check '[ "$RC" -eq 0 ] && [ -f "$H/mainch/main-ahead.txt" ] && grep -q "지금 판이 desktop-v0.1.0보다 앞섬" "$T/out"' "다시 실행: 지금 판(main)이 태그보다 앞서면 내려가지 않음"
git -C "$T/src" -c user.email=t@t -c user.name=t tag -a desktop-v0.2.0 -m t HEAD
TAG2=$(git -C "$T/src" rev-parse HEAD)
git -C "$T/src" push -q "$T/remote.git" --tags
run --dir "$H/tagged"
check '[ "$RC" -eq 0 ] && [ "$(git -C "$H/tagged" rev-parse HEAD)" = "$TAG2" ]' "다시 실행: 새 태그가 나오면 그 태그로"

# --install-docker이고 Homebrew가 없으면 공식 스크립트를 NONINTERACTIVE로 돌린다. 터미널이 없으면 비밀번호 창(SUDO_ASKPASS)(AIV-660)
HB=$T/homebrew
cat >"$T/brew-install.sh" <<EOF
echo "installer NONINTERACTIVE=\$NONINTERACTIVE askpass=\${SUDO_ASKPASS:+set}" >>"$T/brew-calls"
[ -n "\${SUDO_ASKPASS:-}" ] && cat "\$SUDO_ASKPASS" >"$T/askpass-copy"
[ -f "$T/brew-fails" ] && exit 1
mkdir -p "$HB/bin"
printf '#!/bin/sh\nexit 0\n' >"$HB/bin/brew"
chmod +x "$HB/bin/brew"
EOF
export AIV_BREW_PREFIX="$HB" AIV_BREW_INSTALL_URL="file://$T/brew-install.sh" AIVENGERS_NO_TTY=1 AIV_OSASCRIPT=/fake/osascript
: >"$T/brew-fails"
run --dir "$H/Aivengers-desktop" --docker --install-docker
check '[ "$RC" -ne 0 ] && grep -q "Homebrew 설치가 끝나지 않았습니다" "$T/out"' "Homebrew 설치 실패면 멈춤"
rm -f "$T/brew-fails" "$T/body-args"
run --dir "$H/Aivengers-desktop" --docker --install-docker
check '[ "$RC" -eq 0 ] && grep -q "^installer NONINTERACTIVE=1 askpass=set$" "$T/brew-calls"' "터미널 없음: NONINTERACTIVE·SUDO_ASKPASS로 Homebrew 설치"
check 'grep -q "^SUDO_PASSWORD_DIALOG:" "$T/out" && grep -q "/fake/osascript" "$T/askpass-copy" && grep -q "with hidden answer" "$T/askpass-copy"' "비밀번호 창 표시 줄·숨김 입력 창"
check 'grep -q "^--docker$" "$T/body-args" && grep -q "^--install-docker$" "$T/body-args"' "--docker·--install-docker는 본체로 넘김"
: >"$T/brew-calls"
run --dir "$H/Aivengers-desktop" --docker --install-docker
check '[ "$RC" -eq 0 ] && [ ! -s "$T/brew-calls" ]' "다시 실행: 깔린 Homebrew(PATH 밖이어도)는 다시 깔지 않음"
rm -rf "$HB"
: >"$T/brew-calls"
run --dir "$H/Aivengers-desktop" --no-launch
check '[ "$RC" -eq 0 ] && [ ! -s "$T/brew-calls" ]' "--install-docker가 없으면 Homebrew를 깔지 않음"
unset AIV_BREW_PREFIX AIV_BREW_INSTALL_URL AIVENGERS_NO_TTY AIV_OSASCRIPT

env HOME="$H" AIVENGERS_INSTALL_SKIP_PLATFORM= bash -c 'uname() { [ "$1" = -s ] && echo Linux || echo x86_64; }; export -f uname; bash "$0" --dir "$HOME/z"' "$BOOT" >"$T/out" 2>&1 && RC=0 || RC=$?
check '[ "$RC" -ne 0 ] && grep -q "macOS만 지원" "$T/out"' "macOS 아니면 멈춤"

# $이름 바로 뒤에 비ASCII(한글 등)가 붙으면 macOS bash 3.2가 변수 이름을 잘못 읽는다('out이: unbound variable'). ${이름}으로 감싼다.
BAD=$(perl -ne 'next if /^\s*#/; print "$.: $_" if /(?<!\\)\$[A-Za-z_][A-Za-z0-9_]*[^\x00-\x7F]/' "$BOOT" || true)
check '[ -z "$BAD" ]' "install.sh에 \${이름}으로 감싸지 않은 변수 없음"
[ -z "$BAD" ] || printf '%s\n' "$BAD"

echo "== $PASSES 통과, $FAILS 실패"
[ "$FAILS" -eq 0 ]
