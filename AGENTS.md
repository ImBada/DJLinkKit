# AGENTS.md — DJLinkKit

alphatheta-connect(TypeScript)를 Swift로 1:1 옮기는 패키지다. 계획은 docs/PLAN.md, 원본 고정 커밋은 UPSTREAM.md, 출처 기록은 PROVENANCE.md에 있다. 옮기는 규칙은 docs/porting-guide.md에 있다.

- 사용자에게 하는 말·보고·질문은 한국어로 한다. 주석·커밋 메시지는 한국어, 식별자는 영어(원본 이름을 따른다)로 쓴다.
- 원본 동작을 1:1로 옮긴다. 1:1을 마치기 전에는 원본과 다르게 고치지 않는다. 원본 버그도 그대로 옮기고, 고칠 것은 docs/PLAN.md §9에 적는다.
- 원본 시험의 입력과 기대값을 바꾸지 않는다. `it('문구')`는 `@Test("문구")`로, 원본 파일 하나는 Swift 파일 하나로 옮긴다.
- `DJLinkExport*` 타깃은 rbxport(고정 커밋은 docs/LINK-EXPORT-PLAN.md)를 옮긴다. 같은 1:1 규칙을 따른다. 저장소 전체는 GPL-2.0-or-later다(COPYRIGHT.md).
- 구현하는 동안에는 빌드·시험을 돌리지 않는다. 사용자가 "구현 완료"라고 하면 그 단계 시험부터 돌린다.
- 시험은 실제 소켓을 열지 않고 LAN에 아무것도 보내지 않는다.
- 실기 확인은 공연 중이 아닌 시험용 네트워크에서, 같은 Mac의 rekordbox·rekordboxAgent가 꺼져 있을 때만 한다. 가상 CDJ 번호는 7 이상을 쓴다.
- 펌웨어나 rekordbox 실행 파일을 직접 분석하지 않는다(strings·디스어셈블 포함). 원본에 공개된 지식만 옮기고, 새로 알아내는 것은 실기 패킷 캡처를 비교해서만 한다.
- 라이선스가 없는 외부 코드·문서는 쓰지 않는다. 옮기면 THIRD_PARTY_NOTICES.md에 더한다. `.ksy`(EPL-1.0)와 Deep Symmetry 문서 원문은 옮기지 않는다.
- 패킷 캡처와 픽스처에 개인 곡 정보·경로·토큰을 넣지 않는다(공개 저장소).
- 커밋 제목은 `타입: 한국어 설명`으로 쓴다. 커밋·푸시는 요청받았을 때만 한다.
