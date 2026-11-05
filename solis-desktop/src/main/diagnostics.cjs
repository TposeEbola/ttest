'use strict';

const fs = require('node:fs');
const os = require('node:os');
const { execFile } = require('node:child_process');

// These are the complete set of disk-related processes available to the app.
// No command, path, argument, or script comes from IPC, chat, or a model reply.
const PROBES = Object.freeze({
  linuxDevices: Object.freeze({
    file: '/usr/bin/lsblk',
    args: Object.freeze(['--json', '--bytes', '--output', 'NAME,TYPE,SIZE,ROTA,FSTYPE,MOUNTPOINTS']),
  }),
  macRoot: Object.freeze({
    file: '/usr/sbin/diskutil',
    args: Object.freeze(['info', '-plist', '/']),
  }),
  windowsVolumes: Object.freeze({
    file: 'powershell.exe',
    args: Object.freeze([
      '-NoLogo', '-NoProfile', '-NonInteractive', '-Command',
      'Get-CimInstance -ClassName Win32_LogicalDisk -Filter "DriveType=3" | Select-Object DeviceID,VolumeName,FileSystem,Size,FreeSpace,DriveType | ConvertTo-Json -Compress',
    ]),
  }),
});

const DESTRUCTIVE_ACTIONS_DISABLED = true;
const MAX_OUTPUT_BYTES = 2 * 1024 * 1024;

function disabledError(code, message) {
  const error = new Error(message);
  error.code = code;
  return error;
}

function createProbeRunner(execute = execFile) {
  return async function runProbe(probeId) {
    if (typeof probeId !== 'string' || !Object.hasOwn(PROBES, probeId)) {
      throw disabledError('DISK_PROBE_DISABLED', 'This disk probe is not allowed.');
    }
    const probe = PROBES[probeId];
    return new Promise((resolve, reject) => {
      execute(probe.file, [...probe.args], {
        shell: false,
        windowsHide: true,
        timeout: 8_000,
        maxBuffer: MAX_OUTPUT_BYTES,
        encoding: 'utf8',
      }, (error, stdout) => {
        if (error) {
          // Do not expose stderr or a command's potentially sensitive output.
          reject(disabledError('DISK_PROBE_FAILED', 'The read-only disk probe could not complete.'));
          return;
        }
        if (typeof stdout !== 'string' || Buffer.byteLength(stdout, 'utf8') > MAX_OUTPUT_BYTES) {
          reject(disabledError('DISK_PROBE_FAILED', 'The disk probe returned an invalid response.'));
          return;
        }
        resolve(stdout);
      });
    });
  };
}

const defaultRunner = createProbeRunner();

function nonnegative(value) {
  if (value === undefined || value === null || value === '' || typeof value === 'boolean') return null;
  const number = Number(value);
  return Number.isFinite(number) && number >= 0 && number <= Number.MAX_SAFE_INTEGER ? number : null;
}

function text(value, fallback = '') {
  return typeof value === 'string' ? value.replace(/[\u0000-\u001f\u007f]/g, '').slice(0, 512) : fallback;
}

function capacity(total, free) {
  const totalBytes = nonnegative(total);
  const freeBytes = nonnegative(free);
  if (totalBytes === null || freeBytes === null || freeBytes > totalBytes) return null;
  const usedBytes = totalBytes - freeBytes;
  return {
    totalBytes,
    freeBytes,
    usedBytes,
    usedPercent: totalBytes > 0 ? Math.round((usedBytes / totalBytes) * 1000) / 10 : 0,
  };
}

function boolean(value) {
  if (value === true || value === 1 || value === '1') return true;
  if (value === false || value === 0 || value === '0') return false;
  return null;
}

