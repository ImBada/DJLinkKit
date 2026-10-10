#!/usr/bin/env bash
# 원본 시험(it/test) 수와 옮긴 Swift 시험(@Test) 수를 파일별로 나란히 보여 주고,
# 하나라도 다르면 exit 1로 끝난다. (PLAN §8 끝 조건)
#
# 사용법:
#   UPSTREAM_DIR=~/src/upstream bash scripts/port-status.sh [--stage N] [--strict]
#
#   UPSTREAM_DIR  alphatheta-connect, onelibrary-connect, metadata-connect가
#                 나란히 있는 부모 폴더 (기본값 ~/src/upstream)
#   --stage N     PLAN §8 표의 단계 N(1~8) 파일만 본다
#   --strict      원본이 고정 커밋이 아니면 경고 대신 exit 2로 끝난다(scripts/ci.sh가 쓴다)
#
# 종료 코드: 0 = 모두 같음, 1 = 하나라도 다름, 2 = 사용법·환경 오류
set -euo pipefail

UPSTREAM_DIR="${UPSTREAM_DIR:-$HOME/src/upstream}"
UPSTREAM_DIR="${UPSTREAM_DIR/#\~/$HOME}"
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

STAGE=""
STRICT=0
while [ $# -gt 0 ]; do
  case "$1" in
    --stage)
      [ $# -ge 2 ] || { echo "오류: --stage에는 단계 번호가 필요하다" >&2; exit 2; }
      STAGE="$2"; shift 2 ;;
    --stage=*) STAGE="${1#--stage=}"; shift ;;
    --strict) STRICT=1; shift ;;
    -h|--help) sed -n '2,14p' "$0"; exit 0 ;;
    *) echo "오류: 알 수 없는 인자 $1" >&2; exit 2 ;;
  esac
done
case "$STAGE" in
  ""|[1-8]) ;;
  *) echo "오류: --stage는 1~8이어야 한다 (받은 값: $STAGE)" >&2; exit 2 ;;
esac

# 고정 커밋 확인 (다르면 경고만 한다. --strict면 실패)
check_pin() {
  local repo="$1" pin="$2" head
  if [ ! -d "$UPSTREAM_DIR/$repo" ]; then
    echo "오류: $UPSTREAM_DIR/$repo 가 없다" >&2; exit 2
  fi
  head="$(git -C "$UPSTREAM_DIR/$repo" rev-parse HEAD 2>/dev/null || echo unknown)"
  case "$head" in
    "$pin"*) ;;
    *)
      if [ "$STRICT" = 1 ]; then
        echo "오류: $repo 가 고정 커밋($pin)이 아니다 (현재 ${head:0:7}). UPSTREAM.md 참고" >&2; exit 2
      fi
      echo "경고: $repo 가 고정 커밋($pin)이 아니다 (현재 ${head:0:7}). UPSTREAM.md 참고" >&2 ;;
  esac
}
check_pin alphatheta-connect 7496991060a38951c2119db13c26b3da7c075bfa
check_pin onelibrary-connect ac3edd3b8a18f7649d336ebd56d28b15923a05d6
check_pin metadata-connect   c2ae262650a7bbe7af5fb5222a6ab6b882ecf865

