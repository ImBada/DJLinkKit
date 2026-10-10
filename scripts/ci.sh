#!/usr/bin/env bash
# 로컬 CI. GitHub Actions는 끄고, 합치기 전에 이 스크립트로 같은 검사를 돌린다.
#
# 사용법:
#   UPSTREAM_DIR=~/src/upstream bash scripts/ci.sh [--loopback]
#
#   UPSTREAM_DIR  원본 세 저장소가 나란히 있는 부모 폴더 (기본값 ~/src/upstream, 받는 법은 UPSTREAM.md)
#   --loopback    루프백(127.0.0.1) 통합 시험도 돌린다(DJLINK_LOOPBACK_TESTS=1). LAN에는 아무것도 보내지 않는다.
#
# 하는 일: swift test → port-status --strict(원본이 고정 커밋이 아니어도 실패). 앞이 실패해도 뒤는 돈다.
# 종료 코드: 0 = 모두 통과, 1 = 하나라도 실패, 2 = 사용법 오류
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

LOOPBACK=0
while [ $# -gt 0 ]; do
  case "$1" in
    --loopback) LOOPBACK=1; shift ;;
    -h|--help) sed -n '2,11p' "$0"; exit 0 ;;
    *) echo "오류: 알 수 없는 인자 $1" >&2; exit 2 ;;
  esac
done

cd "$ROOT"
failed=()

echo "== swift test (DJLINK_LOOPBACK_TESTS=$LOOPBACK)"
DJLINK_LOOPBACK_TESTS="$LOOPBACK" swift test || failed+=("swift test")

echo "== port-status"
bash scripts/port-status.sh --strict || failed+=("port-status")

if [ ${#failed[@]} -gt 0 ]; then
  echo "실패: ${failed[*]}" >&2
  exit 1
fi
echo "모두 통과"
