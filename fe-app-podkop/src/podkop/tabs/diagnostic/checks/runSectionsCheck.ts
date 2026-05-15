import { DIAGNOSTICS_CHECKS_MAP } from './contstants';
import { PodkopShellMethods } from '../../../methods';
import { updateCheckStore } from './updateCheckStore';
import { getMeta } from '../helpers/getMeta';
import { getDashboardSections } from '../../../methods/custom/getDashboardSections';
import { IDiagnosticsChecksItem } from '../../../services';

export async function runSectionsCheck() {
  const { order, title, code } = DIAGNOSTICS_CHECKS_MAP.OUTBOUNDS;

  updateCheckStore({
    order,
    code,
    title,
    description: _('Checking, please wait'),
    state: 'loading',
    items: [],
  });

  const sections = await getDashboardSections({
    includeSubscriptionCopyState: false,
  });

  if (!sections.success) {
    updateCheckStore({
      order,
      code,
      title,
      description: _('Cannot receive checks result'),
      state: 'error',
      items: [],
    });

    throw new Error('Rule outbounds checks failed');
  }

  const items: Array<IDiagnosticsChecksItem> = [];

  for (const section of sections.data) {
    async function getLatency() {
      if (section.withTagSelect) {
        const latencyGroup = await PodkopShellMethods.getClashApiGroupLatency(
          section.code,
        );

        const selectedOutbound =
          section.outbounds.find((item) => item.selected) ??
          section.outbounds.find(
            (item) => item.type?.toLowerCase() === 'urltest',
          ) ??
          section.outbounds[0];

        const isUrlTest = selectedOutbound?.type?.toLowerCase() === 'urltest';

        const success = latencyGroup.success && !latencyGroup.data.message;

        if (success) {
          if (isUrlTest) {
            const latency = Object.values(latencyGroup.data)
              .map((item) => (item ? `${item}ms` : 'n/a'))
              .join(' / ');

            return {
              success: true,
              latency: `[${_('Fastest')}] ${latency}`,
            };
          }

          const selectedProxyDelay =
            latencyGroup.data?.[selectedOutbound?.code ?? ''];

          if (selectedProxyDelay) {
            return {
              success: true,
              latency: `[${selectedOutbound?.displayName ?? ''}] ${selectedProxyDelay}ms`,
            };
          }

          return {
            success: false,
            latency: `[${selectedOutbound?.displayName ?? ''}] ${_('Not responding')}`,
          };
        }

        return {
          success: false,
          latency: _('Not responding'),
        };
      }

      const latencyProxy = await PodkopShellMethods.getClashApiProxyLatency(
        section.code,
      );

      const success = latencyProxy.success && !latencyProxy.data.message;

      if (success) {
        return {
          success: true,
          latency: `${latencyProxy.data.delay} ms`,
        };
      }

      return {
        success: false,
        latency: _('Not responding'),
      };
    }

    const { latency, success } = await getLatency();

    items.push({
      state: success ? 'success' : 'error',
      key: section.displayName,
      value: latency,
    });
  }

  const allGood = items.every((item) => item.state === 'success');

  const atLeastOneGood = items.some((item) => item.state === 'success');

  const { state, description } = getMeta({ atLeastOneGood, allGood });

  updateCheckStore({
    order,
    code,
    title,
    description,
    state,
    items,
  });

  if (!atLeastOneGood) {
    throw new Error('Rule outbounds checks failed');
  }
}