# 대응표: 단계|원본 파일(UPSTREAM_DIR 기준)|Swift 파일(저장소 기준)
# 단계 번호는 PLAN §8 표를 따른다. docs/port-map.md의 시험 대응과 같아야 한다.
MAP='
1|alphatheta-connect/tests/utils/index.spec.ts|Tests/DJLinkKitTests/Utils/UtilsIndexTests.swift
1|alphatheta-connect/tests/devices/index.spec.ts|Tests/DJLinkKitTests/Devices/DevicesIndexTests.swift
1|alphatheta-connect/tests/devices/utils.spec.ts|Tests/DJLinkKitTests/Devices/DevicesUtilsTests.swift
1|alphatheta-connect/tests/status/utils.spec.ts|Tests/DJLinkKitTests/Status/StatusUtilsTests.swift
1|alphatheta-connect/tests/status/position.spec.ts|Tests/DJLinkKitTests/Status/StatusPositionTests.swift
1|alphatheta-connect/tests/status/on-air.test.ts|Tests/DJLinkKitTests/Status/StatusOnAirTests.swift
1|alphatheta-connect/src/status/stagehand-gating.test.ts|Tests/DJLinkKitTests/Status/StatusStagehandGatingTests.swift
2|alphatheta-connect/src/virtualcdj/heartbeat.test.ts|Tests/DJLinkKitTests/VirtualCDJ/VirtualCDJHeartbeatTests.swift
2|alphatheta-connect/tests/virtualcdj/conflict.test.ts|Tests/DJLinkKitTests/VirtualCDJ/VirtualCDJConflictTests.swift
2|alphatheta-connect/tests/virtualcdj/device-id.test.ts|Tests/DJLinkKitTests/VirtualCDJ/VirtualCDJDeviceIdTests.swift
2|alphatheta-connect/tests/virtualcdj/stagehand.test.ts|Tests/DJLinkKitTests/VirtualCDJ/VirtualCDJStagehandTests.swift
2|alphatheta-connect/tests/virtualcdj/startup.test.ts|Tests/DJLinkKitTests/VirtualCDJ/VirtualCDJStartupTests.swift
2|alphatheta-connect/tests/virtualcdj/wire-selection.test.ts|Tests/DJLinkKitTests/VirtualCDJ/VirtualCDJWireSelectionTests.swift
2|alphatheta-connect/tests/network/stagehand-identity.test.ts|Tests/DJLinkKitTests/Network/NetworkStagehandIdentityTests.swift
3|alphatheta-connect/tests/remotedb/connection.spec.ts|Tests/DJLinkKitTests/RemoteDB/RemoteDBConnectionTests.swift
3|alphatheta-connect/tests/remotedb/fields.spec.ts|Tests/DJLinkKitTests/RemoteDB/RemoteDBFieldsTests.swift
3|alphatheta-connect/src/nfs/index.test.ts|Tests/DJLinkKitTests/NFS/NFSIndexTests.swift
3|alphatheta-connect/tests/nfs/path.spec.ts|Tests/DJLinkKitTests/NFS/NFSPathTests.swift
4|alphatheta-connect/tests/localdb/anlz-2ex-integration.spec.ts|Tests/DJLinkKitTests/LocalDB/LocalDBAnlz2exIntegrationTests.swift
4|alphatheta-connect/tests/localdb/anlz-parsers-2ex.spec.ts|Tests/DJLinkKitTests/LocalDB/LocalDBAnlzParsers2exTests.swift
4|alphatheta-connect/tests/localdb/anlz-parsers-cue-nulls.spec.ts|Tests/DJLinkKitTests/LocalDB/LocalDBAnlzParsersCueNullsTests.swift
4|alphatheta-connect/tests/localdb/anlz-parsers-cues.spec.ts|Tests/DJLinkKitTests/LocalDB/LocalDBAnlzParsersCuesTests.swift
4|alphatheta-connect/tests/localdb/anlz-parsers-extended-cues.spec.ts|Tests/DJLinkKitTests/LocalDB/LocalDBAnlzParsersExtendedCuesTests.swift
4|alphatheta-connect/tests/localdb/anlz-parsers-song-structure.spec.ts|Tests/DJLinkKitTests/LocalDB/LocalDBAnlzParsersSongStructureTests.swift
4|alphatheta-connect/tests/localdb/anlz-parsing.spec.ts|Tests/DJLinkKitTests/LocalDB/LocalDBAnlzParsingTests.swift
4|alphatheta-connect/tests/localdb/database-fallback.spec.ts|Tests/DJLinkKitTests/LocalDB/LocalDBDatabaseFallbackTests.swift
4|alphatheta-connect/tests/localdb/database-loading.spec.ts|Tests/DJLinkKitTests/LocalDB/LocalDBDatabaseLoadingTests.swift
4|alphatheta-connect/tests/localdb/edge-cases.spec.ts|Tests/DJLinkKitTests/LocalDB/LocalDBEdgeCasesTests.swift
4|alphatheta-connect/tests/localdb/load-anlz-vocal-config.spec.ts|Tests/DJLinkKitTests/LocalDB/LocalDBLoadAnlzVocalConfigTests.swift
4|alphatheta-connect/tests/localdb/onelibrary-adapter.spec.ts|Tests/DJLinkKitTests/LocalDB/LocalDBOnelibraryAdapterTests.swift
4|onelibrary-connect/tests/adapter.spec.ts|Tests/DJLinkKitTests/OneLibraryConnect/OneLibraryConnectAdapterTests.swift
5|alphatheta-connect/tests/db/blankMetadata.spec.ts|Tests/DJLinkKitTests/DB/DBBlankMetadataTests.swift
5|alphatheta-connect/tests/db/getMetadata.spec.ts|Tests/DJLinkKitTests/DB/DBGetMetadataTests.swift
5|alphatheta-connect/tests/db/getPlaylist.spec.ts|Tests/DJLinkKitTests/DB/DBGetPlaylistTests.swift
5|alphatheta-connect/tests/db/getWaveforms.spec.ts|Tests/DJLinkKitTests/DB/DBGetWaveformsTests.swift
5|alphatheta-connect/tests/artwork/extraction.integration.test.ts|Tests/DJLinkKitTests/Artwork/ArtworkExtractionIntegrationTests.swift
5|alphatheta-connect/tests/artwork/parsers.spec.ts|Tests/DJLinkKitTests/Artwork/ArtworkParsersTests.swift
5|metadata-connect/test/extract.test.ts|Tests/DJLinkKitTests/MetadataConnect/MetadataConnectExtractTests.swift
5|metadata-connect/test/label.test.ts|Tests/DJLinkKitTests/MetadataConnect/MetadataConnectLabelTests.swift
6|alphatheta-connect/tests/mixstatus/index.spec.ts|Tests/DJLinkKitTests/MixStatus/MixStatusIndexTests.swift
7|alphatheta-connect/tests/control/load.spec.ts|Tests/DJLinkControlTests/ControlLoadTests.swift
7|alphatheta-connect/tests/control/stagehand.spec.ts|Tests/DJLinkControlTests/ControlStagehandTests.swift
8|alphatheta-connect/tests/passive/alphatheta.spec.ts|Tests/DJLinkPassiveTests/PassiveAlphathetaTests.swift
8|alphatheta-connect/tests/passive/pcap-adapter.spec.ts|Tests/DJLinkPassiveTests/PassivePcapAdapterTests.swift
'

