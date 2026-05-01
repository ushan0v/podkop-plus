import { insertIf } from '../../../../helpers';
import { DIAGNOSTICS_CHECKS_MAP } from './contstants';
import { PodkopShellMethods, RemoteFakeIPMethods } from '../../../methods';
import { IDiagnosticsChecksItem } from '../../../services';
import { updateCheckStore } from './updateCheckStore';
import { getMeta } from '../helpers/getMeta';

export async function runFakeIPCheck() {
  const { order, title, code } = DIAGNOSTICS_CHECKS_MAP.FAKEIP;

  updateCheckStore({
    order,
    code,
    title,
    description: _('Checking, please wait'),
    state: 'loading',
    items: [],
  });

  const routerFakeIPResponse = await PodkopShellMethods.checkFakeIP();
  const checkFakeIPResponse = await RemoteFakeIPMethods.getFakeIpCheck();
  const checkIPResponse = await RemoteFakeIPMethods.getIpCheck();

  const checks = {
    singBoxFakeIP:
      routerFakeIPResponse.success && routerFakeIPResponse.data.fakeip,
    browserFakeIP:
      checkFakeIPResponse.success && checkFakeIPResponse.data.fakeip,
    differentIP:
      checkFakeIPResponse.success &&
      checkIPResponse.success &&
      checkFakeIPResponse.data.IP !== checkIPResponse.data.IP,
  };

  const allGood =
    checks.singBoxFakeIP && checks.browserFakeIP && checks.differentIP;
  const atLeastOneGood =
    checks.singBoxFakeIP || checks.browserFakeIP || checks.differentIP;

  const { state, description } = getMeta({ atLeastOneGood, allGood });

  updateCheckStore({
    order,
    code,
    title,
    description,
    state,
    items: [
      {
        state: checks.singBoxFakeIP ? 'success' : 'error',
        key: checks.singBoxFakeIP
          ? _('Sing-box FakeIP DNS works')
          : _('Sing-box FakeIP DNS does not work'),
        value: routerFakeIPResponse.success ? routerFakeIPResponse.data.IP : '',
      },
      {
        state: checks.browserFakeIP ? 'success' : 'error',
        key: checks.browserFakeIP
          ? _('Browser is using FakeIP correctly')
          : _('Browser is not using FakeIP'),
        value: '',
      },
      ...insertIf<IDiagnosticsChecksItem>(checks.browserFakeIP, [
        {
          state: checks.differentIP ? 'success' : 'error',
          key: checks.differentIP
            ? _('Proxy traffic is routed via FakeIP')
            : _('Proxy traffic is not routed via FakeIP'),
          value: '',
        },
      ]),
    ],
  });
}
