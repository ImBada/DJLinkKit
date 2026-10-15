# 저작권과 라이선스

이 저장소의 결과물은 **GNU General Public License, version 2 or (at your option) any later version (GPL-2.0-or-later)**로 배포한다. 전문은 [LICENSE](LICENSE)(같은 내용이 [LICENSES/GPL-2.0-or-later.txt](LICENSES/GPL-2.0-or-later.txt))에 있다. 파일에 따로 적힌 `SPDX-License-Identifier`가 없으면 GPL-2.0-or-later가 기본이다.

## 저작권 표시

| 범위 | 저작권 | 들어올 때의 라이선스 |
|---|---|---|
| 이 프로젝트가 새로 쓴 Swift 코드와 문서 | Copyright (c) 2026 Bada | GPL-2.0-or-later |
| alphatheta-connect·onelibrary-connect·metadata-connect를 옮긴 부분(`DJLinkKit`, `DJLinkControl`, `DJLinkPassive`, `djlink`) | Copyright (c) 2013 Evan Purkhiser, Copyright (c) 2025–2026 Chris Le 등 | MIT. 원문과 표시는 [LICENSES/MIT.txt](LICENSES/MIT.txt)와 [THIRD_PARTY_NOTICES.md](THIRD_PARTY_NOTICES.md)에 그대로 두었다 |
| rbxport를 옮긴 `DJLinkExport*` | Copyright (c) 2026 Chris Le | GPL-2.0-or-later |
| DJCrate 리더에서 옮긴 파일 | Copyright (c) 2026 Hyeonjae Nam (같은 저작자) | MIT에서 GPL-2.0-or-later로 |
| 그 밖의 제3자 항목 | [THIRD_PARTY_NOTICES.md](THIRD_PARTY_NOTICES.md) | 항목마다 적혀 있다 |

## 왜 GPL로 통일했나

`DJLinkExport`가 GPL-2.0-or-later인 rbxport의 파생물이라 MIT로 낼 수 없다. MIT 코드는 GPL 결과물에 합쳐 배포해도 되므로(MIT가 허용한다), 같은 저장소의 제품마다 라이선스가 다르게 보이지 않도록 하나로 통일했다. MIT 원문과 저작권 표시는 지우지 않고 보존한다.

## 알아둘 것

- **2026-10-15 이전에 공개된 커밋**은 그때의 MIT 조건으로 받은 사본이 이미 있다. 그 사본의 MIT 조건은 바뀌지 않는다.
- 이 패키지(어느 제품이든)를 링크해 배포하는 프로그램은 GPL-2.0-or-later의 조건을 따라야 한다.
- 앱스토어 배포는 GPL과 약관이 충돌하는 것으로 알려져 있다.
