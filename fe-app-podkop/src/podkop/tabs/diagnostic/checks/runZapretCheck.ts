import { DIAGNOSTICS_CHECKS_MAP } from './contstants';
import { PodkopShellMethods } from '../../../methods';
import { updateCheckStore } from './updateCheckStore';
import { IDiagnosticsChecksItem } from '../../../services';

type CheckState = 'success' | 'warning' | 'error';

export async function runZapretCheck() {
  const { order, title, code } = DIAGNOSTICS_CHECKS_MAP.ZAPRET;

  updateCheckStore({
    order,
    code,
    title,
    description: _('Checking, please wait'),
    state: 'loading',
    items: [],
  });

  const zapretStatus = await PodkopShellMethods.getZapretStatus();

  if (!zapretStatus.success) {
    updateCheckStore({
      order,
      code,
      title,
      description: _('Cannot receive checks result'),
      state: 'error',
      items: [],
    });

    throw new Error('Zapret checks failed');
  }

  const data = zapretStatus.data;
  const providerAvailable = Boolean(data.provider_available ?? data.installed);
  const packageInstalled = Boolean(data.package_installed);
  const hasZapretRules = Number(data.enabled_rule_count || 0) > 0;
  const ready = Boolean(data.ready);
  const queueOverlap = Boolean(data.queue_overlap);
  const standaloneServiceRunning = Boolean(data.standalone_service_running);
  const standaloneConflict = hasZapretRules && standaloneServiceRunning;
  const expectedProcesses = Number(data.expected_process_count || 0);
  const runningProcesses = Number(data.running_process_count || 0);
  const supervisorProcesses = Number(data.supervisor_process_count || 0);
  const podkopRuntimeReady =
    !hasZapretRules ||
    (runningProcesses === expectedProcesses &&
      supervisorProcesses === expectedProcesses);
  const unexpectedRuntime =
    !hasZapretRules && (runningProcesses > 0 || supervisorProcesses > 0);

  let state: CheckState = 'success';
  let description = _('Checks passed');

  if (hasZapretRules && !providerAvailable) {
    state = 'error';
    description = _('Checks failed');
  } else if (hasZapretRules && !ready) {
    state = 'error';
    description = _('Checks failed');
  } else if (queueOverlap) {
    state = 'error';
    description = _('Checks failed');
  } else if (!hasZapretRules && !providerAvailable) {
    state = 'warning';
    description = _('Issues detected');
  } else if (standaloneConflict) {
    state = 'warning';
    description = _('Issues detected');
  }

  const items: Array<IDiagnosticsChecksItem> = [
    {
      state: providerAvailable
        ? 'success'
        : hasZapretRules
          ? 'error'
          : 'warning',
      key: providerAvailable
        ? _('Zapret provider binary is available')
        : _('Zapret provider binary is not available'),
      value: '',
    },
    {
      state: packageInstalled
        ? 'success'
        : hasZapretRules
          ? 'error'
          : 'warning',
      key: packageInstalled
        ? _('Zapret package is installed')
        : _('Zapret package is not installed'),
      value: '',
    },
    {
      state: hasZapretRules && !providerAvailable ? 'error' : 'success',
      key: hasZapretRules
        ? _('There are rules using Zapret')
        : _('No rules use Zapret'),
      value: '',
    },
    {
      state: unexpectedRuntime || !podkopRuntimeReady ? 'error' : 'success',
      key: hasZapretRules
        ? podkopRuntimeReady
          ? _('Podkop-managed nfqws runtime is ready')
          : _('Podkop-managed nfqws runtime is not ready')
        : unexpectedRuntime
          ? _('Unexpected Podkop-managed nfqws runtime is running')
          : _('Podkop-managed nfqws runtime is not running'),
      value: '',
    },
    {
      state: queueOverlap ? 'error' : 'success',
      key: queueOverlap
        ? _('NFQUEUE range overlaps with another rule')
        : _('NFQUEUE range is available'),
      value: `${Number(data.queue_base || 0)}-${Number(data.queue_range_end || 0)}`,
    },
    {
      state: standaloneConflict ? 'warning' : 'success',
      key: standaloneServiceRunning
        ? hasZapretRules
          ? _('Standalone Zapret is active together with Podkop Zapret rules')
          : _('Standalone Zapret service is active')
        : _('Standalone Zapret service is inactive'),
      value: '',
    },
  ];

  updateCheckStore({
    order,
    code,
    title,
    description,
    state,
    items,
  });
}
