# Godot Engine 아키텍처 분석 & 학습 자료

> 기준 소스: 이 저장소 (`version.py` 기준 Godot **4.8 dev**, master 브랜치).
> 모든 파일 경로/줄 번호는 이 저장소 기준이며, 직접 열어보면서 읽는 것을 전제로 작성했습니다.

## 이 자료의 목적

Godot을 **사용자(게임 개발자)** 로서 배우는 것과 **엔진 개발자** 로서 이해하는 것 사이의 간극을 메우는 것이 목표입니다.
공식 문서는 "어떻게 쓰는가"를, 이 자료는 "왜 그렇게 설계되었고 소스 어디에 있는가"를 다룹니다.

## 목차

| 장 | 파일 | 내용 |
|---|---|---|
| 0 | [00-quickstart.md](00-quickstart.md) | 빌드하고 소스를 따라가 볼 준비 (SCons, 디버그, 테스트) |
| 1 | [01-architecture-overview.md](01-architecture-overview.md) | 전체 구조: 계층(layer) 모델, 부팅 순서, 메인 루프 |
| 2 | [02-core-layer.md](02-core-layer.md) | `core/`: Object · Variant · ClassDB · Resource · 컨테이너 · GDExtension |
| 3 | [03-servers-and-scene.md](03-servers-and-scene.md) | `servers/`와 `scene/`: 서버 패턴(RID), SceneTree, Node, Viewport |
| 4 | [04-modules-and-scripting.md](04-modules-and-scripting.md) | `modules/`: 모듈 구조, GDScript 컴파일러, C#, 물리 백엔드 |
| 5 | [05-multiplatform.md](05-multiplatform.md) | 멀티플랫폼: `platform/` · `drivers/` · 빌드 시스템 · 익스포트 |
| 6 | [06-graphics-backends.md](06-graphics-backends.md) | 그래픽스 백엔드: RenderingDevice, Vulkan/D3D12/Metal, GL Compatibility, 셰이더 파이프라인 |
| 7 | [07-graphics-tuning.md](07-graphics-tuning.md) | 백엔드별 튜닝: 프로젝트 설정 항목, 플랫폼별 권장값, 진단 방법 |
| 8 | [08-comparison-other-engines.md](08-comparison-other-engines.md) | Unity · Unreal · Bevy · Defold 등과의 설계 차이 |
| 9 | [09-learning-roadmap.md](09-learning-roadmap.md) | 튜토리얼부터 엔진 내부까지: 단계별 학습 로드맵과 연습 과제 |
| 부록 | [appendix-glossary.md](appendix-glossary.md) | 용어집 & 자주 찾는 파일 색인 |
| 실습 | [projects/README.md](projects/README.md) | Stage 1~7 각각에 대응하는 실행 가능한 Godot 프로젝트 7개 (데모 허브 + 셀프테스트) |

## 읽는 순서 제안

- **엔진을 처음 접함**: 9장(로드맵) → 0장 → 1장 → 3장 → 다시 9장의 단계별 과제
- **다른 엔진 경험자**: 8장(비교) → 1장 → 3장 → 6장
- **렌더링/그래픽스 관심**: 1장 → 6장 → 7장 → `servers/rendering/` 직접 읽기
- **엔진 기여/모듈 개발**: 2장 → 4장 → 5장(빌드) → `CONTRIBUTING.md`

## 실습 프로젝트

`learning/projects/` 에 단계별 Godot 프로젝트가 있습니다. 각 장을 읽은 뒤 해당 프로젝트를 에디터로 열어 데모를 눌러 보고, 스크립트 주석에 적힌 엔진 소스 경로를 따라가는 방식을 권합니다. 헤드리스로도 검증할 수 있습니다: `learning/projects/tools/verify.sh learning/projects/<dir>`.

## 표기 규칙

- `path/to/file.h:123` 형식은 이 저장소의 파일과 줄 번호입니다 (줄 번호는 커밋에 따라 조금씩 달라질 수 있습니다).
- 📌 = 꼭 열어봐야 하는 파일, 🧪 = 직접 해 볼 실습, ⚠️ = 흔한 오해/함정.
