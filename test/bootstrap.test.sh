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
printf '#!/bin/sh\n[ "$1" = --version ] && { echo v24.22.2; exit 0; }\nexit 0\n' >"$T/bin/node"
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

env HOME="$H" AIVENGERS_INSTALL_SKIP_PLATFORM= bash -c 'uname() { [ "$1" = -s ] && echo Linux || echo x86_64; }; export -f uname; bash "$0" --dir "$HOME/z"' "$BOOT" >"$T/out" 2>&1 && RC=0 || RC=$?
check '[ "$RC" -ne 0 ] && grep -q "macOS만 지원" "$T/out"' "macOS 아니면 멈춤"

# $이름 바로 뒤에 비ASCII(한글 등)가 붙으면 macOS bash 3.2가 변수 이름을 잘못 읽는다('out이: unbound variable'). ${이름}으로 감싼다.
BAD=$(perl -ne 'next if /^\s*#/; print "$.: $_" if /(?<!\\)\$[A-Za-z_][A-Za-z0-9_]*[^\x00-\x7F]/' "$BOOT" || true)
check '[ -z "$BAD" ]' "install.sh에 \${이름}으로 감싸지 않은 변수 없음"
[ -z "$BAD" ] || printf '%s\n' "$BAD"

echo "== $PASSES 통과, $FAILS 실패"
[ "$FAILS" -eq 0 ]
