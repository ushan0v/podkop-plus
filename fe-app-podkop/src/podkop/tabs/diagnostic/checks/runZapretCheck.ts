import { DIAGNOSTICS_CHECKS_MAP } from './contstants';
import { PodkopShellMethods } from '../../../methods';
import { updateCheckStore } from './updateCheckStore';

type CheckState = 'success' | 'warning' | 'error';

function boolText(value: boolean) {
  return value ? _('yes') : _('no');
}

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
  const standaloneActive = Boolean(
    data.standalone_service_running || data.standalone_service_enabled,
  );
  const queueOverlap = Boolean(data.queue_overlap);
  const legacyRuntimePresent = Boolean(data.legacy_runtime_present);
  const standaloneConflict = Boolean(data.standalone_conflict);

  let state: CheckState = 'success';
  let description = _('Checks passed');

  if (hasZapretRules && !providerAvailable) {
    state = 'error';
    description = _('Zapret provider is not available');
  } else if (hasZapretRules && !ready) {
    state = 'error';
    description = _('Podkop-managed nfqws is not ready');
  } else if (queueOverlap || legacyRuntimePresent) {
    state = 'error';
    description = _('Zapret conflict detected');
  } else if (!hasZapretRules && !providerAvailable) {
    state = 'warning';
    description = _('Zapret provider is not installed');
  } else if (standaloneConflict || standaloneActive) {
    state = 'warning';
    description = _('Standalone zapret may overlap with Podkop Plus');
  }

  updateCheckStore({
    order,
    code,
    title,
    description,
    state,
    items: [
      {
        state: providerAvailable
          ? 'success'
          : hasZapretRules
            ? 'error'
            : 'warning',
        key: _('Provider binary'),
        value: data.provider_path || '/opt/zapret/nfq/nfqws',
      },
      {
        state: packageInstalled
          ? 'success'
          : providerAvailable
            ? 'warning'
            : 'error',
        key: _('Zapret package installed'),
        value: boolText(packageInstalled),
      },
      {
        state: hasZapretRules ? 'success' : 'warning',
        key: hasZapretRules
          ? _('There are rules using zapret')
          : _('No rules use zapret'),
        value: `${Number(data.enabled_rule_count || 0)}`,
      },
      {
        state:
          !hasZapretRules ||
          data.running_process_count === data.expected_process_count
            ? 'success'
            : 'error',
        key: _('Podkop-managed nfqws processes'),
        value: `${Number(data.running_process_count || 0)} / ${Number(
          data.expected_process_count || 0,
        )}`,
      },
      {
        state:
          !hasZapretRules ||
          data.supervisor_process_count === data.expected_process_count
            ? 'success'
            : 'error',
        key: _('Podkop nfqws supervisors'),
        value: `${Number(data.supervisor_process_count || 0)} / ${Number(
          data.expected_process_count || 0,
        )}`,
      },
      {
        state: data.standalone_service_running ? 'warning' : 'success',
        key: _('Standalone zapret running'),
        value: boolText(Boolean(data.standalone_service_running)),
      },
      {
        state: data.standalone_service_enabled ? 'warning' : 'success',
        key: _('Standalone zapret enabled'),
        value: boolText(Boolean(data.standalone_service_enabled)),
      },
      {
        state: data.standalone_config_present ? 'warning' : 'success',
        key: _('/etc/config/zapret present'),
        value: boolText(Boolean(data.standalone_config_present)),
      },
      {
        state: data.luci_app_installed ? 'warning' : 'success',
        key: _('luci-app-zapret installed'),
        value: boolText(Boolean(data.luci_app_installed)),
      },
      {
        state: queueOverlap ? 'error' : 'success',
        key: _('NFQUEUE range'),
        value: `${Number(data.queue_base || 0)}-${Number(data.queue_range_end || 0)}`,
      },
      {
        state: legacyRuntimePresent ? 'error' : 'success',
        key: _('Legacy runtime paths'),
        value: boolText(legacyRuntimePresent),
      },
      {
        state: standaloneConflict ? 'warning' : 'success',
        key: _('Possible packet-level overlap'),
        value: boolText(standaloneConflict),
      },
    ],
  });
}
