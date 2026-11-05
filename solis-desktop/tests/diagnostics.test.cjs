'use strict';

const { test } = require('node:test');
const assert = require('node:assert/strict');
const {
  DESTRUCTIVE_ACTIONS_DISABLED, createProbeRunner, getDiskDiagnostics, runDiskAction,
} = require('../src/main/diagnostics.cjs');

const now = () => new Date('2026-11-05T12:00:00Z');
const statfs = async () => ({ bsize: 1024n, blocks: 1000n, bavail: 250n });
const base = { now, statfs, home: '/home/tester' };

test('the production runner resolves only fixed read-only probes with bounded execution', async () => {
  const calls = [];
  const run = createProbeRunner((file, args, options, callback) => {
    calls.push({ file, args, options });
    callback(null, '{}');
  });
  await run('linuxDevices');
  await run('macRoot');
  await run('windowsVolumes');
  assert.equal(calls[0].file, '/usr/bin/lsblk');
  assert.deepEqual(calls[0].args, ['--json', '--bytes', '--output', 'NAME,TYPE,SIZE,ROTA,FSTYPE,MOUNTPOINTS']);
  assert.equal(calls[1].file, '/usr/sbin/diskutil');
  assert.deepEqual(calls[1].args, ['info', '-plist', '/']);
  assert.equal(calls[2].file, 'powershell.exe');
  assert.deepEqual(calls[2].args.slice(0, 4), ['-NoLogo', '-NoProfile', '-NonInteractive', '-Command']);
  assert.equal(calls[2].args[4], 'Get-CimInstance -ClassName Win32_LogicalDisk -Filter "DriveType=3" | Select-Object DeviceID,VolumeName,FileSystem,Size,FreeSpace,DriveType | ConvertTo-Json -Compress');
  for (const { options } of calls) {
    assert.equal(options.shell, false);
    assert.equal(options.windowsHide, true);
    assert.equal(options.timeout, 8000);
    assert.equal(options.maxBuffer, 2 * 1024 * 1024);
  }
  for (const id of ['format', 'diskutil eraseDisk', 'linuxDevices; rm -rf /', '__proto__', {}, null]) {
    await assert.rejects(run(id), { code: 'DISK_PROBE_DISABLED' });
  }
  assert.equal(calls.length, 3);
});

test('destructive, unknown, and injected disk actions are rejected before all disk access', async () => {
  assert.equal(DESTRUCTIVE_ACTIONS_DISABLED, true);
  let accessed = 0;
  const options = {
    run: async () => { accessed += 1; },
    statfs: async () => { accessed += 1; },
  };
  for (const action of [
    'erase', 'format', 'repair', 'partition', 'mount', 'unmount', 'eject', 'delete',
    'wipe', 'clean', 'trim', 'fsck', 'chkdsk', 'diskpart', 'sudo',
    'eraseDisk', 'eraseVolume', 'partitionDisk', 'resizeVolume', 'zeroDisk',
    'secureErase', 'repairDisk', 'repairVolume', 'dd', 'mkfs',
    'summary; rm -rf /', 'devices && format C:', '../summary', 'SUMMARY', '',
    ['summary'], { action: 'summary' }, null, undefined,
  ]) {
    await assert.rejects(runDiskAction(action, options), { code: 'DISK_ACTION_DISABLED' });
  }
  assert.equal(accessed, 0);
});

test('Linux reports capacity and nested devices without exposing serial numbers or claiming health', async () => {
  const paths = [];
  const probes = [];
  const report = await runDiskAction('summary', {
    ...base, platform: 'linux',
    statfs: async (path) => { paths.push(path); return statfs(); },
    run: async (probe) => {
      probes.push(probe);
      return JSON.stringify({ blockdevices: [{
        name: 'nvme0n1', type: 'disk', size: 2048000, rota: false, serial: 'PRIVATE-SERIAL',
        children: [{ name: 'nvme0n1p1', type: 'part', size: '1024000', fstype: 'ext4', mountpoints: ['/', '/external', null] }],
      }] });
    },
  });
  assert.deepEqual(paths, ['/home/tester']);
  assert.deepEqual(probes, ['linuxDevices']);
  assert.equal(report.generatedAt, '2026-11-05T12:00:00.000Z');
  assert.equal(report.readOnly, true);
  assert.equal(report.health, 'not-assessed');
  assert.deepEqual(report.summary, { totalBytes: 1024000, freeBytes: 256000, usedBytes: 768000, usedPercent: 75 });
  assert.equal(report.devices.length, 2);
  assert.equal(report.devices[0].rotational, false);
  assert.deepEqual(report.devices[1].mountPoints, ['/', '/external']);
  assert.equal(report.volumes[0].totalBytes, report.summary.totalBytes);
  assert.equal(report.volumes[1].totalBytes, null, 'partition byte size is not filesystem capacity');
  assert.equal(JSON.stringify(report).includes('PRIVATE-SERIAL'), false);
  assert.deepEqual(report.warnings, []);
});

