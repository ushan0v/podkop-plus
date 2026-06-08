import { onMount, preserveScrollForPage } from '../../../helpers';
import { PODKOP_ACTION_PROVIDERS_AVAILABILITY_EVENT } from '../../../constants';
import { normalizeCompiledVersion } from '../../../helpers/normalizeCompiledVersion';
import { showToast } from '../../../helpers/showToast';
import {
  renderDownloadIcon24,
  renderRotateCcwIcon24,
  renderSearchIcon24,
  renderXIcon24,
} from '../../../icons';
import { renderButton } from '../../../partials';
import { getComponentActionKey } from '../../helpers/getComponentActionKey';
import type { UpdatesActionKey } from '../../helpers/getComponentActionKey';
import { isTransientRpcError } from '../../helpers/isTransientRpcError';
import { isActiveLuciTab } from '../../helpers/isActiveLuciTab';
import { shouldShowLoadingForRestoredAction } from '../../helpers/restoredActionLoading';
import {
  formatSingBoxVersion,
  normalizeSingBoxVariantFields,
} from '../../helpers/singBoxVariant';
import {
  hasLocalMutatingServiceActionLoading,
  isServiceTransitionStatus,
} from '../diagnostic/serviceTransition';
import { shouldApplyCompletedComponentActionResult } from './componentActionCompletion';
import {
  shouldPreserveCompletedCheckResultOnNextMount,
  shouldRefreshComponentStateBeforeRender,
  shouldResetCheckResultsOnMount,
} from './checkResultLifecycle';
import { PodkopShellMethods } from '../../methods';
import {
  logger,
  markUiActionOwned,
  setLocalComponentAction,
  shouldNotifyOwnedUiAction,
  store,
  StoreType,
} from '../../services';
import { ensureSystemInfo } from '../../services/systemInfo.service';
import {
  getCachedRuntimeUiState,
  refreshRuntimeUiState,
  subscribeRuntimeUiState,
} from '../../services/runtimeUiState.service';
import { Podkop } from '../../types';

type UpdateStatus = StoreType['updatesChecks'][Podkop.ComponentName]['status'];

interface ComponentActionButton {
  key: UpdatesActionKey;
  text: string;
  icon: () => SVGSVGElement;
  component: Podkop.ComponentName;
  action: Podkop.ComponentAction;
}

interface ComponentCard {
  title: string;
  version: string;
  latestVersion?: string;
  releaseUrl?: string;
  tag?: {
    label: string;
    kind: 'neutral' | 'success' | 'warning';
  };
  actions: ComponentActionButton[];
}

let updatesLifecycleRegistered = false;
let updatesControllerInitialized = false;
let updatesMounted = false;
let updatesMountId = 0;
let pageUnloading = false;
let preserveCheckResultsOnNextMount = false;
let componentActionStateUnsubscribe: (() => void) | null = null;
let componentActionStateRefreshPromise: Promise<void> | null = null;
const followedComponentJobs = new Set<string>();
const handledComponentJobs = new Set<string>();

if (typeof window !== 'undefined') {
  window.addEventListener('pagehide', () => {
    pageUnloading = true;
  });
  window.addEventListener('pageshow', () => {
    pageUnloading = false;
  });
}

function isNotInstalled(version: string | undefined) {
  return !version || version === 'not installed';
}

function getCheckTag(component: Podkop.ComponentName): ComponentCard['tag'] {
  const status = store.get().updatesChecks[component].status;

  if (!status) {
    return undefined;
  }

  if (status === 'latest') {
    return { label: _('Latest'), kind: 'success' };
  }

  if (status === 'outdated') {
    return { label: _('Outdated'), kind: 'warning' };
  }

  return { label: _('Dev'), kind: 'neutral' };
}

function shouldShowInstallAfterCheck(component: Podkop.ComponentName) {
  const status = store.get().updatesChecks[component].status;

  return status === 'outdated' || status === 'dev';
}

function getInstallActionText(component: Podkop.ComponentName) {
  if (shouldShowInstallAfterCheck(component)) {
    return _('Update');
  }

  return _('Install');
}

function getLatestVersion(component: Podkop.ComponentName) {
  const checkResult = store.get().updatesChecks[component];

  if (!shouldShowInstallAfterCheck(component)) {
    return undefined;
  }

  return checkResult.latest_version || undefined;
}

