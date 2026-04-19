#!/usr/bin/env bash
# team-panels — 첫 패널(기획)만 열고 체인 시작
set -euo pipefail

TASK="${1:-}"
if [[ -z "$TASK" ]]; then
  echo "Usage: $0 \"작업 설명\"" >&2
  exit 1
fi
if [[ -z "${CMUX_WORKSPACE_ID:-}" ]]; then
  echo "Error: cmux 터미널 세션 안에서 실행해야 합니다 (CMUX_WORKSPACE_ID 없음)" >&2
  exit 1
fi

CMUX="/Applications/cmux.app/Contents/Resources/bin/cmux"
SKILL_DIR="$HOME/.claude/skills/team-panels/scripts"
TS="$(date +%Y%m%d-%H%M%S)"
WORK_DIR="$HOME/.cmux-team/$TS"
OUT_DIR="$WORK_DIR/outputs"
PROMPT_DIR="$WORK_DIR/prompts"
mkdir -p "$OUT_DIR" "$PROMPT_DIR"

printf '%s' "$TASK" > "$WORK_DIR/TASK.md"

# 역할 정의 (순번|이름|분할방향|프롬프트)
# 기획(01)이 팀 리드로서 <next-roles> 마커로 필요한 역할만 선택해 호출
ROLES=(
  "01|기획|right|당신은 제품 기획자(PM)이자 팀 리드입니다. 사용자 요청을 분석해 어떤 전문가 역할의 산출물이 필요한지 판단하세요.\n\n판단 기준(중요):\n- 사용자가 \"설계/구현/테스트/문서화/리뷰/디자인/보안 검토/아키텍처\" 같은 구체 산출물을 요구 → 해당 전문가 역할 반드시 호출\n- 기능/앱/서비스 개발 요청(\"만들어줘/설계해줘/기획해줘/구축해줘\") → 최소 아키텍트·디자인·개발·테스트 조합 호출. 혼자 다 작성하지 말 것.\n- 정말로 1단계로 끝나는 경우(단일 질문 답변, 한두 줄 카피, 사실 확인, 짧은 문구)만 기획 단독 완결\n\n복잡한 작업: 기획 산출물(요구사항·유저 스토리·수용 기준·우선순위)만 작성하고 상세는 전문가에게 위임. 당신이 미리 다 써버리면 후속 역할이 할 일이 사라짐.\n단독 완결 시: 모든 관점/산출물 직접 작성 + 필요한 파일 직접 저장.\n\n출력 마지막 줄에 반드시: <next-roles>번호,번호,...</next-roles> (호출할 역할 번호 쉼표 구분, 없으면 빈 태그)\n\n역할 번호: 02=리서치 03=아키텍트 04=DBA 05=디자인 06=UX라이터 07=개발 08=보안 09=코드리뷰 10=DevOps 11=테스트 12=테크라이터\n\n호출 예시:\n- 간단 웹앱(카운터/메모/타이머 등) 설계 요청: 03,05,07,11\n- 일반 웹 기능 설계: 02,03,05,07,09,11\n- DB 있는 기능: 02,03,04,05,07,09,11\n- 보안 민감 기능: 02,03,04,08,07,09,11\n- 릴리즈 준비/운영화: 09,11,10,12\n- 카피/문구 수정만: 06\n- 사실 질문/한 줄 답변: 빈 태그"
  "02|리서치|down|당신은 프로덕트 리서처입니다. 작업 관련 시장/경쟁사/유저 인사이트를 정리하세요: 유사 사례, 사용자 페인포인트, 기회 영역, 참고할 패턴. 구체적 레퍼런스를 포함해 마크다운으로 작성."
  "03|아키텍트|right|당신은 소프트웨어 아키텍트입니다. 시스템 구조를 설계하세요: 컴포넌트 다이어그램(ASCII), 데이터 흐름, 외부 의존성, 기술 스택 선택 근거, 주요 트레이드오프. 기획/리서치 산출물을 참고."
  "04|DBA|down|당신은 데이터베이스 전문가입니다. 데이터 모델을 설계하세요: 엔티티, 관계, 스키마(컬럼·타입·제약), 필요한 인덱스, 마이그레이션 전략. 아키텍트 산출물과 정합성 확인."
  "05|디자인|right|당신은 UI/UX 디자이너입니다. 화면 흐름, 컴포넌트 구성, 주요 인터랙션, 상태 변화(로딩/에러/빈 상태), 와이어프레임(ASCII/마크다운)을 작성. 접근성(대비/키보드/스크린리더)도 간략 체크."
  "06|UX라이터|down|당신은 UX 라이터입니다. 화면 내 카피, 버튼 레이블, 에러/성공 메시지, 빈 상태 문구, 톤앤매너 가이드를 작성. 디자인 산출물과 짝을 맞춰 일관성 유지."
  "07|개발|right|당신은 시니어 개발자입니다. 구현 계획을 설계하세요: 파일/모듈 구조, 핵심 함수 시그니처, 데이터 흐름, 핵심 로직 의사코드, 에러 처리 전략. 기획/아키텍트/디자인 산출물을 모두 반영."
  "08|보안|down|당신은 보안 엔지니어입니다. 위협 모델링을 수행하세요: STRIDE 분석, 공격 벡터, OWASP Top 10 체크, 인증/인가 설계, 민감 데이터 처리 방안, 로깅/감사 정책."
  "09|코드리뷰|right|당신은 수석 코드 리뷰어입니다. 개발/아키텍트 산출물을 검토해 잠재 이슈(보안/성능/유지보수성/가독성), 리스크, 개선 체크리스트, 추천 리팩토링을 작성."
  "10|DevOps|down|당신은 DevOps/SRE 엔지니어입니다. 배포·운영 전략을 설계하세요: CI/CD 파이프라인, 환경 구성(dev/staging/prod), IaC 개요, 모니터링·알람 지표, 롤백 전략, 장애 대응 플레이북."
  "11|테스트|right|당신은 QA 엔지니어입니다. 테스트 전략을 수립하세요: 테스트 피라미드(단위/통합/E2E), 정상/경계/예외 케이스, 자동화 범위, 성능/부하 시나리오, QA 체크리스트."
  "12|테크라이터|down|당신은 테크니컬 라이터입니다. 문서를 작성하세요: README(설치/사용법), API 명세(요청/응답/에러 코드), 아키텍처 개요, 개발자 온보딩 가이드, 변경 이력(CHANGELOG) 템플릿."
)

