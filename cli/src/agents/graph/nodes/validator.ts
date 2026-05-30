import { AgentGraphState } from '../state';
import { PlanningHarness } from '../../harness';

export async function validatorNode(
  state: AgentGraphState,
  onChunk: (data: any) => void
): Promise<AgentGraphState> {
  const nextState = structuredClone(state);

  // 1. specifier 노드에서 이미 형식/세이프가드 에러가 수집된 경우
  if (nextState.validationErrors && nextState.validationErrors.length > 0) {
    nextState.attempts++;
    if (nextState.attempts >= nextState.maxAttempts) {
      onChunk({ 
        type: 'status', 
        chunk: `\n\n*⚠️ [기획 하네스 반려] AI가 규격에 맞는 기획서를 생성하는 데 실패했습니다. 오류 내역이 상단에 기록되며, 최종 수동 중재 모드로 전환합니다.*` 
      });
      nextState.currentRoute = 'end';
      nextState.isDone = true;
    } else {
      nextState.currentRoute = 'specifier';
    }
    return nextState;
  }

  // 2. 사양 업데이트(specUpdate)가 존재하는 경우 하네스 린터 검증 수행
  if (nextState.tempSpecUpdate) {
    onChunk({ type: 'status', chunk: `\n*[PlanningHarness를 통한 명세 검증 Assert를 돌리고 있습니다...]*\n` });

    const validation = PlanningHarness.validateSection(nextState.tempSpecUpdate);

    if (validation.isValid) {
      onChunk({ type: 'status', chunk: `\n*[기획 하네스 최종 검증 완료: 합격]*\n` });
      nextState.validationErrors = undefined;
      nextState.previousAttempt = undefined;
      nextState.currentRoute = 'end';
      nextState.isDone = true;
    } else {
      nextState.validationErrors = validation.errors;
      nextState.attempts++;

      if (nextState.attempts >= nextState.maxAttempts) {
        onChunk({ 
          type: 'status', 
          chunk: `\n\n*⚠️ [기획 하네스 반려] AI가 규격에 맞는 기획서를 생성하는 데 실패했습니다. 오류 내역이 상단에 기록되며, 최종 수동 중재 모드로 전환합니다.*` 
        });
        nextState.currentRoute = 'end';
        nextState.isDone = true;
      } else {
        nextState.currentRoute = 'specifier';
      }
    }
  } else {
    // 3. specUpdate가 없는 일반 채팅은 하네스 루프 없이 즉시 종료
    nextState.validationErrors = undefined;
    nextState.previousAttempt = undefined;
    nextState.currentRoute = 'end';
    nextState.isDone = true;
  }

  return nextState;
}