function getGitHubReleaseUrl(component: Podkop.ComponentName) {
  const checkResult = store.get().updatesChecks[component];

  if (!shouldShowInstallAfterCheck(component) || !checkResult.release_url) {
    return undefined;
  }

  return checkResult.release_url;
}

function isAnyActionLoading() {
  return Object.values(store.get().updatesActions).some((item) => item.loading);
}

function isServiceRuntimeActionLoading() {
  const state = store.get();

  return (
    hasLocalMutatingServiceActionLoading(state.diagnosticsActions) ||
    isServiceTransitionStatus(state.servicesInfoWidget.data.podkopStatus)
  );
}

function isSystemInfoLoading() {
  const systemInfo = store.get().diagnosticsSystemInfo;

  return systemInfo.loading || !systemInfo.loaded;
}

function setActionLoading(
  action: UpdatesActionKey,
  loading: boolean,
  local = false,
) {
  if (local || !loading) {
    setLocalComponentAction(action, loading && local);
  }

  const updatesActions = store.get().updatesActions;

  store.set({
    updatesActions: {
      ...updatesActions,
      [action]: { loading },
    },
  });
}

function beginComponentAction(button: ComponentActionButton) {
  if (isAnyActionLoading()) {
    return false;
  }

  setActionLoading(button.key, true, true);
  return true;
}

function setCheckResult(
  component: Podkop.ComponentName,
  status: UpdateStatus,
  latestVersion: string,
  releaseUrl: string = '',
) {
  const updatesChecks = store.get().updatesChecks;

  store.set({
    updatesChecks: {
      ...updatesChecks,
      [component]: {
        status,
        latest_version: latestVersion,
        release_url: releaseUrl,
      },
    },
  });
}

function resetCheckResult(component: Podkop.ComponentName) {
  setCheckResult(component, null, '');
}

function getErrorMessage(error: unknown, fallback: string) {
  return error instanceof Error && error.message ? error.message : fallback;
}

async function ackComponentActionJob(jobId: string) {
  try {
    const response = await PodkopShellMethods.uiActionAck('component', jobId);

    if (!response.success) {
      logger.debug('[UPDATES]', 'component action ack failed', response.error);
    }
  } catch (error) {
    logger.debug('[UPDATES]', 'component action ack failed', error);
  }
}

function getExpectedLatestVersionForAction(button: ComponentActionButton) {
  if (button.component !== 'podkop' || button.action !== 'install') {
    return undefined;
  }

  return (
    store.get().updatesChecks[button.component].latest_version || undefined
  );
}

function getCheckToastMessage(status: UpdateStatus) {
  if (status === 'outdated') {
    return _('Update is available');
  }

  if (status === 'dev') {
    return _('Installed version is newer than release');
  }

  return _('Latest version is installed');
}

async function refreshSystemInfoAfterMutation() {
  await ensureSystemInfo({ force: true, silent: true });
}

function notifyActionProvidersAvailabilityChanged(
  systemInfo: StoreType['diagnosticsSystemInfo'],
) {
  if (typeof window === 'undefined' || typeof CustomEvent === 'undefined') {
    return;
  }

  window.dispatchEvent(
    new CustomEvent(PODKOP_ACTION_PROVIDERS_AVAILABILITY_EVENT, {
      detail: {
        zapretInstalled: Boolean(systemInfo.zapret_installed),
        zapret2Installed: Boolean(systemInfo.zapret2_installed),
        byedpiInstalled: Boolean(systemInfo.byedpi_installed),
      },
    }),
  );
}

function reloadPageAfterPodkopUpdate() {
  window.setTimeout(() => {
    window.location.reload();
  }, 1200);
}