# jest-each의 `each([...]).it(` 꼴(줄이 `]).it(`로 시작)도 시험 하나로 센다.
count_upstream() { [ -f "$1" ] && { grep -cE '^\s*(it|test)(\.each)?\(|^\s*\]\)\.(it|test)\(' "$1" || true; } || echo "-"; }
count_swift()    { [ -f "$1" ] && { grep -cE '^\s*@Test\b' "$1" || true; } || echo 0; }

fmt='%-5s %-68s %6s  %-6s %6s  %s\n'
printf "$fmt" "단계" "원본 파일" "원본" "" "Swift" "Swift 파일 / 판정"
rows=0; bad=0
declare -a sum_up sum_sw
for g in alphatheta-connect onelibrary-connect metadata-connect; do sum_up[${#sum_up[@]}]=0; sum_sw[${#sum_sw[@]}]=0; done
group_index() { case "$1" in alphatheta-connect/*) echo 0 ;; onelibrary-connect/*) echo 1 ;; *) echo 2 ;; esac; }

while IFS='|' read -r stage up sw; do
  [ -n "$stage" ] || continue
  if [ -n "$STAGE" ] && [ "$stage" != "$STAGE" ]; then continue; fi
  u="$(count_upstream "$UPSTREAM_DIR/$up")"
  s="$(count_swift "$ROOT/$sw")"
  verdict="같음"
  if [ "$u" = "-" ]; then
    verdict="원본 파일 없음"; bad=$((bad+1)); u=0
  elif [ "$u" -ne "$s" ]; then
    verdict="다름"; bad=$((bad+1))
  fi
  gi="$(group_index "$up")"
  sum_up[$gi]=$(( ${sum_up[$gi]} + u ))
  sum_sw[$gi]=$(( ${sum_sw[$gi]} + s ))
  rows=$((rows+1))
  short="${sw#Tests/}"
  printf "$fmt" "$stage" "$up" "$u" "" "$s" "$short  [$verdict]"
done <<< "$MAP"

if [ "$rows" -eq 0 ]; then echo "오류: 보여 줄 파일이 없다" >&2; exit 2; fi

tot_up=$(( ${sum_up[0]} + ${sum_up[1]} + ${sum_up[2]} ))
tot_sw=$(( ${sum_sw[0]} + ${sum_sw[1]} + ${sum_sw[2]} ))
echo
printf "%-36s 원본 %5d   Swift %5d\n" "alphatheta-connect" "${sum_up[0]}" "${sum_sw[0]}"
printf "%-36s 원본 %5d   Swift %5d\n" "onelibrary-connect" "${sum_up[1]}" "${sum_sw[1]}"
printf "%-36s 원본 %5d   Swift %5d\n" "metadata-connect" "${sum_up[2]}" "${sum_sw[2]}"
printf "%-36s 원본 %5d   Swift %5d   (파일 %d개%s)\n" "합계" "$tot_up" "$tot_sw" "$rows" "${STAGE:+, 단계 $STAGE}"

if [ "$bad" -ne 0 ] || [ "$tot_up" -ne "$tot_sw" ]; then
  echo "결과: 다름 (파일 ${bad}개가 어긋남)"
  exit 1
fi
echo "결과: 모두 같음"
