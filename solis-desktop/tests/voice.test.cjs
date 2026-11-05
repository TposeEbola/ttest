'use strict';

const test = require('node:test');
const assert = require('node:assert/strict');
const { EventEmitter } = require('node:events');
const { PassThrough } = require('node:stream');
const { createVoiceService } = require('../src/main/voice.cjs');

const helper = '/app/build/native/SolisSpeech';
const macVoices = [
  { id: 'mx-female', name: 'Paulina', language: 'es-MX', gender: 'female' },
  { id: 'co-male', name: 'Carlos', language: 'es-CO', gender: 'male' },
  { id: 'co-female', name: 'Colombian voice', language: 'es-CO', gender: 'female' },
];

function harness({ platform = 'darwin', files = ['/usr/bin/say'], voices = macVoices, ...options } = {}) {
  const calls = [];
  const service = createVoiceService({
    platform,
    appPath: '/app',
    existsSync: (filename) => files.includes(filename),
    spawn: (command, args, spawnOptions) => {
      const child = new EventEmitter();
      child.stdout = new PassThrough();
      child.stderr = new PassThrough();
      child.stdin = new PassThrough();
      child.input = '';
      child.stdin.on('data', (data) => { child.input += data.toString(); });
      child.killed = false;
      child.signals = [];
      child.kill = (signal) => {
        child.killed = true;
        child.signals.push(signal);
        queueMicrotask(() => child.emit('close', null, signal));
        return true;
      };
      calls.push({ command, args, options: spawnOptions, child });
      if (args[0] === '--voices') queueMicrotask(() => {
        child.stdout.write(`${JSON.stringify({ voices })}\n`);
        child.emit('close', 0, null);
      });
      return child;
    },
    ...options,
  });
  return { service, calls };
}

function complete(call, stdout = '', exitCode = 0) {
  if (stdout) call.child.stdout.write(stdout);
  call.child.emit('close', exitCode, null);
}

test('status is permission-free and identifies a missing macOS helper', async () => {
  const { service, calls } = harness();
  const status = await service.getStatus();
  assert.equal(status.ttsAvailable, true);
  assert.equal(status.speechAvailable, false);
  assert.equal(status.helperPath, helper);
  assert.equal(status.voiceFallback, true);
  assert.equal(calls.length, 0);
  assert.ok(status.warnings.some((entry) => entry.includes('prepare:macos')));
});

test('macOS status uses actual installed voice metadata with the Colombian female default', async () => {
  const { service, calls } = harness({ files: [helper] });
  const status = await service.getStatus();
  assert.equal(status.ttsAvailable, true);
  assert.equal(status.speechAvailable, true);
  assert.equal(status.selectedVoice.id, 'co-female');
  assert.equal(status.voiceFallback, false);
  assert.deepEqual(calls[0].args, ['--voices']);
  assert.equal(calls[0].options.shell, false);
  await service.getStatus({ voiceId: 'mx-female' });
  assert.equal(calls.length, 1, 'installed metadata is cached without repeated subprocesses');
});

test('voice selection reports a real Spanish female fallback when the Colombian voice is absent', async () => {
  const { service } = harness({ files: [helper], voices: macVoices.slice(0, 2) });
  const status = await service.getStatus();
  assert.equal(status.selectedVoice.id, 'mx-female');
  assert.equal(status.voiceFallback, true);
  assert.ok(status.warnings.some((entry) => entry.includes('accent may differ')));
});

test('explicit packaged resources path takes precedence over the development helper', async () => {
  const packagedHelper = '/Applications/Project Solis.app/Contents/Resources/native/SolisSpeech';
  const { service } = harness({ resourcesPath: '/Applications/Project Solis.app/Contents/Resources', files: [helper, packagedHelper] });
  assert.equal((await service.getStatus()).helperPath, packagedHelper);
});