function patchSystemInfoAfterMutation(result: Podkop.ComponentActionResult) {
  const systemInfo = store.get().diagnosticsSystemInfo;
  const nextSystemInfo = { ...systemInfo, loading: false, loaded: true };
  const version =
    result.current_version || result.latest_version || _('unknown');

  if (result.component === 'podkop' && result.action === 'install') {
    nextSystemInfo.podkop_version = version;
  }

  if (result.component === 'sing_box') {
    nextSystemInfo.sing_box_version = version;

    if (result.action === 'install_extended') {
      nextSystemInfo.sing_box_extended = 1;
      nextSystemInfo.sing_box_tiny = 0;
      nextSystemInfo.sing_box_compressed = 0;
      nextSystemInfo.sing_box_tailscale = 1;
    }

    if (result.action === 'install_extended_compressed') {
      nextSystemInfo.sing_box_extended = 1;
      nextSystemInfo.sing_box_tiny = 0;
      nextSystemInfo.sing_box_compressed = 1;
      nextSystemInfo.sing_box_tailscale = 1;
    }

    if (result.action === 'install_stable') {
      nextSystemInfo.sing_box_extended = 0;
      nextSystemInfo.sing_box_tiny = 0;
      nextSystemInfo.sing_box_compressed = 0;
      nextSystemInfo.sing_box_tailscale = 1;
    }

    if (result.action === 'install_tiny') {
      nextSystemInfo.sing_box_extended = 0;
      nextSystemInfo.sing_box_tiny = 1;
      nextSystemInfo.sing_box_compressed = 0;
      nextSystemInfo.sing_box_tailscale = 0;
    }
  }

  if (result.component === 'zapret') {
    nextSystemInfo.providerInfoLoaded = true;

    if (result.action === 'remove') {
      nextSystemInfo.zapret_installed = 0;
      nextSystemInfo.zapret_version = 'not installed';
    } else {
      nextSystemInfo.zapret_installed = 1;
      nextSystemInfo.zapret_version = version;
    }
  }

  if (result.component === 'zapret2') {
    nextSystemInfo.providerInfoLoaded = true;

    if (result.action === 'remove') {
      nextSystemInfo.zapret2_installed = 0;
      nextSystemInfo.zapret2_version = 'not installed';
    } else {
      nextSystemInfo.zapret2_installed = 1;
      nextSystemInfo.zapret2_version = version;
    }
  }

  if (result.component === 'byedpi') {
    nextSystemInfo.providerInfoLoaded = true;

    if (result.action === 'remove') {
      nextSystemInfo.byedpi_installed = 0;
      nextSystemInfo.byedpi_version = 'not installed';
    } else {
      nextSystemInfo.byedpi_installed = 1;
      nextSystemInfo.byedpi_version = version;
    }
  }

  const normalizedSystemInfo = normalizeSingBoxVariantFields(nextSystemInfo);

  store.set({
    diagnosticsSystemInfo: normalizedSystemInfo,
  });

  if (
    result.component === 'zapret' ||
    result.component === 'zapret2' ||
    result.component === 'byedpi'
  ) {
    notifyActionProvidersAvailabilityChanged(normalizedSystemInfo);
  }
}

async function applyCompletedComponentAction({
  key,
  result,
  notify,
}: {
  key: UpdatesActionKey;
  result: Podkop.ComponentActionResult;
  notify: boolean;
}) {
  if (result.action === 'check_update') {
    setActionLoading(key, false);

    if (!shouldApplyCompletedComponentActionResult(result, notify)) {
      return;
    }

    if (
      shouldPreserveCompletedCheckResultOnNextMount({
        action: result.action,
        mounted: updatesMounted,
      })
    ) {
      preserveCheckResultsOnNextMount = true;
    }

    const status = result.status || null;

    if (status === 'latest' || status === 'outdated' || status === 'dev') {
      setCheckResult(
        result.component,
        status,
        result.latest_version || '',
        result.release_url || '',
      );
    }

    if (notify) {
      showToast(getCheckToastMessage(status), 'success');
    }
    return;
  }

  if (result.action === 'install' || result.action.startsWith('install_')) {
    setCheckResult(result.component, 'latest', result.latest_version || '');
  } else {
    resetCheckResult(result.component);
  }

  patchSystemInfoAfterMutation(result);
  setActionLoading(key, false);

  if (result.component === 'podkop' && result.action === 'install') {
    if (notify && result.message) {
      showToast(result.message, 'success', 1200);
    }

    if (notify) {
      reloadPageAfterPodkopUpdate();
    }
    return;
  }

  if (notify && result.message) {
    showToast(result.message, 'success');
  }

  void refreshSystemInfoAfterMutation();
}

