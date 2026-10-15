#!/usr/bin/env bash
# 로컬 CI. GitHub Actions는 끄고, 합치기 전에 이 스크립트로 같은 검사를 돌린다.
#
# 사용법:
#   UPSTREAM_DIR=~/src/upstream bash scripts/ci.sh [--loopback]
#
#   UPSTREAM_DIR  원본 세 저장소가 나란히 있는 부모 폴더 (기본값 ~/src/upstream, 받는 법은 UPSTREAM.md)
#   --loopback    루프백(127.0.0.1) 통합 시험도 돌린다(DJLINK_LOOPBACK_TESTS=1). LAN에는 아무것도 보내지 않는다.
#                 기본 시험을 먼저 돌리고, 루프백 시험만 따로 한 번 더 돌린다(#33). 같은 프로세스에서
#                 SQLCipher DB 열기가 DJLinkActor를 몇 초씩 막아 루프백 시험의 시간 제한이 먼저 지나기 때문이다.
#
# 하는 일: swift test → (--loopback이면) 루프백 시험만 → TypeScript/Rust 시험 이름 정적 대응(고정 커밋 포함).
# 앞이 실패해도 뒤는 돈다.
# 종료 코드: 0 = 모두 통과, 1 = 하나라도 실패, 2 = 사용법 오류
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

LOOPBACK=0
while [ $# -gt 0 ]; do
  case "$1" in
    --loopback) LOOPBACK=1; shift ;;
    -h|--help) sed -n '2,14p' "$0"; exit 0 ;;
    *) echo "오류: 알 수 없는 인자 $1" >&2; exit 2 ;;
  esac
done

cd "$ROOT"
failed=()

echo "== swift test"
DJLINK_LOOPBACK_TESTS=0 swift test || failed+=("swift test")

if [ "$LOOPBACK" = 1 ]; then
  # 루프백 조건부 시험만 따로 돈다. 새 루프백 시험을 더하면 이 목록에도 더한다.
  LOOPBACK_FILTER='LiveTCPConnectionLoopback|DJLinkExportTests\.LoopbackTests|ExportSocketGuardTests'
  echo "== swift test (DJLINK_LOOPBACK_TESTS=1, 루프백 시험만)"
  DJLINK_LOOPBACK_TESTS=1 swift test --filter "$LOOPBACK_FILTER" || failed+=("swift test --loopback")
fi

echo "== port-status"
bash scripts/port-status.sh --strict || failed+=("port-status")

echo "== export-port-status"
python3 scripts/export-port-status.py --strict || failed+=("export-port-status")

if [ ${#failed[@]} -gt 0 ]; then
  echo "실패: ${failed[*]}" >&2
  exit 1
fi
echo "모두 통과"