function parseLinux(stdout, report) {
  const data = JSON.parse(stdout);
  if (!data || !Array.isArray(data.blockdevices)) throw new Error('Invalid device list');
  // Bound traversal even when a platform command returns unexpected data.
  const pending = data.blockdevices.map((device) => ({ device, depth: 0 }));
  let count = 0;
  while (pending.length && count < 512) {
    const { device, depth } = pending.shift();
    if (!device || typeof device !== 'object' || typeof device.name !== 'string') continue;
    count += 1;
    const mountPoints = (Array.isArray(device.mountpoints) ? device.mountpoints : [])
      .filter((mount) => typeof mount === 'string' && mount.length > 0)
      .slice(0, 32).map((mount) => text(mount));
    const item = {
      name: text(device.name),
      type: text(device.type, 'unknown'),
      sizeBytes: nonnegative(device.size),
      rotational: boolean(device.rota),
      filesystem: text(device.fstype),
      mountPoints,
    };
    report.devices.push(item);
    for (const mountPoint of mountPoints) {
      report.volumes.push({
        name: item.name, device: item.name, mountPoint,
        filesystem: item.filesystem, totalBytes: null, freeBytes: null,
        usedBytes: null, usedPercent: null,
      });
    }
    if (depth < 12 && Array.isArray(device.children)) {
      pending.push(...device.children.slice(0, 512).map((child) => ({ device: child, depth: depth + 1 })));
    }
  }
  if (pending.length) report.warnings.push('The device list was shortened.');
}

async function parseMac(stdout, report) {
  // diskutil -plist produces XML, never OpenStep or binary data. Reject other
  // output before the XML library can write parser diagnostics to stderr.
  if (!/<plist(?:\s|>)/.test(stdout) || !stdout.trimEnd().endsWith('</plist>') || /<!ENTITY\b/i.test(stdout)) {
    throw new Error('Invalid property list');
  }
  const { parse } = await import('plist');
  const data = parse(stdout);
  if (!data || typeof data !== 'object' || typeof data.DeviceIdentifier !== 'string') {
    throw new Error('Invalid disk information');
  }
  const name = text(data.DeviceIdentifier);
  const mountPoint = text(data.MountPoint, '/');
  const filesystem = text(data.FilesystemName || data.FilesystemType || data.Content);
  report.devices.push({
    name,
    type: data.Whole === true ? 'disk' : 'volume',
    sizeBytes: nonnegative(data.TotalSize ?? data.DiskSize ?? data.VolumeTotalSpace),
    solidState: boolean(data.SolidState),
    removable: boolean(data.RemovableMedia),
    filesystem,
    mountPoints: [mountPoint],
  });
  const space = capacity(data.VolumeTotalSpace ?? data.TotalSize, data.VolumeFreeSpace ?? data.FreeSpace);
  report.volumes.push({
    name: text(data.VolumeName, name), device: name, mountPoint, filesystem,
    ...(space || { totalBytes: null, freeBytes: null, usedBytes: null, usedPercent: null }),
  });
}

function parseWindows(stdout, report) {
  // PowerShell emits no text for zero fixed volumes, one object for a single
  // volume, and an array for multiple volumes.
  const parsed = stdout.trim() ? JSON.parse(stdout) : [];
  const items = Array.isArray(parsed) ? parsed : parsed ? [parsed] : [];
  if (items.length > 512) throw new Error('Invalid volume list');
  for (const item of items) {
    if (!item || typeof item !== 'object' || typeof item.DeviceID !== 'string') {
      throw new Error('Invalid volume information');
    }
    const name = text(item.DeviceID);
    const filesystem = text(item.FileSystem);
    const space = capacity(item.Size, item.FreeSpace);
    report.volumes.push({
      name: text(item.VolumeName, name) || name, device: name, mountPoint: `${name}\\`, filesystem,
      ...(space || { totalBytes: null, freeBytes: null, usedBytes: null, usedPercent: null }),
    });
    report.devices.push({
      name, type: 'logical-volume', sizeBytes: nonnegative(item.Size), filesystem,
      mountPoints: [`${name}\\`],
    });
  }
}