# plan.tsv 작성 (role.sh 가 참조)
: > "$WORK_DIR/plan.tsv"
for entry in "${ROLES[@]}"; do
  IFS='|' read -r NUM NAME DIR PROMPT <<< "$entry"
  PROMPT_FILE="$PROMPT_DIR/$NUM.txt"
  # %b 로 \n 등을 실제 제어문자로 해석
  printf '%b' "$PROMPT" > "$PROMPT_FILE"
  printf '%s\t%s\t%s\t%s\n' "$NUM" "$NAME" "$DIR" "$PROMPT_FILE" >> "$WORK_DIR/plan.tsv"
done

# 원래 워크스페이스 기억 (체인 종료 후 복귀할 용도)
ORIG_WS="$CMUX_WORKSPACE_ID"
echo "$ORIG_WS" > "$WORK_DIR/original-workspace.txt"

# 새 워크스페이스 생성 — 체인이 이 안에서 진행되고 완료 시 통째로 닫힘
WS_OUT=$("$CMUX" new-workspace --cwd "$HOME" 2>&1) || {
  echo "Error: 새 워크스페이스 생성 실패: $WS_OUT" >&2
  exit 1
}
WS=$(echo "$WS_OUT" | grep -oE 'workspace:[0-9]+' | head -1)
if [[ -z "$WS" ]]; then
  echo "Error: 새 워크스페이스 ID 파싱 실패: $WS_OUT" >&2
  exit 1
fi
echo "$WS" > "$WORK_DIR/workspace.txt"
"$CMUX" rename-workspace --workspace "$WS" "team-panels" >/dev/null 2>&1 || true
sleep 0.5

# 기본 surface 획득 (새 워크스페이스에 자동 생성된 터미널)
FIRST_SURFACE=$("$CMUX" list-pane-surfaces --workspace "$WS" 2>&1 | grep -oE 'surface:[0-9]+' | head -1)
if [[ -z "$FIRST_SURFACE" ]]; then
  echo "Error: 새 워크스페이스 기본 surface 찾기 실패" >&2
  exit 1
fi

FIRST_NAME="기획"
FIRST_NUM="01"
"$CMUX" rename-tab --surface "$FIRST_SURFACE" --workspace "$WS" "$FIRST_NAME" >/dev/null 2>&1 || true

# 생성된 패널 ID 추적 (중간 실패 시 fallback 용)
echo "$FIRST_SURFACE" > "$WORK_DIR/surfaces.txt"

# 기획 역할 실행 명령 전달
CMD="bash $SKILL_DIR/role.sh $WORK_DIR $FIRST_NUM"
"$CMUX" send --surface "$FIRST_SURFACE" --workspace "$WS" "$CMD" >/dev/null 2>&1
"$CMUX" send-key --surface "$FIRST_SURFACE" --workspace "$WS" Enter >/dev/null 2>&1

# 포커스 복귀 — 사용자 작업 공간을 뺏지 않도록 원래 워크스페이스로 선택 복원
"$CMUX" select-workspace --workspace "$ORIG_WS" >/dev/null 2>&1 || true

echo "[team-panels] 시작됨 (새 워크스페이스: $WS, 백그라운드)"
echo "  작업: $TASK"
echo "  워크디렉토리: $WORK_DIR"
echo "  완료 시 워크스페이스 전체가 자동으로 닫힙니다"
