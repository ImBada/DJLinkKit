# 원본 (고정 커밋)

DJLinkKit이 1:1로 옮기는 원본 세 저장소다. 모두 읽기만 한다. 받은 폴더 안에서 npm이나 스크립트를 돌리지 않는다. 계획은 [docs/PLAN.md](docs/PLAN.md) §2, §12를 따른다.

| 저장소 | 고정 커밋 | 버전 | 커밋 날짜(UTC) | 라이선스 | 저작권 표시 |
|---|---|---|---|---|---|
| [chrisle/alphatheta-connect](https://github.com/chrisle/alphatheta-connect) | `7496991060a38951c2119db13c26b3da7c075bfa` | v0.28.5 | 2026-10-04 | MIT | Copyright (c) 2013 Evan Purkhiser |
| [chrisle/onelibrary-connect](https://github.com/chrisle/onelibrary-connect) | `ac3edd3b8a18f7649d336ebd56d28b15923a05d6` | v1.1.6 | 2026-09-26 | MIT | Copyright (c) 2025 Chris Le |
| [chrisle/metadata-connect](https://github.com/chrisle/metadata-connect) | `c2ae262650a7bbe7af5fb5222a6ab6b882ecf865` | v1.2.2 | 2026-09-08 | MIT | Copyright (c) 2026 Chris Le |

- 커밋 해시는 받아 둔 저장소에서 `git rev-parse HEAD`로 확인했다(2026-10-10). 세 커밋 모두 해당 버전의 릴리스 커밋(`chore: release vX.Y.Z`)이다.
- 라이선스와 저작권 표시는 각 저장소의 `LICENSE` 파일에서 옮겼다. alphatheta-connect는 `package.json`에 `author`가 Evan Purkhiser, `contributors`가 Chris Le로 적혀 있다. 고지 내용은 [THIRD_PARTY_NOTICES.md](THIRD_PARTY_NOTICES.md)에 있다.
- alphatheta-connect는 나머지 두 저장소를 `file:../`로 불러온다. 그래서 세 저장소를 같은 부모 폴더 아래에 나란히 받는다.

## 받는 방법

```bash
mkdir -p ~/src/upstream && cd ~/src/upstream
git clone https://github.com/chrisle/alphatheta-connect.git  && git -C alphatheta-connect  checkout 7496991060a38951c2119db13c26b3da7c075bfa
git clone https://github.com/chrisle/onelibrary-connect.git  && git -C onelibrary-connect  checkout ac3edd3b8a18f7649d336ebd56d28b15923a05d6
git clone https://github.com/chrisle/metadata-connect.git    && git -C metadata-connect    checkout c2ae262650a7bbe7af5fb5222a6ab6b882ecf865
```

`scripts/port-status.sh`는 `UPSTREAM_DIR`(기본값 `~/src/upstream`)에서 원본을 찾고, 고정 커밋과 다르면 경고만 출력한다.

## 다른 원본 (참고만 함)

- DJCrate(같은 저작자, MIT): localdb 리더(PDB·ANLZ 읽기, `CipherDatabase`)의 출발점이다. 읽은 기준 커밋은 `6b2954892257f7d96aee1328c9f654e267921333`이고, 옮긴 파일은 [docs/port-map.md](docs/port-map.md) §6, 고지는 [THIRD_PARTY_NOTICES.md](THIRD_PARTY_NOTICES.md) §2에 있다(PLAN §7). 원본 세 저장소와 달리 이 커밋을 따라가며 맞추지는 않는다.
- Deep Symmetry의 DJL Analysis 문서는 링크로만 가리킨다. 원문은 옮기지 않는다.

## 새 원본 릴리스를 따라가는 순서

한 번에 한 릴리스씩, 1:1 기준선인 `port/one-to-one` 브랜치에서 한다(PLAN §12).

1. 두 커밋 사이의 차이를 본다(`git diff <고정 커밋>..<새 릴리스>`).
2. 바뀐 시험부터 옮긴다.
3. 코드를 옮긴다.
4. `scripts/ci.sh`(시험과 `port-status.sh`)가 통과하는지 본다.
5. 이 파일(`UPSTREAM.md`)과 `scripts/port-status.sh`의 고정 커밋, 버전, 날짜를 갱신한다.
6. main에 합친다. PLAN §9에서 고친 곳과 겹치면 고친 쪽을 남긴다.

새 차이에 펌웨어 분석 근거가 생기면 [PROVENANCE.md](PROVENANCE.md)에 더한다. 시험 대응이나 파일 이름이 늘거나 바뀌면 `docs/port-map.md`와 `scripts/port-status.sh`의 대응표도 같이 고친다.

## Link Export 서버 원본

- [chrisle/rbxport](https://github.com/chrisle/rbxport/tree/90bfb53da59c5b2c3f0b76101601f30a6b74ab2b): 1.8.0, `90bfb53da59c5b2c3f0b76101601f30a6b74ab2b`, GPL-2.0-or-later, Copyright (c) 2026 Chris Le.
- `rbl-prolink`, `rbl-nfs`, `rbl-dbserver`, `rbl-link`와 서버에 필요한 ANLZ·메모리 모델을 별도 `DJLinkExport` 제품으로 옮긴다. 상세 범위·검증 상태는 [서버 계획](docs/LINK-EXPORT-PLAN.md), [대응표](docs/export-port-map.md).
- 이 원본도 읽기만 하며 Rust/npm 스크립트를 실행하지 않는다. 픽스처는 이 고정 체크아웃에서 읽는다.

```bash
git clone https://github.com/chrisle/rbxport.git ~/src/upstream/rbxport
git -C ~/src/upstream/rbxport checkout 90bfb53da59c5b2c3f0b76101601f30a6b74ab2b
```

- rbxport가 참조하는 Rust 클라이언트의 상태 파서는 [alphatheta-connect-rs `b54d9e9c53059f11e04f4de9898f4abae3b46480`](https://github.com/chrisle/alphatheta-connect-rs/tree/b54d9e9c53059f11e04f4de9898f4abae3b46480)에서 비교했다. 기존 Swift 클라이언트와 다른 패킷 길이·반올림 경계는 Export 쪽에서 대응한다.