function measuredVolumeIndex(volumes, path, platform) {
  const normalize = (value) => {
    const normalized = value.replace(/\\/g, '/').replace(/\/+$/, '') || '/';
    return platform === 'win32' ? normalized.toLowerCase() : normalized;
  };
  const sampled = normalize(path);
  let bestIndex = -1;
  let longest = -1;
  volumes.forEach((volume, index) => {
    const mount = normalize(volume.mountPoint);
    if ((mount === '/' ? sampled.startsWith('/') : sampled === mount || sampled.startsWith(`${mount}/`))
      && mount.length > longest) {
      bestIndex = index;
      longest = mount.length;
    }
  });
  return bestIndex;
}

async function getDiskDiagnostics({
  platform = process.platform,
  run = defaultRunner,
  statfs = fs.promises.statfs,
  home = os.homedir(),
  now = () => new Date(),
} = {}) {
  const report = {
    generatedAt: now().toISOString(), platform, readOnly: true,
    summary: { totalBytes: null, freeBytes: null, usedBytes: null, usedPercent: null },
    volumes: [], devices: [], warnings: [], health: 'not-assessed',
  };
  const capacityPath = platform === 'darwin' ? '/' : home;
  try {
    // One filesystem metadata lookup; never enumerate files or access devices.
    const stats = await statfs(capacityPath);
    const blockSize = nonnegative(stats.bsize);
    const blocks = nonnegative(stats.blocks);
    const availableBlocks = nonnegative(stats.bavail);
    const space = blockSize !== null && blocks !== null && availableBlocks !== null
      ? capacity(blockSize * blocks, blockSize * availableBlocks) : null;
    if (!space) throw new Error('Invalid filesystem capacity');
    report.summary = space;
    report.volumes.push({
      name: 'Current filesystem', device: null, mountPoint: capacityPath, filesystem: '', ...space,
    });
  } catch {
    report.warnings.push('Filesystem capacity is unavailable.');
  }

  const probeId = { linux: 'linuxDevices', darwin: 'macRoot', win32: 'windowsVolumes' }[platform];
  if (!probeId) {
    report.warnings.push('Device details are not available on this operating system.');
    return report;
  }
  try {
    const stdout = await run(probeId);
    if (typeof stdout !== 'string' || Buffer.byteLength(stdout, 'utf8') > MAX_OUTPUT_BYTES) {
      throw new Error('Invalid probe output');
    }
    // Keep parsing atomic so malformed output never leaves a partial inventory.
    const inventory = { devices: [], volumes: [], warnings: [] };
    if (platform === 'linux') parseLinux(stdout, inventory);
    else if (platform === 'darwin') await parseMac(stdout, inventory);
    else parseWindows(stdout, inventory);
    if (report.summary.totalBytes !== null) {
      const measuredIndex = measuredVolumeIndex(inventory.volumes, capacityPath, platform);
      if (measuredIndex >= 0) {
        // The mounted filesystem's available space comes from statfs. Device
        // sizes and APFS container space are not independent volume capacities.
        Object.assign(inventory.volumes[measuredIndex], report.summary);
        report.volumes.length = 0;
      }
    }
    report.devices.push(...inventory.devices);
    report.volumes.push(...inventory.volumes);
    report.warnings.push(...inventory.warnings);
  } catch {
    report.warnings.push('Device details are unavailable; the read-only probe failed or returned unsupported data.');
  }
  return report;
}

async function runDiskAction(action, options) {
  if (action !== 'summary' && action !== 'devices') {
    throw disabledError('DISK_ACTION_DISABLED', 'Destructive disk actions are disabled. Only read-only summary and device information are available.');
  }
  return getDiskDiagnostics(options);
}

module.exports = {
  DESTRUCTIVE_ACTIONS_DISABLED,
  createProbeRunner,
  getDiskDiagnostics,
  runDiskAction,
};
