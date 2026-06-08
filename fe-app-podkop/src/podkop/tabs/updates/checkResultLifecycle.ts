import type { Podkop } from '../../types';

export function shouldPreserveCompletedCheckResultOnNextMount({
  action,
  mounted,
}: {
  action: Podkop.ComponentAction;
  mounted: boolean;
}) {
  return action === 'check_update' && !mounted;
}

export function shouldResetCheckResultsOnMount({
  anyActionLoading,
  preserveCheckResultsOnNextMount,
}: {
  anyActionLoading: boolean;
  preserveCheckResultsOnNextMount: boolean;
}) {
  return !anyActionLoading && !preserveCheckResultsOnNextMount;
}

export function shouldRefreshComponentStateBeforeRender(
  uiState?: Pick<Podkop.UiState, 'actions'>,
) {
  return Boolean(
    uiState?.actions.component.some((state) => state.running === true),
  );
}