test('macOS say receives text only over stdin, including command-looking input', async () => {
  const { service, calls } = harness();
  const text = '-v Evil; $(touch /tmp/nope) `id`\nhello';
  const speaking = service.speak(text);
  assert.equal(calls[0].command, '/usr/bin/say');
  assert.deepEqual(calls[0].args, []);
  assert.equal(calls[0].options.shell, false);
  assert.equal(calls[0].child.input, text);
  complete(calls[0]);
  assert.deepEqual(await speaking, { spoken: true, engine: 'macOS system voice' });
});

test('native synthesis receives a fixed mode and JSON stdin; speaking never starts recognition', async () => {
  const { service, calls } = harness({ files: [helper] });
  const speaking = service.speak('Buenas noches; $(rm -rf /)', { locale: 'es-CO', gender: 'female', voiceId: 'actual-installed-id' });
  assert.equal(calls[0].command, helper);
  assert.deepEqual(calls[0].args, ['--speak']);
  assert.deepEqual(JSON.parse(calls[0].child.input), {
    text: 'Buenas noches; $(rm -rf /)', locale: 'es-CO', gender: 'female', voiceId: 'actual-installed-id',
  });
  complete(calls[0], '{"type":"spoken"}\n');
  await speaking;
});

test('Linux uses a trusted executable and explicitly reports its accent approximation', async () => {
  const { service, calls } = harness({ platform: 'linux', files: ['/usr/bin/espeak'] });
  const status = await service.getStatus();
  assert.equal(status.speechAvailable, false);
  assert.equal(status.selectedVoice.language, 'es');
  assert.equal(status.voiceFallback, true);
  const speaking = service.speak('hola');
  assert.equal(calls[0].command, '/usr/bin/espeak');
  assert.deepEqual(calls[0].args, ['-v', 'es+f3', '--stdin']);
  assert.equal(calls[0].child.input, 'hola');
  assert.equal(calls[0].options.shell, false);
  complete(calls[0]);
  await speaking;
});

test('Windows uses a fixed System.Speech script, with user data only in stdin JSON', async () => {
  const { service, calls } = harness({ platform: 'win32', existsSync: (filename) => filename.endsWith('\\powershell.exe') });
  const text = "'; Start-Process evil; #";
  const speaking = service.speak(text);
  assert.match(calls[0].command, /^[a-z]:\\Windows\\System32\\WindowsPowerShell\\v1\.0\\powershell\.exe$/i);
  assert.equal(calls[0].options.shell, false);
  assert.ok(calls[0].args.includes('-NonInteractive'));
  assert.ok(calls[0].args.at(-1).includes('System.Speech'));
  assert.ok(!calls[0].args.at(-1).includes(text));
  assert.equal(JSON.parse(calls[0].child.input).text, text);
  complete(calls[0]);
  await speaking;
});

test('invalid speech input cannot start a subprocess', async () => {
  const { service, calls } = harness();
  for (const text of [null, undefined, 42, '', '  ', 'a'.repeat(4001), 'bad\0text']) {
    await assert.rejects(service.speak(text), { code: 'VOICE_INVALID_TEXT' });
  }
  assert.equal(calls.length, 0);
});

test('unavailable TTS and unsupported transcription have clear errors', async () => {
  const { service, calls } = harness({ platform: 'linux', files: [] });
  assert.equal((await service.getStatus()).ttsAvailable, false);
  await assert.rejects(service.speak('hello'), { code: 'VOICE_UNAVAILABLE' });
  await assert.rejects(service.transcribeNative(), { code: 'VOICE_UNSUPPORTED' });
  assert.equal(calls.length, 0);
});

test('native recognition runs only the fixed helper listening mode and returns its final transcript', async () => {
  const { service, calls } = harness({ files: [helper] });
  const recognition = service.transcribeNative();
  assert.equal(calls[0].command, helper);
  assert.deepEqual(calls[0].args, ['--listen']);
  assert.equal(calls[0].options.stdio[0], 'ignore');
  assert.equal(calls[0].options.shell, false);
  complete(calls[0], '{"type":"partial","text":"hello"}\n{"type":"final","text":"  hello Solis  "}\n');
  assert.equal(await recognition, 'hello Solis');
});