async function completeComponentActionJob(
  key: UpdatesActionKey,
  jobId: string,
  response: Podkop.MethodResponse<Podkop.ComponentActionResult>,
) {
  if (pageUnloading) {
    setActionLoading(key, false);
    return;
  }

  const alreadyHandled = handledComponentJobs.has(jobId);

  if (alreadyHandled) {
    setActionLoading(key, false);
    return;
  }

  const shouldNotify = shouldNotifyOwnedUiAction('component', jobId);

  if (!response.success || response.data.success === false) {
    const message = response.success
      ? response.data.message || _('Failed to execute')
      : response.error || _('Failed to execute');

    if (isTransientRpcError(message)) {
      setActionLoading(key, false);
      void refreshComponentActionState();
      return;
    }

    handledComponentJobs.add(jobId);
    setActionLoading(key, false);
    if (shouldNotify) {
      showToast(message, 'error');
    }
    await ackComponentActionJob(jobId);
    return;
  }

  handledComponentJobs.add(jobId);
  await ackComponentActionJob(jobId);
  await applyCompletedComponentAction({
    key,
    result: response.data,
    notify: shouldNotify,
  });
}

async function followComponentActionState(state: Podkop.ComponentActionResult) {
  const jobId = state.job_id;
  const key = getComponentActionKey(state.component, state.action);

  if (!jobId || !key || followedComponentJobs.has(jobId)) {
    return;
  }

  if (!state.running && handledComponentJobs.has(jobId)) {
    return;
  }

  followedComponentJobs.add(jobId);
  if (shouldShowLoadingForRestoredAction(state)) {
    setActionLoading(key, true);
  }

  try {
    const response = state.running
      ? await PodkopShellMethods.waitComponentActionJob(
          jobId,
          state.component,
          state.action,
          state.latest_version || undefined,
        )
      : ({
          success: true,
          data: state,
        } as Podkop.MethodSuccessResponse<Podkop.ComponentActionResult>);

    await completeComponentActionJob(key, jobId, response);
  } catch (error) {
    logger.error('[UPDATES]', 'followComponentActionState failed', error);
    if (!pageUnloading) {
      const message = getErrorMessage(error, _('Failed to execute'));

      setActionLoading(key, false);
      if (!isTransientRpcError(message)) {
        showToast(message, 'error');
      }
    }
  } finally {
    followedComponentJobs.delete(jobId);
  }
}

async function followAlreadyRunningComponentAction(
  button: ComponentActionButton,
) {
  const uiState = await refreshRuntimeUiState({ force: true });

  if (!uiState) {
    return false;
  }

  const state = uiState.actions.component.find(
    (item) =>
      item.running &&
      item.component === button.component &&
      item.action === button.action,
  );

  if (!state) {
    return false;
  }

  if (state.job_id) {
    markUiActionOwned('component', state.job_id);
  }
  await followComponentActionState(state);
  return true;
}

function isComponentActionAlreadyRunningError(message: string | undefined) {
  return Boolean(
    message && message.includes('Another component action is already running'),
  );
}

function handleComponentUiState(uiState: Podkop.UiState) {
  for (const state of uiState.actions.component || []) {
    void followComponentActionState(state);
  }
}

async function refreshComponentActionState() {
  if (componentActionStateRefreshPromise) {
    return componentActionStateRefreshPromise;
  }

  componentActionStateRefreshPromise = (async () => {
    if (!updatesMounted) {
      return;
    }

    const state = await refreshRuntimeUiState({ force: true });

    if (!state) {
      return;
    }

    handleComponentUiState(state);
  })().finally(() => {
    componentActionStateRefreshPromise = null;
  });

  return componentActionStateRefreshPromise;
}

function startComponentActionStateWatcher() {
  if (componentActionStateUnsubscribe) {
    return;
  }

  componentActionStateUnsubscribe = subscribeRuntimeUiState((uiState) => {
    if (updatesMounted) {
      handleComponentUiState(uiState);
    }
  });
}

function stopComponentActionStateWatcher() {
  if (!componentActionStateUnsubscribe) {
    return;
  }

  componentActionStateUnsubscribe();
  componentActionStateUnsubscribe = null;
}

