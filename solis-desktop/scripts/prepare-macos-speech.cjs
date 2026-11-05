#!/usr/bin/env node
'use strict';

const { execFileSync } = require('node:child_process');
const { createHash } = require('node:crypto');
const { existsSync, mkdirSync, readFileSync, writeFileSync } = require('node:fs');
const path = require('node:path');

if (process.platform !== 'darwin') {
  console.log('Skipping the Apple Speech helper: build it on macOS 13 or later with Xcode Command Line Tools. Text chat remains available here.');
  process.exit(0);
}

const root = path.resolve(__dirname, '..');
const outputDirectory = path.join(root, 'build', 'native');
const source = path.join(root, 'native', 'macos', 'SolisSpeech.swift');
const infoPlist = path.join(root, 'native', 'macos', 'SpeechInfo.plist');
const executable = path.join(outputDirectory, 'SolisSpeech');
const stampPath = path.join(outputDirectory, '.speech-build.json');
const architecture = process.arch === 'arm64' ? 'arm64' : 'x86_64';

function sha256(value) {
  return createHash('sha256').update(value).digest('hex');
}

function prepare() {
  const inputs = {
    version: 1,
    architecture,
    target: `${architecture}-apple-macosx13.0`,
    sourceHash: sha256(readFileSync(source)),
    plistHash: sha256(readFileSync(infoPlist)),
  };
  const inputHash = sha256(JSON.stringify(inputs));
  let stamp;
  try { stamp = JSON.parse(readFileSync(stampPath, 'utf8')); }
  catch { /* A missing or outdated stamp requires a fresh local build. */ }
  if (stamp?.inputHash === inputHash && existsSync(executable)
      && stamp.binaryHash === sha256(readFileSync(executable))) {
    console.log(`Using unchanged macOS speech helper: ${executable}`);
    return;
  }

  const swiftc = execFileSync('/usr/bin/xcrun', ['--find', 'swiftc'], {
    encoding: 'utf8', shell: false, stdio: ['ignore', 'pipe', 'pipe'],
  }).trim();
  if (!path.isAbsolute(swiftc) || !swiftc.endsWith('/swiftc')) {
    throw new Error('Xcode did not return a valid Swift compiler path.');
  }
  mkdirSync(outputDirectory, { recursive: true });
  execFileSync(swiftc, [
    source,
    '-O',
    '-target', inputs.target,
    '-framework', 'AVFoundation',
    '-framework', 'Speech',
    '-Xlinker', '-sectcreate',
    '-Xlinker', '__TEXT',
    '-Xlinker', '__info_plist',
    '-Xlinker', infoPlist,
    '-o', executable,
  ], { shell: false, stdio: 'inherit' });
  writeFileSync(stampPath, `${JSON.stringify({ ...inputs, inputHash, binaryHash: sha256(readFileSync(executable)) }, null, 2)}\n`);
  console.log(`Built macOS speech helper: ${executable}`);
}

try {
  prepare();
} catch (error) {
  console.error(`Unable to build the macOS speech helper: ${error.message}`);
  console.error('Install Xcode Command Line Tools with xcode-select --install, then run npm run prepare:macos again.');
  process.exitCode = 1;
}
