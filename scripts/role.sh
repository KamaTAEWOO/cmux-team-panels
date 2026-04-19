#!/usr/bin/env bash
# role.sh — 각 패널에서 실행되는 단일 역할 러너
# 역할 실행 → 산출물 저장 → 다음 역할 패널 열기
# 마지막 역할이 끝나면 모든 패널을 한 번에 닫음
set -euo pipefail

WORK_DIR="${1:-}"
NUM="${2:-}"

if [[ -z "$WORK_DIR" || -z "$NUM" ]]; then
  echo "Usage: $0 <work_dir> <role_num>" >&2
  exit 1
fi

CMUX="/Applications/cmux.app/Contents/Resources/bin/cmux"
SKILL_DIR="$HOME/.claude/skills/team-panels/scripts"
PLAN="$WORK_DIR/plan.tsv"
TASK_FILE="$WORK_DIR/TASK.md"
OUT_DIR="$WORK_DIR/outputs"

# 원래 사용자 워크스페이스 (포커스 복귀용)
ORIG_WS=""
if [[ -f "$WORK_DIR/original-workspace.txt" ]]; then
  ORIG_WS=$(cat "$WORK_DIR/original-workspace.txt")
fi

restore_focus() {
  [[ -n "$ORIG_WS" ]] && "$CMUX" select-workspace --workspace "$ORIG_WS" >/dev/null 2>&1 || true
}

# 내 역할 조회
LINE=$(awk -F'\t' -v n="$NUM" '$1==n{print; exit}' "$PLAN")
if [[ -z "$LINE" ]]; then
  echo "Error: plan.tsv 에 $NUM 없음" >&2
  exit 1
fi
IFS=$'\t' read -r _ NAME DIR PROMPT_FILE <<< "$LINE"

# 터미널 타이틀 설정 (cmux 사이드바 표시용 fallback)
printf '\033]0;%s\007' "$NAME"

# 탭 이름도 한 번 더 설정 (이미 부모가 설정했어도 재확인)
if [[ -n "${CMUX_SURFACE_ID:-}" ]]; then
  "$CMUX" rename-tab --surface "$CMUX_SURFACE_ID" --workspace "${CMUX_WORKSPACE_ID:-}" "$NAME" >/dev/null 2>&1 || true
fi

TASK=$(cat "$TASK_FILE")
OUT="$OUT_DIR/${NUM}-${NAME}.md"
SYS=$(cat "$PROMPT_FILE")