async function handleComponentAction(button: ComponentActionButton) {
  if (!beginComponentAction(button)) {
    return;
  }

  let jobId = '';
  let ownsJobFollow = false;

  try {
    const startResponse = await PodkopShellMethods.componentActionStart(
      button.component,
      button.action,
    );

    if (!startResponse.success) {
      if (isComponentActionAlreadyRunningError(startResponse.error)) {
        setActionLoading(button.key, false);
        if (!(await followAlreadyRunningComponentAction(button))) {
          await refreshComponentActionState();
        }
        return;
      }

      if (isTransientRpcError(startResponse.error)) {
        if (!(await followAlreadyRunningComponentAction(button))) {
          setActionLoading(button.key, false);
          await refreshComponentActionState();
        }
        return;
      }

      throw new Error(startResponse.error);
    }

    jobId = startResponse.data.job_id;
    markUiActionOwned('component', jobId);
    if (followedComponentJobs.has(jobId)) {
      return;
    }

    followedComponentJobs.add(jobId);
    ownsJobFollow = true;

    const response = await PodkopShellMethods.waitComponentActionJob(
      jobId,
      button.component,
      button.action,
      getExpectedLatestVersionForAction(button),
    );

    await completeComponentActionJob(button.key, jobId, response);
  } catch (error) {
    logger.error('[UPDATES]', 'handleComponentAction failed', error);
    if (!pageUnloading) {
      const message = getErrorMessage(error, _('Failed to execute'));

      setActionLoading(button.key, false);
      if (!isTransientRpcError(message)) {
        showToast(message, 'error');
      }
      void refreshComponentActionState();
    }
  } finally {
    if (ownsJobFollow) {
      followedComponentJobs.delete(jobId);
    }
  }
}

function getPrimaryUpdateAction(
  component: Podkop.ComponentName,
  checkKey: UpdatesActionKey,
  installKey: UpdatesActionKey,
): ComponentActionButton {
  if (shouldShowInstallAfterCheck(component)) {
    return {
      key: installKey,
      text: getInstallActionText(component),
      icon: renderRotateCcwIcon24,
      component,
      action: 'install',
    };
  }

  return {
    key: checkKey,
    text: _('Check update'),
    icon: renderSearchIcon24,
    component,
    action: 'check_update',
  };
}