test('macOS prioritizes the mounted root filesystem with a fixed diskutil plist probe', async () => {
  const probes = [];
  const paths = [];
  const plist = `<?xml version="1.0" encoding="UTF-8"?>
  <!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
  <plist version="1.0"><dict>
    <key>DeviceIdentifier</key><string>disk3s1s1</string>
    <key>VolumeName</key><string>Macintosh HD</string>
    <key>MountPoint</key><string>/</string>
    <key>FilesystemName</key><string>APFS</string>
    <key>TotalSize</key><integer>2000000</integer>
    <key>VolumeTotalSpace</key><integer>2000000</integer>
    <key>VolumeFreeSpace</key><integer>500000</integer>
    <key>SolidState</key><true/>
    <key>RemovableMedia</key><false/>
    <key>SerialNumber</key><string>DO-NOT-EXPOSE</string>
  </dict></plist>`;
  const report = await getDiskDiagnostics({
    ...base, platform: 'darwin',
    statfs: async (path) => { paths.push(path); return statfs(); },
    run: async (probe) => { probes.push(probe); return plist; },
  });
  assert.deepEqual(probes, ['macRoot']);
  assert.deepEqual(paths, ['/']);
  assert.equal(report.devices[0].name, 'disk3s1s1');
  assert.equal(report.devices[0].solidState, true);
  assert.equal(report.volumes.length, 1, 'the root filesystem is not duplicated');
  assert.equal(report.volumes[0].name, 'Macintosh HD');
  assert.equal(report.volumes[0].usedPercent, 75);
  assert.equal(report.summary.totalBytes, 1024000, 'statfs remains the current capacity source');
  assert.equal(report.health, 'not-assessed');
  assert.equal(JSON.stringify(report).includes('DO-NOT-EXPOSE'), false);
  assert.deepEqual(report.warnings, []);
});

test('Windows parses both single-volume and multiple-volume PowerShell JSON', async () => {
  const volume = { DeviceID: 'C:', VolumeName: 'System', FileSystem: 'NTFS', Size: '1000', FreeSpace: '400', DriveType: 3 };
  for (const output of [volume, [volume, { ...volume, DeviceID: 'D:', VolumeName: 'Data' }]]) {
    const report = await runDiskAction('devices', {
      ...base, platform: 'win32', home: 'C:\\Users\\tester',
      run: async (probe) => { assert.equal(probe, 'windowsVolumes'); return JSON.stringify(output); },
    });
    assert.equal(report.volumes[0].mountPoint, 'C:\\');
    assert.equal(report.volumes[0].usedPercent, 75, 'the current filesystem uses statfs capacity');
    if (Array.isArray(output)) assert.equal(report.volumes[1].usedPercent, 60);
    assert.equal(report.devices[0].type, 'logical-volume');
    assert.equal(report.health, 'not-assessed');
    assert.deepEqual(report.warnings, []);
  }
});

test('failed probes and malformed output return warnings without executing a fallback command', async () => {
  for (const platform of ['linux', 'darwin', 'win32']) {
    for (const output of ['not valid output', '{}', 'x'.repeat(2 * 1024 * 1024 + 1)]) {
      let calls = 0;
      const report = await getDiskDiagnostics({
        ...base, platform,
        run: async () => { calls += 1; return output; },
      });
      assert.equal(calls, 1);
      assert.equal(report.devices.length, 0);
      assert.equal(report.volumes.length, 1);
      assert.equal(report.warnings.length, 1);
      assert.equal(report.health, 'not-assessed');
    }
  }
  const report = await getDiskDiagnostics({ ...base, platform: 'linux', run: async () => { throw new Error('PRIVATE STDERR'); } });
  assert.equal(JSON.stringify(report).includes('PRIVATE STDERR'), false);
  assert.equal(report.warnings.length, 1);
});

test('capacity failures are bounded, invalid counters are rejected, and no free-space result implies physical health', async () => {
  for (const stats of [
    { bsize: 1024, blocks: 100, bavail: 101 },
    { bsize: -1, blocks: 100, bavail: 10 },
    { bsize: 1024, blocks: NaN, bavail: 10 },
    { bsize: 1024n, blocks: 2n ** 63n, bavail: 10n },
  ]) {
    let calls = 0;
    const report = await getDiskDiagnostics({
      ...base, platform: 'linux',
      statfs: async () => { calls += 1; return stats; },
      run: async () => '{"blockdevices":[]}',
    });
    assert.equal(calls, 1);
    assert.equal(report.summary.totalBytes, null);
    assert.equal(report.health, 'not-assessed');
    assert.equal(report.warnings.length, 1);
  }
  let scans = 0;
  const unsupported = await getDiskDiagnostics({
    ...base, platform: 'freebsd', run: async () => { scans += 1; },
    statfs: async () => { throw new Error('unavailable'); },
  });
  assert.equal(scans, 0);
  assert.equal(unsupported.warnings.length, 2);
});

test('the runner rejects failed and oversized process responses without returning their contents', async () => {
  const failed = createProbeRunner((_file, _args, _options, done) => done(new Error('PRIVATE'), 'PRIVATE'));
  await assert.rejects(failed('macRoot'), (error) => error.code === 'DISK_PROBE_FAILED' && !error.message.includes('PRIVATE'));
  const oversized = createProbeRunner((_file, _args, _options, done) => done(null, 'x'.repeat(2 * 1024 * 1024 + 1)));
  await assert.rejects(oversized('linuxDevices'), { code: 'DISK_PROBE_FAILED' });
});
