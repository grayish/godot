#!/usr/bin/env bash
# 학습 프로젝트 헤드리스 검증 스크립트.
# 사용: learning/projects/tools/verify.sh <project_dir> [godot_binary]
#  1) selftest.gd 실행 (SELFTEST PASS 필요)
#  2) 메인 씬(허브)을 5 프레임 실행
#  3) demo_runner.gd: 모든 .gd 를 load() 로 컴파일 검사한 뒤 demos/*/*.tscn 을 각각 인스턴스화
# 어느 단계든 "SCRIPT ERROR" / "ERROR:" / "Parse error" 가 나오면 실패.
set -u
PROJ="$(cd "$1" && pwd)"
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
GODOT="${2:-${GODOT:-$HERE/../../../bin/godot.linuxbsd.editor.x86_64}}"
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
RUNNER="$HERE/demo_runner.gd"
FAIL=0
ERRPAT='SCRIPT ERROR|^ERROR:|Parse error|Failed to load|SCRIPT LOAD FAIL|DEMO FAIL|Invalid call|Nonexistent|Cannot instantiate|Node not found'

run() { # name, cmd...
	local name="$1"; shift
	local out
	out="$(timeout 120 "$@" 2>&1)"
	local code=$?
	if [ $code -ne 0 ] || grep -Eq "$ERRPAT" <<<"$out"; then
		echo "FAIL [$name] exit=$code"
		grep -E -A2 "$ERRPAT" <<<"$out" | head -40
		FAIL=1
	else
		echo "ok   [$name]"
	fi
	echo "$out" > "/tmp/verify_${name//[^A-Za-z0-9_]/_}.log"
}

echo "== verify $PROJ"
if [ -f "$PROJ/selftest.gd" ]; then
	out="$(timeout 120 "$GODOT" --headless --path "$PROJ" -s res://selftest.gd 2>&1)"; code=$?
	if [ $code -ne 0 ] || ! grep -q "SELFTEST PASS" <<<"$out" || grep -Eq "$ERRPAT" <<<"$out"; then
		echo "FAIL [selftest] exit=$code"; grep -E -A2 "$ERRPAT|SELFTEST" <<<"$out" | head -60; FAIL=1
	else
		echo "ok   [selftest] $(grep 'SELFTEST PASS' <<<"$out")"
	fi
else
	echo "FAIL [selftest] missing selftest.gd"; FAIL=1
fi

run "hub" "$GODOT" --headless --path "$PROJ" --quit-after 5
run "demos" "$GODOT" --headless --path "$PROJ" -s "$RUNNER"
grep -h "SCRIPT OK\|DEMO OK\|DEMO_RUNNER DONE" /tmp/verify_demos.log 2>/dev/null | sed 's/^/     /'

if [ $FAIL -eq 0 ]; then echo "VERIFY PASS $PROJ"; else echo "VERIFY FAIL $PROJ"; fi
exit $FAIL
