# 후속 보강 적용 현황

기존 검토 아래 항목 중 서버 발급 세션, 이벤트 기반 점수 재계산, 요청 한도, DB CHECK 제약, 신고·숨김·삭제 요청 및 취소를 구현하고 실제 DB 통합 테스트를 통과했습니다. 상세 범위와 잔여 한계는 [OPERATIONS.md](OPERATIONS.md)에 있습니다. Turnstile은 사용자 요청으로 제외했습니다. 자동 보관 정리 스케줄은 2026-10-18 사용자 승인으로 등록했으며, 2026-10-21 활성화 상태를 확인했습니다(매일 한국 시간 04:15, 서버 GMT 19:15).

---

# 보안 검토 — 2026-10-17

범위: 공개 프런트엔드, online.js, schema.sql, 익명 API 접근 차단 실측. 전문 침투 테스트나 모든 Supabase 관리자 설정 점검을 대체하지 않습니다. 관리자 비밀키는 사용하지 않았습니다.

## 확인한 보호

- hunters/hunts에 RLS 활성화, anon/authenticated 직접 테이블 권한 회수. 공개키로 두 테이블을 limit=0 조회했을 때 각각 401 permission denied 확인.
- 인증 없는 save_hunt 호출도 401 permission denied. 인증된 호출은 auth.uid()를 사용하며 전달받은 사용자 ID를 신뢰하지 않음.
- 함수에 고정된 빈 search_path, 동적 SQL 없음. 닉네임 허용 문자/길이, 사진 형식/크기, 점수 범위, 단계/포획 수 검증.
- 동일 기록 UUID 재전송 방지, 사용자별 잠금과 3초 저장 간격.
- 랭킹 이름/상세는 textContent 사용. 업로드 사진은 브라우저에서 128×128 WebP로 다시 인코딩. 서버 최대 약 28KB.
- config.js는 공개용 publishable key만 포함. 이 키가 보이는 것은 설계된 동작이며, 보호는 DB 권한과 검증이 담당.

## 이번 보강

- CSP: 같은 출처 스크립트/스타일만 허용, 연결 대상은 같은 출처 및 이 게임의 Supabase 프로젝트로 제한. 인라인 스크립트, 플러그인, base URL 변경, 폼 전송 차단.
- no-referrer 적용. CSP 적용 후 실제 온라인 랭킹 읽기 정상 확인.

## 권장 우선순위

1. **점수 위조 방지 (높음, 랭킹 신뢰성)**: 현재 클라이언트의 최종 점수와 시간만 받으므로 수학적으로 타당한 가짜 기록은 통과 가능. 서버에서 게임 세션 시작/종료 및 이벤트 순서/시간을 검증하고 일회성 세션 ID 사용. 클라이언트 서명이나 난독화만으로 해결되지 않음.
2. **봇·용량 남용 (중간)**: 익명 계정을 계속 만들면 사용자별 3초 제한을 우회할 수 있음. CAPTCHA/Turnstile, 서버 측 IP/사용자 쿼터, 이상 요청 모니터링 권장. 현재 설정의 CAPTCHA 활성 여부와 관리자 rate limit 값은 이번 점검 범위 밖. UI 코드에는 CAPTCHA 토큰 전달이 없음.
3. **누적 기록 정리/쿼리 비용 (중간)**: 화면은 100개지만 DB는 모든 기록을 보관하며 조회 시 사용자별 최고 기록을 계산. 보관기간, 총 저장 제한, 최고 기록 집계 테이블/캐시 마련.
4. **DB 검증 경계 (중간)**: PostgreSQL 배열의 시작 인덱스/차원은 cardinality만으로 보장되지 않음. array_ndims=1, array_lower=1, array_upper=3 및 각 값 NOT NULL을 명시하여 SQL NULL 조건 우회를 방어. RPC 외 경로에 대비한 테이블 CHECK 제약도 권장. 실제 악성 기록은 운영 DB에 삽입하지 않았음.
5. **공개 콘텐츠 관리 (중간)**: 닉네임/사진 공개에 대한 안내는 있으나 신고/숨김/삭제 기능 없음. 운영자 관리 및 본인 데이터 삭제 기능 권장. 익명 세션을 잃으면 같은 사용자로 복구 불가.
6. **추가 브라우저 보호 (낮음)**: 인증 토큰은 localStorage에 있어 향후 XSS가 생기면 탈취 위험. CSP는 위험을 줄이지만 완전 방어는 아님. GitHub Pages의 meta CSP로는 frame-ancestors 보호가 불가하므로 호스팅/프록시에서 응답 헤더 설정 시 보강.

DB 변경, CAPTCHA 도입, 로그인 방식 변경은 이번 디자인 수정에서 적용하지 않았습니다.

## 근거

- https://supabase.com/docs/guides/auth/auth-anonymous
- https://supabase.com/docs/guides/getting-started/api-keys
- https://supabase.com/docs/guides/database/functions

## 이미지 변경 기록

내장 imagegen 편집 사용. 저장: assets/cat-face.png.
프롬프트: 기존 단순한 3D 얼굴, 초록 눈, 이어진 ^ 이마 무늬를 보존하고 코 왼쪽의 황갈색 얼룩만 코 위 콧등까지 하나의 넓고 둥근 무늬로 확장. 털 디테일/몸/장식 추가 없이 투명 배경 유지.
