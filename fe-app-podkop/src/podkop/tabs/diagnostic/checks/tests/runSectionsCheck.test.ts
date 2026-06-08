import { beforeEach, describe, expect, it, vi } from 'vitest';

const mocks = vi.hoisted(() => ({
  getDashboardSections: vi.fn(),
  getClashApiProxyLatency: vi.fn(),
  updateCheckStore: vi.fn(),
}));

vi.mock('../../../../methods/custom/getDashboardSections', () => ({
  getDashboardSections: mocks.getDashboardSections,
}));

vi.mock('../../../../methods', () => ({
  PodkopShellMethods: {
    getClashApiProxyLatency: mocks.getClashApiProxyLatency,
  },
}));

vi.mock('../updateCheckStore', () => ({
  updateCheckStore: mocks.updateCheckStore,
}));

import { runSectionsCheck } from '../runSectionsCheck';

describe('runSectionsCheck', () => {
  beforeEach(() => {
    mocks.getDashboardSections.mockReset();
    mocks.getClashApiProxyLatency.mockReset();
    mocks.updateCheckStore.mockReset();
  });

  it('keeps VPN interface probe failures as warnings when the runtime outbound exists', async () => {
    mocks.getDashboardSections.mockResolvedValue({
      success: true,
      data: [
        {
          withTagSelect: false,
          code: 'AWG-out',
          sectionName: 'AWG',
          displayName: 'AWG',
          action: 'vpn',
          latencyTestTimeout: '10000',
          outbounds: [
            {
              code: 'AWG-out',
              displayName: 'awg1',
              latency: 0,
              type: 'Direct',
              selected: true,
              runtimeAvailable: true,
            },
          ],
        },
      ],
    });
    mocks.getClashApiProxyLatency.mockResolvedValue({
      success: true,
      data: { message: 'context deadline exceeded' },
    });

    await expect(runSectionsCheck()).resolves.toBeUndefined();

    expect(mocks.getClashApiProxyLatency).toHaveBeenCalledWith(
      'AWG-out',
      '10000',
    );
    expect(mocks.updateCheckStore).toHaveBeenLastCalledWith(
      expect.objectContaining({
        state: 'warning',
        description: 'Issues detected',
        items: [
          {
            state: 'warning',
            key: 'AWG',
            value: '[awg1] Connectivity probe failed',
          },
        ],
      }),
    );
  });
});