# 이전 단계 산출물 수집
CTX=""
for prev in "$OUT_DIR"/*.md; do
  [[ -e "$prev" ]] || continue
  [[ "$(basename "$prev")" == "${NUM}-${NAME}.md" ]] && continue
  CTX+=$'\n\n### '"$(basename "$prev" .md)"$'\n'"$(cat "$prev")"
done

if [[ -n "$CTX" ]]; then
  FULL_TASK=$'작업: '"$TASK"$'\n\n## 이전 단계 산출물'"$CTX"$'\n\n## 출력\n결과를 마크다운으로 작성.'
else
  FULL_TASK=$'작업: '"$TASK"$'\n\n## 출력\n결과를 마크다운으로 작성.'
fi

echo "▶ [$NAME] 작업 시작..."
echo ""

if claude -p --dangerously-skip-permissions --append-system-prompt="$SYS" "$FULL_TASK" > "$OUT" 2>&1; then
  echo ""
  echo "✓ [$NAME] 완료 → $OUT"
else
  echo ""
  echo "✗ [$NAME] 실패 (exit=$?) — 로그: $OUT" >&2
fi

# 기획(01)이면 next-roles 마커 파싱 → plan.tsv 필터링
# 빈 태그(<next-roles></next-roles>)는 기본 체인(03,05,07,11)으로 폴백
DEFAULT_CHAIN="03,05,07,11"
if [[ "$NUM" == "01" ]]; then
  if grep -qE '<next-roles>[^<]*</next-roles>' "$OUT"; then
    NEXT_ROLES=$(grep -oE '<next-roles>[^<]*</next-roles>' "$OUT" | sed 's|<next-roles>||; s|</next-roles>||' | tr -d ' ' | tail -1)
    if [[ -z "$NEXT_ROLES" ]]; then
      NEXT_ROLES="$DEFAULT_CHAIN"
      echo "[기획] 빈 next-roles 감지 — 기본 체인 강제: $NEXT_ROLES"
    else
      echo "[기획] 후속 역할 지정: $NEXT_ROLES"
    fi
    NEW_PLAN="$WORK_DIR/plan.tsv.new"
    awk -F'\t' -v n="01" '$1==n' "$PLAN" > "$NEW_PLAN"
    IFS=',' read -ra WANTED <<< "$NEXT_ROLES"
    for r in "${WANTED[@]}"; do
      [[ -z "$r" ]] && continue
      awk -F'\t' -v n="$r" '$1==n' "$PLAN" >> "$NEW_PLAN"
    done
    mv "$NEW_PLAN" "$PLAN"
  else
    echo "[기획] next-roles 마커 없음 — 기본 체인 강제: $DEFAULT_CHAIN"
    NEW_PLAN="$WORK_DIR/plan.tsv.new"
    awk -F'\t' -v n="01" '$1==n' "$PLAN" > "$NEW_PLAN"
    IFS=',' read -ra WANTED <<< "$DEFAULT_CHAIN"
    for r in "${WANTED[@]}"; do
      awk -F'\t' -v n="$r" '$1==n' "$PLAN" >> "$NEW_PLAN"
    done
    mv "$NEW_PLAN" "$PLAN"
  fi
fi

# 다음 역할 결정 (plan.tsv에서 현재 번호 다음 행)
NEXT_LINE=$(awk -F'\t' -v cur="$NUM" 'found{print; exit} $1==cur{found=1}' "$PLAN" || true)

if [[ -n "$NEXT_LINE" ]]; then
  IFS=$'\t' read -r NEXT_NUM NEXT_NAME NEXT_DIR _ <<< "$NEXT_LINE"
  echo "→ 다음 패널 열기: $NEXT_NAME"

  SPLIT_OUT=$("$CMUX" new-split "$NEXT_DIR" --workspace "${CMUX_WORKSPACE_ID}" --surface "${CMUX_SURFACE_ID}" 2>&1 || true)
  NEW=$(echo "$SPLIT_OUT" | grep -oE 'surface:[0-9]+' | head -1)
  sleep 0.4

  if [[ -n "$NEW" ]]; then
    "$CMUX" rename-tab --surface "$NEW" --workspace "${CMUX_WORKSPACE_ID}" "$NEXT_NAME" >/dev/null 2>&1 || true
    # 생성된 패널 ID 추적
    echo "$NEW" >> "$WORK_DIR/surfaces.txt"
    NEXT_CMD="bash $SKILL_DIR/role.sh $WORK_DIR $NEXT_NUM"
    "$CMUX" send --surface "$NEW" --workspace "${CMUX_WORKSPACE_ID}" "$NEXT_CMD" >/dev/null 2>&1 || true
    "$CMUX" send-key --surface "$NEW" --workspace "${CMUX_WORKSPACE_ID}" Enter >/dev/null 2>&1 || true
  else
    echo "경고: 다음 패널 생성 실패: $SPLIT_OUT" >&2
  fi
  # 사용자 포커스가 team-panels 워크스페이스로 끌려갔다면 원래 위치로 복귀
  restore_focus
  # 중간 역할: 자기 패널은 닫지 않고 그대로 유지 (모든 역할 끝나면 마지막 역할이 일괄 close)
  exit 0
fi

# 여기는 마지막 역할 경로 (단독 완결 포함)
echo ""
echo "✓ 모든 역할 완료 — 산출물: $OUT_DIR/"
echo "  5초 후 워크스페이스를 닫습니다..."
sleep 5

# 워크스페이스 close 전에 원래 사용자 워크스페이스로 포커스 미리 이동
restore_focus

# 워크스페이스 전체 close — 모든 패널이 한 번에 정리됨
WS_TO_CLOSE=""
if [[ -f "$WORK_DIR/workspace.txt" ]]; then
  WS_TO_CLOSE=$(cat "$WORK_DIR/workspace.txt")
fi
WS_TO_CLOSE="${WS_TO_CLOSE:-${CMUX_WORKSPACE_ID:-}}"

if [[ -n "$WS_TO_CLOSE" ]]; then
  "$CMUX" close-workspace --workspace "$WS_TO_CLOSE" >/dev/null 2>&1 || true
fi