function getComponentCards(): ComponentCard[] {
  const systemInfo = normalizeSingBoxVariantFields(
    store.get().diagnosticsSystemInfo,
  );
  const systemInfoLoading = isSystemInfoLoading();
  const zapretInstalled = Boolean(systemInfo.zapret_installed);
  const zapret2Installed = Boolean(systemInfo.zapret2_installed);
  const byedpiInstalled = Boolean(systemInfo.byedpi_installed);
  const singBoxInstalled = !isNotInstalled(systemInfo.sing_box_version);
  const singBoxStable =
    singBoxInstalled &&
    !systemInfo.sing_box_extended &&
    !systemInfo.sing_box_tiny;
  const singBoxExtended =
    Boolean(systemInfo.sing_box_extended) && !systemInfo.sing_box_compressed;
  const singBoxExtendedCompressed =
    Boolean(systemInfo.sing_box_extended) &&
    Boolean(systemInfo.sing_box_compressed);
  const singBoxTiny = Boolean(systemInfo.sing_box_tiny);
  const singBoxActions: ComponentActionButton[] = [
    getPrimaryUpdateAction('sing_box', 'singBoxCheck', 'singBoxInstall'),
  ];

  if (!singBoxStable) {
    singBoxActions.push({
      key: 'singBoxInstallStable',
      text: _('Install stable'),
      icon: renderDownloadIcon24,
      component: 'sing_box',
      action: 'install_stable',
    });
  }

  if (!singBoxTiny) {
    singBoxActions.push({
      key: 'singBoxInstallTiny',
      text: _('Install tiny'),
      icon: renderDownloadIcon24,
      component: 'sing_box',
      action: 'install_tiny',
    });
  }

  if (!singBoxExtended) {
    singBoxActions.push({
      key: 'singBoxInstallExtended',
      text: _('Install extended'),
      icon: renderDownloadIcon24,
      component: 'sing_box',
      action: 'install_extended',
    });
  }

  if (!singBoxExtendedCompressed) {
    singBoxActions.push({
      key: 'singBoxInstallExtendedCompressed',
      text: _('Install extended compressed'),
      icon: renderDownloadIcon24,
      component: 'sing_box',
      action: 'install_extended_compressed',
    });
  }

  return [
    {
      title: 'Podkop Plus',
      version: normalizeCompiledVersion(systemInfo.podkop_version),
      latestVersion: getLatestVersion('podkop'),
      releaseUrl: getGitHubReleaseUrl('podkop'),
      tag: getCheckTag('podkop'),
      actions: [
        getPrimaryUpdateAction('podkop', 'podkopCheck', 'podkopInstall'),
      ],
    },
    {
      title: 'Sing-box',
      version: formatSingBoxVersion(systemInfo),
      latestVersion: getLatestVersion('sing_box'),
      releaseUrl: getGitHubReleaseUrl('sing_box'),
      tag: getCheckTag('sing_box'),
      actions: singBoxActions,
    },
    {
      title: 'Zapret',
      version: systemInfoLoading
        ? 'loading'
        : zapretInstalled
          ? systemInfo.zapret_version
          : _('Not installed'),
      latestVersion: getLatestVersion('zapret'),
      releaseUrl: getGitHubReleaseUrl('zapret'),
      tag: zapretInstalled ? getCheckTag('zapret') : undefined,
      actions: zapretInstalled
        ? [
            getPrimaryUpdateAction('zapret', 'zapretCheck', 'zapretInstall'),
            {
              key: 'zapretRemove',
              text: _('Remove'),
              icon: renderXIcon24,
              component: 'zapret',
              action: 'remove',
            },
          ]
        : [
            {
              key: 'zapretInstall',
              text: _('Install'),
              icon: renderDownloadIcon24,
              component: 'zapret',
              action: 'install',
            },
          ],
    },
    {
      title: 'Zapret2',
      version: systemInfoLoading
        ? 'loading'
        : zapret2Installed
          ? systemInfo.zapret2_version
          : _('Not installed'),
      latestVersion: getLatestVersion('zapret2'),
      releaseUrl: getGitHubReleaseUrl('zapret2'),
      tag: zapret2Installed ? getCheckTag('zapret2') : undefined,
      actions: zapret2Installed
        ? [
            getPrimaryUpdateAction('zapret2', 'zapret2Check', 'zapret2Install'),
            {
              key: 'zapret2Remove',
              text: _('Remove'),
              icon: renderXIcon24,
              component: 'zapret2',
              action: 'remove',
            },
          ]
        : [
            {
              key: 'zapret2Install',
              text: _('Install'),
              icon: renderDownloadIcon24,
              component: 'zapret2',
              action: 'install',
            },
          ],
    },
    {
      title: 'ByeDPI',
      version: systemInfoLoading
        ? 'loading'
        : byedpiInstalled
          ? systemInfo.byedpi_version
          : _('Not installed'),
      latestVersion: getLatestVersion('byedpi'),
      releaseUrl: getGitHubReleaseUrl('byedpi'),
      tag: byedpiInstalled ? getCheckTag('byedpi') : undefined,
      actions: byedpiInstalled
        ? [
            getPrimaryUpdateAction('byedpi', 'byedpiCheck', 'byedpiInstall'),
            {
              key: 'byedpiRemove',
              text: _('Remove'),
              icon: renderXIcon24,
              component: 'byedpi',
              action: 'remove',
            },
          ]
        : [
            {
              key: 'byedpiInstall',
              text: _('Install'),
              icon: renderDownloadIcon24,
              component: 'byedpi',
              action: 'install',
            },
          ],
    },
  ];
}

function renderComponentTag(card: ComponentCard) {
  if (!card.tag) {
    return null;
  }

  return E(
    'span',
    {
      class: [
        'pdk_updates-page__component__tag',
        card.tag.kind === 'success'
          ? 'pdk_updates-page__component__tag--success'
          : '',
        card.tag.kind === 'warning'
          ? 'pdk_updates-page__component__tag--warning'
          : '',
      ]
        .filter(Boolean)
        .join(' '),
    },
    card.tag.label,
  );
}

