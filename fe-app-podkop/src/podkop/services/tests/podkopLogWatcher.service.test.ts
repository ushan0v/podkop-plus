import { beforeEach, describe, expect, it } from 'vitest';

import { PodkopLogWatcher } from '../podkopLogWatcher.service';

describe('PodkopLogWatcher', () => {
  const watcher = PodkopLogWatcher.getInstance();
  let rawLogs = '';
  let seenLines: string[] = [];

  beforeEach(() => {
    watcher.stop();
    watcher.reset();
    rawLogs = '';
    seenLines = [];
  });

  it('uses the first read as a baseline when initial logs are suppressed', async () => {
    watcher.init(() => rawLogs, {
      suppressInitialLogs: true,
      onNewLog: (line) => seenLines.push(line),
    });

    rawLogs = 'old info\nold error';
    await watcher.checkOnce();

    expect(seenLines).toEqual([]);

    rawLogs = 'old info\nold error\nnew error';
    await watcher.checkOnce();
    await watcher.checkOnce();

    expect(seenLines).toEqual(['new error']);
  });

  it('does not replay old lines when the tracked log window slides', async () => {
    watcher.init(() => rawLogs, {
      suppressInitialLogs: true,
      maxTrackedLines: 3,
      onNewLog: (line) => seenLines.push(line),
    });

    rawLogs = 'line 1\nline 2\nline 3';
    await watcher.checkOnce();

    rawLogs = 'line 1\nline 2\nline 3\nline 4';
    await watcher.checkOnce();

    rawLogs = 'line 1\nline 2\nline 3\nline 4\nline 5';
    await watcher.checkOnce();
    await watcher.checkOnce();

    expect(seenLines).toEqual(['line 4', 'line 5']);
  });

  it('can still emit the initial snapshot when requested', async () => {
    watcher.init(() => rawLogs, {
      onNewLog: (line) => seenLines.push(line),
    });

    rawLogs = 'line 1\nline 2';
    await watcher.checkOnce();

    expect(seenLines).toEqual(['line 1', 'line 2']);
  });
});
