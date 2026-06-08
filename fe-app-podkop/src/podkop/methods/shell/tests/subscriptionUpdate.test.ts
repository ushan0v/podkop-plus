import { afterEach, beforeEach, describe, expect, it, vi } from 'vitest';

const mocks = vi.hoisted(() => ({
  executeShellCommand: vi.fn(),
}));

vi.mock('../../../../helpers', () => ({
  executeShellCommand: mocks.executeShellCommand,
}));

import { PodkopShellMethods } from '../index';

describe('PodkopShellMethods.subscriptionUpdate', () => {
  beforeEach(() => {
    vi.useFakeTimers();
    mocks.executeShellCommand.mockReset();
  });

  afterEach(() => {
    vi.useRealTimers();
  });

  it('starts a targeted background subscription update and waits for its state', async () => {
    mocks.executeShellCommand.mockImplementation(({ args }) => {
      if (args[0] === 'subscription_update_async') {
        return Promise.resolve({
          stdout: JSON.stringify({
            success: true,
            job_id: 'job-1',
            message: 'Subscription update started',
          }),
          stderr: '',
          code: 0,
        });
      }

      if (args[0] === 'subscription_update_status') {
        return Promise.resolve({
          stdout: JSON.stringify({
            success: true,
            running: false,
            message: 'Subscription update completed',
            exit_code: 0,
          }),
          stderr: '',
          code: 0,
        });
      }

      return Promise.resolve({
        stdout: '',
        stderr: 'Unexpected command',
        code: 1,
      });
    });

    await expect(
      PodkopShellMethods.subscriptionUpdateStart('main'),
    ).resolves.toEqual({
      success: true,
      data: {
        success: true,
        job_id: 'job-1',
        message: 'Subscription update started',
      },
    });

    const responsePromise =
      PodkopShellMethods.waitSubscriptionUpdateJob('job-1');

    await vi.advanceTimersByTimeAsync(1500);

    await expect(responsePromise).resolves.toEqual({
      success: true,
      data: {
        success: true,
        running: false,
        message: 'Subscription update completed',
        exit_code: 0,
      },
    });
    expect(mocks.executeShellCommand).toHaveBeenNthCalledWith(1, {
      command: '/usr/bin/podkop-plus',
      args: ['subscription_update_async', 'main'],
      timeout: 15000,
    });
    expect(mocks.executeShellCommand).toHaveBeenNthCalledWith(2, {
      command: '/usr/bin/podkop-plus',
      args: ['subscription_update_status', 'job-1'],
      timeout: 15000,
    });
  });

  it('returns the backend subscription start error message', async () => {
    mocks.executeShellCommand.mockResolvedValue({
      stdout: JSON.stringify({
        success: false,
        message: 'Subscription update is already running',
      }),
      stderr: '',
      code: 1,
    });

    await expect(
      PodkopShellMethods.subscriptionUpdateStart('main'),
    ).resolves.toEqual({
      success: false,
      error: 'Subscription update is already running',
    });
  });

  it('returns failed finished job state from the low-level waiter for UI restoration', async () => {
    mocks.executeShellCommand.mockImplementation(({ args }) => {
      if (args[0] === 'subscription_update_status') {
        return Promise.resolve({
          stdout: JSON.stringify({
            success: false,
            running: false,
            message: 'Failed to download subscriptions',
            section: 'main',
            source_index: '',
            exit_code: 1,
          }),
          stderr: '',
          code: 0,
        });
      }

      return Promise.resolve({
        stdout: '',
        stderr: 'Unexpected command',
        code: 1,
      });
    });

    const responsePromise =
      PodkopShellMethods.waitSubscriptionUpdateJob('job-1');

    await vi.advanceTimersByTimeAsync(1500);

    await expect(responsePromise).resolves.toEqual({
      success: true,
      data: {
        success: false,
        running: false,
        message: 'Failed to download subscriptions',
        section: 'main',
        source_index: '',
        exit_code: 1,
      },
    });
  });

  it('keeps waiting through a transient RPC reply loss', async () => {
    mocks.executeShellCommand.mockImplementation(({ args }) => {
      if (args[0] === 'subscription_update_status') {
        if (mocks.executeShellCommand.mock.calls.length === 1) {
          return Promise.resolve({
            stdout: '',
            stderr: 'No related RPC reply',
            code: 1,
          });
        }

        return Promise.resolve({
          stdout: JSON.stringify({
            success: true,
            running: false,
            message: 'Subscription update completed',
            section: 'main',
            source_index: '',
            exit_code: 0,
          }),
          stderr: '',
          code: 0,
        });
      }

      return Promise.resolve({
        stdout: '',
        stderr: 'Unexpected command',
        code: 1,
      });
    });

    const responsePromise =
      PodkopShellMethods.waitSubscriptionUpdateJob('job-1');

    await vi.advanceTimersByTimeAsync(3000);

    await expect(responsePromise).resolves.toEqual({
      success: true,
      data: {
        success: true,
        running: false,
        message: 'Subscription update completed',
        section: 'main',
        source_index: '',
        exit_code: 0,
      },
    });
  });
});