function renderComponentCard(card: ComponentCard) {
  const updatesActions = store.get().updatesActions;
  const anyActionLoading = isAnyActionLoading();
  const serviceRuntimeActionLoading = isServiceRuntimeActionLoading();
  const systemInfoLoading = isSystemInfoLoading();
  const tag = renderComponentTag(card);
  const headerChildren: Node[] = [
    E('b', { class: 'pdk_updates-page__component__title' }, card.title),
  ];
  const statusChildren: Node[] = [];

  if (card.releaseUrl) {
    statusChildren.push(
      E(
        'a',
        {
          class: 'pdk_updates-page__component__release-link',
          href: card.releaseUrl,
          target: '_blank',
          rel: 'noopener noreferrer',
        },
        card.latestVersion
          ? _('Latest: %s').replace('%s', card.latestVersion)
          : _('Latest release'),
      ),
    );
  }

  if (tag) {
    statusChildren.push(tag);
  }

  if (statusChildren.length > 0) {
    headerChildren.push(
      E(
        'div',
        { class: 'pdk_updates-page__component__status' },
        statusChildren,
      ),
    );
  }

  return E('div', { class: 'pdk_updates-page__component' }, [
    E('div', { class: 'pdk_updates-page__component__header' }, headerChildren),
    E('div', { class: 'pdk_updates-page__component__version' }, [
      E(
        'span',
        { class: 'pdk_updates-page__component__version__label' },
        _('Version'),
      ),
      E(
        'span',
        { class: 'pdk_updates-page__component__version__value' },
        card.version,
      ),
    ]),
    E(
      'div',
      { class: 'pdk_updates-page__component__actions' },
      card.actions.map((action) => {
        const loading = updatesActions[action.key].loading;

        return renderButton({
          text: action.text,
          icon: action.icon,
          loading,
          disabled:
            systemInfoLoading ||
            serviceRuntimeActionLoading ||
            (anyActionLoading && !loading),
          onClick: () => void handleComponentAction(action),
        });
      }),
    ),
  ]);
}

function renderUpdatesComponents() {
  const container = document.getElementById('pdk_updates-components');

  if (!container) {
    return;
  }

  const columns = [[], []] as Node[][];
  getComponentCards().forEach((card, index) => {
    columns[index % 2].push(renderComponentCard(card));
  });

  return preserveScrollForPage(() => {
    container.replaceChildren(
      E('div', { class: 'pdk_updates-page__components-column' }, columns[0]),
      E('div', { class: 'pdk_updates-page__components-column' }, columns[1]),
    );
  });
}

function onStoreUpdate(
  _next: StoreType,
  _prev: StoreType,
  diff: Partial<StoreType>,
) {
  if (
    diff.diagnosticsSystemInfo ||
    diff.updatesActions ||
    diff.updatesChecks ||
    diff.diagnosticsActions ||
    diff.servicesInfoWidget
  ) {
    renderUpdatesComponents();
  }
}

async function onPageMount() {
  onPageUnmount();

  updatesMounted = true;
  updatesMountId += 1;
  const mountId = updatesMountId;
  const cachedRuntimeState = getCachedRuntimeUiState();
  const hasRuntimeSnapshot = Boolean(cachedRuntimeState);
  const needsFreshStateBeforeRender =
    shouldRefreshComponentStateBeforeRender(cachedRuntimeState);

  if (!hasRuntimeSnapshot || needsFreshStateBeforeRender) {
    await refreshRuntimeUiState({ force: true });

    if (!updatesMounted || mountId !== updatesMountId) {
      return;
    }
  }

  if (
    shouldResetCheckResultsOnMount({
      anyActionLoading: isAnyActionLoading(),
      preserveCheckResultsOnNextMount,
    })
  ) {
    store.reset(['updatesChecks']);
  }
  preserveCheckResultsOnNextMount = false;
  store.subscribe(onStoreUpdate);
  startComponentActionStateWatcher();
  renderUpdatesComponents();
  void ensureSystemInfo();
  if (hasRuntimeSnapshot) {
    void refreshRuntimeUiState({ force: true });
  }
}

function onPageUnmount() {
  updatesMounted = false;
  updatesMountId += 1;
  stopComponentActionStateWatcher();
  store.unsubscribe(onStoreUpdate);
}

function registerLifecycleListeners() {
  if (updatesLifecycleRegistered) {
    return;
  }

  updatesLifecycleRegistered = true;

  store.subscribe((next, prev, diff) => {
    if (
      diff.tabService &&
      next.tabService.current !== prev.tabService.current
    ) {
      const isUpdatesVisible = next.tabService.current === 'updates';

      if (isUpdatesVisible) {
        return onPageMount();
      }

      if (updatesMounted) {
        return onPageUnmount();
      }
    }
  });
}

export async function initController(): Promise<void> {
  if (updatesControllerInitialized) {
    return;
  }

  updatesControllerInitialized = true;

  onMount('updates-status').then(() => {
    logger.debug('[UPDATES]', 'initController', 'onMount');
    registerLifecycleListeners();
    if (
      store.get().tabService.current === 'updates' ||
      isActiveLuciTab('updates')
    ) {
      onPageMount();
    }
  });
}