test('native response decoding preserves Unicode across stream chunk boundaries', async () => {
  const { service, calls } = harness({ files: [helper] });
  const recognition = service.transcribeNative();
  const bytes = Buffer.from('{"type":"final","text":"café ☀️"}\n');
  for (const byte of bytes) calls[0].child.stdout.write(Buffer.from([byte]));
  complete(calls[0]);
  assert.equal(await recognition, 'café ☀️');
});

test('native helper missing is reported before spawn', async () => {
  const { service, calls } = harness();
  await assert.rejects(service.transcribeNative(), { code: 'VOICE_UNAVAILABLE' });
  assert.equal(calls.length, 0);
});

test('native permission errors, malformed responses, empty speech, and crashes reject clearly', async () => {
  for (const [output, code, expectedCode, expectedMessage] of [
    ['{"type":"error","message":"Microphone access denied."}\n', 1, 'VOICE_RECOGNITION_FAILED', /Microphone access denied/],
    ['not json\n', 0, 'VOICE_INVALID_RESPONSE', /invalid response/],
    ['{"type":"final","text":"  "}\n', 0, 'VOICE_NO_SPEECH', /No speech/],
    ['', 1, 'VOICE_RECOGNITION_FAILED', /stopped unexpectedly/],
  ]) {
    const { service, calls } = harness({ files: [helper] });
    const recognition = service.transcribeNative();
    complete(calls[0], output, code);
    await assert.rejects(recognition, (error) => error.code === expectedCode && expectedMessage.test(error.message));
  }
});

test('stopSpeaking cancels only its own speaking child while recognition continues', async () => {
  const { service, calls } = harness({ files: ['/usr/bin/say', helper] });
  const speaking = service.speak('hello');
  const speakingRejected = assert.rejects(speaking, { code: 'VOICE_CANCELLED' });
  const recognition = service.transcribeNative();
  assert.equal(service.stopSpeaking(), true);
  await speakingRejected;
  assert.deepEqual(calls[0].child.signals, ['SIGTERM']);
  assert.deepEqual(calls[1].child.signals, []);
  assert.equal(service.stopSpeaking(), false);
  complete(calls[1], '{"type":"final","text":"still listening"}\n');
  assert.equal(await recognition, 'still listening');
});

test('a replacement reply cancels its previous child without cancelling the new one', async () => {
  const { service, calls } = harness();
  const first = service.speak('first');
  const rejected = assert.rejects(first, { code: 'VOICE_CANCELLED' });
  const second = service.speak('second');
  await rejected;
  assert.equal(calls[0].child.killed, true);
  assert.equal(calls[1].child.killed, false);
  complete(calls[1]);
  await second;
});

test('stopNativeRecognition only terminates the owned listener', async () => {
  const { service, calls } = harness({ files: [helper] });
  assert.equal(service.stopNativeRecognition(), false);
  const recognition = service.transcribeNative();
  const rejected = assert.rejects(recognition, { code: 'VOICE_CANCELLED' });
  assert.equal(service.stopNativeRecognition(), true);
  await rejected;
  assert.deepEqual(calls[0].child.signals, ['SIGTERM']);
});

test('a stalled native process times out and is terminated', async () => {
  const { service, calls } = harness({ files: [helper], speechTimeoutMs: 5 });
  await assert.rejects(service.transcribeNative(), { code: 'VOICE_TIMEOUT' });
  assert.deepEqual(calls[0].child.signals, ['SIGTERM']);
});

