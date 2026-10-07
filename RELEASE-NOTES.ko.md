# 白羽 Shiroha 0.14.0

[中文](RELEASE-NOTES.md) · [English](RELEASE-NOTES.en.md) · [日本語](RELEASE-NOTES.ja.md) · [한국어](RELEASE-NOTES.ko.md)

[소개·설치](README.ko.md) · [릴리스 노트](RELEASE-NOTES.ko.md) · [다음 업데이트](UPDATE-PREVIEW.ko.md) · [변경 내역](CHANGELOG.ko.md) · [문제 해결·기여](README.ko.md#help)

첫 공개 프리뷰입니다. 비주얼 노벨을 책장에 정리하고, 설치된 CrossOver로 실행할 수 있습니다. 밀린 게임 정리는 됐습니다. 이제 플레이할 차례네요.

## 이번 버전에 들어간 것

- 이름을 붙인 북마크 여러 개, 수동 공략 노드, 선행 조건과 완료 상태.
- 외부 Steam 라이브러리 검색, 실행 로그 관리, VNDB를 통한 Steam App ID 조회.
- 상세 화면, 긴 제목, 창 크기에 따른 표시 개선.
- 백업 검증, 북마크 이전, 오래된 스캔 결과, 편집 충돌 수정.
- ‘白羽 Shiroha’로 이름 변경 및 새 아이콘 추가. VNLauncher 데이터 폴더는 그대로 사용합니다.

## 다운로드

[v0.14.0 릴리스 페이지](https://github.com/Mornyep/Shiroha/releases/tag/v0.14.0)에서 받을 수 있습니다.

- `Shiroha-0.14.0-arm64.zip`: Apple Silicon용 앱.
- `Shiroha-0.14.0-source.zip`: 이 버전의 소스 코드 스냅샷.
- `Shiroha-SHA256SUMS.txt`: 위 두 ZIP 파일의 SHA-256 체크섬.

macOS 14 이상과 별도로 설치한 CrossOver, 게임, 보틀이 필요합니다. 현재 arm64 패키지만 제공합니다. 검증 환경은 macOS 27.2이며 Intel 및 macOS 14·15에서는 실제 기기 검증을 하지 않았습니다.

앱은 ad-hoc 서명을 사용하며 Developer ID 서명과 Apple 공증은 없습니다. 처음 실행하는 방법은 [한국어 설치 안내](README.ko.md#설치하고-첫-실행까지)를 확인해 주세요. 현재 앱 화면은 주로 중국어로 표시됩니다.

## 알려진 제한 사항

북마크와 공략은 직접 정리해야 합니다. 챕터 자동 인식이나 저장·불러오기 동기화는 지원하지 않습니다. 실제 게임의 음성, 영상, 입력, 저장·불러오기는 폭넓게 검증하지 못했습니다. 구성 요소 설치와 롤백, 외부 Steam 라이브러리의 전체 사용 흐름도 추가 검증이 필요합니다. 백업 전에 게임의 세이브 쓰기를 멈춰 주세요.

이 버전은 유닛 테스트 88개와 빌드·서명 검증을 통과했습니다. 모든 게임과 호환된다는 뜻은 아닙니다.

## 라이선스

프로젝트의 자체 소스 코드, 문서, 컴파일된 소프트웨어에는 [MIT License](LICENSE)가 적용됩니다. 나루세 시로하의 비공식 팬아트인 아이콘은 MIT 적용 대상에서 제외됩니다. 캐릭터 권리는 각 권리자에게 있으며 이 프로젝트는 공식 제작사와 무관합니다. [라이선스 적용 범위](LICENSE-SCOPE.md)와 [이미지 권리 안내](app/Artwork/NOTICE.md)를 확인해 주세요.

배포 파일과 v0.14.0 태그는 이 버전의 스냅샷을 유지합니다. main의 문서는 계속 업데이트됩니다. `RELEASE-FILES.json`은 소스 배포 파일에 들어 있는 파일과 해시를 기록한 것으로, main의 실시간 목록이 아닙니다.