test('unbounded helper output is rejected and the child is terminated', async () => {
  const { service, calls } = harness({ files: [helper] });
  const recognition = service.transcribeNative();
  const rejected = assert.rejects(recognition, { code: 'VOICE_OUTPUT_LIMIT' });
  calls[0].child.stdout.write('a'.repeat(65 * 1024));
  await rejected;
  assert.equal(calls[0].child.killed, true);
});

test('subprocess startup and nonzero TTS exit errors reject without lingering active operations', async () => {
  const first = harness();
  const failed = first.service.speak('hello');
  first.calls[0].child.emit('error', new Error('ENOENT'));
  await assert.rejects(failed, { code: 'VOICE_START_FAILED' });
  assert.equal(first.service.stopSpeaking(), false);
  const second = harness();
  const speaking = second.service.speak('hello');
  second.calls[0].child.stderr.write('No output device');
  complete(second.calls[0], '', 1);
  await assert.rejects(speaking, /No output device/);
});

test('native preparation preserves an unchanged helper and rebuilds changed inputs or binaries', () => {
  const fs = require('node:fs');
  const path = require('node:path');
  const vm = require('node:vm');
  const scriptPath = path.resolve(__dirname, '../scripts/prepare-macos-speech.cjs');
  const script = fs.readFileSync(scriptPath, 'utf8');
  const root = path.resolve(__dirname, '..');
  const source = path.join(root, 'native/macos/SolisSpeech.swift');
  const plist = path.join(root, 'native/macos/SpeechInfo.plist');
  const executable = path.join(root, 'build/native/SolisSpeech');
  const stamp = path.join(root, 'build/native/.speech-build.json');
  const files = new Map([[source, 'original Swift source'], [plist, 'original permission plist']]);
  let builds = 0;
  let probes = 0;
  const fakeFs = {
    existsSync: (filename) => files.has(filename),
    mkdirSync: () => {},
    readFileSync: (filename) => {
      if (!files.has(filename)) throw new Error('ENOENT');
      return files.get(filename);
    },
    writeFileSync: (filename, value) => files.set(filename, value),
  };
  const execFileSync = (command, args, options) => {
    assert.equal(options.shell, false);
    if (command === '/usr/bin/xcrun') {
      assert.deepEqual(Array.from(args), ['--find', 'swiftc']);
      probes += 1;
      return '/Xcode/usr/bin/swiftc\n';
    }
    assert.equal(command, '/Xcode/usr/bin/swiftc');
    assert.ok(args.includes('-sectcreate'), 'permission plist remains embedded');
    assert.ok(args.includes(plist));
    builds += 1;
    files.set(executable, `locally compiled binary ${builds}`);
    return '';
  };
  const run = (arch = 'arm64') => vm.runInNewContext(script, {
    __dirname: path.dirname(scriptPath),
    process: { platform: 'darwin', arch },
    console: { log: () => {}, error: (message) => { throw new Error(message); } },
    require: (name) => name === 'node:fs' ? fakeFs
      : name === 'node:child_process' ? { execFileSync } : require(name),
  }, { filename: scriptPath });

  run();
  assert.equal(builds, 1);
  const initialBinary = files.get(executable);
  run();
  assert.equal(builds, 1);
  assert.equal(probes, 1, 'cache reuse does not require another compiler lookup');
  assert.equal(files.get(executable), initialBinary, 'the helper identity remains unchanged');
  files.set(source, 'changed Swift source');
  run();
  assert.equal(builds, 2);
  files.set(plist, 'changed permission plist');
  run();
  assert.equal(builds, 3);
  run('x64');
  assert.equal(builds, 4);
  assert.equal(JSON.parse(files.get(stamp)).architecture, 'x86_64');
  files.set(executable, 'unexpected replacement binary');
  run('x64');
  assert.equal(builds, 5, 'a changed binary cannot reuse an old build stamp');
  files.delete(executable);
  run('x64');
  assert.equal(builds, 6, 'a stamp without its helper is rebuilt');
});
