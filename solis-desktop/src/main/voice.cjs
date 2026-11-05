'use strict';

const { spawn: nodeSpawn } = require('node:child_process');
const { existsSync: fileExists } = require('node:fs');
const path = require('node:path');

const MAX_TEXT_LENGTH = 4000;
const MAX_OUTPUT_BYTES = 64 * 1024;
const WINDOWS_SPEECH_SCRIPT = [
  "$ErrorActionPreference = 'Stop'",
  '[Console]::InputEncoding = New-Object System.Text.UTF8Encoding',
  'Add-Type -AssemblyName System.Speech',
  '$voice = New-Object System.Speech.Synthesis.SpeechSynthesizer',
  '$request = [Console]::In.ReadToEnd() | ConvertFrom-Json',
  '$voices = @($voice.GetInstalledVoices() | ForEach-Object { $_.VoiceInfo })',
  '$selected = $voices | Where-Object { $_.Culture.Name -eq $request.locale -and $_.Gender.ToString().ToLowerInvariant() -eq $request.gender } | Select-Object -First 1',
  'if (!$selected) { $selected = $voices | Where-Object { $_.Culture.TwoLetterISOLanguageName -eq $request.locale.Split("-")[0] -and $_.Gender.ToString().ToLowerInvariant() -eq $request.gender } | Select-Object -First 1 }',
  'if ($selected) { $voice.SelectVoice($selected.Name) }',
  'try { $voice.Speak($request.text) } finally { $voice.Dispose() }',
].join('; ');

function preferences(value = {}) {
  const source = value && typeof value === 'object' ? value : {};
  return {
    locale: typeof source.locale === 'string' && /^[a-z]{2,3}(?:-[a-z0-9]{2,8})*$/i.test(source.locale) ? source.locale : 'es-CO',
    gender: ['female', 'male', 'unspecified'].includes(source.gender) ? source.gender : 'female',
    voiceId: typeof source.voiceId === 'string' && source.voiceId.length <= 256 ? source.voiceId : '',
  };
}

function selectVoice(voices, desired) {
  const locale = desired.locale.toLowerCase();
  const base = locale.split('-')[0];
  const exact = (voice) => voice.language.toLowerCase() === locale;
  const sameLanguage = (voice) => voice.language.toLowerCase().split('-')[0] === base;
  const sameGender = (voice) => voice.gender === desired.gender;
  return voices.find((voice) => desired.voiceId && voice.id === desired.voiceId)
    ?? voices.find((voice) => exact(voice) && sameGender(voice))
    ?? voices.find((voice) => sameLanguage(voice) && sameGender(voice))
    ?? voices.find(exact)
    ?? voices.find(sameLanguage)
    ?? voices.find(sameGender)
    ?? voices[0]
    ?? null;
}

function voiceError(message, code = 'VOICE_ERROR') {
  return Object.assign(new Error(message), { code });
}

function createVoiceService(options = {}) {
  const platform = options.platform ?? process.platform;
  const spawn = options.spawn ?? nodeSpawn;
  const existsSync = options.existsSync ?? fileExists;
  const appPath = options.appPath ?? path.resolve(__dirname, '../..');
  const resourcesPath = options.resourcesPath;
  const speechTimeoutMs = options.speechTimeoutMs ?? 40_000;
  const speakingTimeoutMs = options.speakingTimeoutMs ?? 180_000;
  const active = { speaking: null, recognition: null, voices: null };
  let voiceListPromise;

  function helperPath() {
    // Packaged apps must use their own bundled helper, never a working-directory executable.
    return resourcesPath
      ? path.join(resourcesPath, 'native', 'SolisSpeech')
      : path.join(appPath, 'build', 'native', 'SolisSpeech');
  }

  function ttsBackend() {
    if (platform === 'darwin') {
      return existsSync('/usr/bin/say')
        ? { executable: '/usr/bin/say', args: [], name: 'macOS system voice' }
        : null;
    }
    if (platform === 'linux') {
      for (const executable of ['/usr/bin/espeak-ng', '/usr/bin/espeak']) {
        if (existsSync(executable)) {
          return { executable, args: ['--stdin'], name: path.basename(executable) };
        }
      }
    }
    if (platform === 'win32') {
      // Accept the normal Windows installation drive only; never search PATH for a voice command.
      const windowsRoot = /^[a-z]:\\Windows$/i.test(process.env.SystemRoot ?? '')
        ? process.env.SystemRoot
        : 'C:\\Windows';
      const executable = path.win32.join(windowsRoot, 'System32', 'WindowsPowerShell', 'v1.0', 'powershell.exe');
      if (existsSync(executable)) {
        return {
          executable,
          args: ['-NoLogo', '-NoProfile', '-NonInteractive', '-Command', WINDOWS_SPEECH_SCRIPT],
          name: 'Windows system voice',
        };
      }
    }
    return null;
  }

  async function installedMacVoices() {
    if (!voiceListPromise) {
      voiceListPromise = runProcess('voices', helperPath(), ['--voices'], undefined, 8000, ({ code, stdout }) => {
        if (code !== 0) throw voiceError('Unable to read installed macOS voices.', 'VOICE_UNAVAILABLE');
        let response;
        try { response = JSON.parse(stdout.trim()); }
        catch { throw voiceError('Unable to read installed macOS voice metadata.', 'VOICE_INVALID_RESPONSE'); }
        return Array.isArray(response.voices) ? response.voices.filter((voice) => voice
          && typeof voice.id === 'string' && typeof voice.name === 'string'
          && typeof voice.language === 'string' && typeof voice.gender === 'string') : [];
      });
    }
    try { return await voiceListPromise; }
    catch (error) { voiceListPromise = undefined; throw error; }
  }

  async function getStatus(requested) {
    const desired = preferences(requested);
    const tts = ttsBackend();
    const nativePath = platform === 'darwin' ? helperPath() : null;
    const speechAvailable = platform === 'darwin' && existsSync(nativePath);
    const warnings = [];
    let availableVoices = [];
    if (speechAvailable) {
      try { availableVoices = await installedMacVoices(); }
      catch (error) { warnings.push(error.message); }
    } else if (platform === 'linux' && tts) {
      availableVoices = [
        { id: 'es+f3', name: 'eSpeak Spanish feminine variant', language: 'es', gender: 'female' },
        { id: 'en+f3', name: 'eSpeak English feminine variant', language: 'en', gender: 'female' },
      ];
    }
    const selectedVoice = selectVoice(availableVoices, desired);
    const voiceFallback = !selectedVoice
      || selectedVoice.language.toLowerCase() !== desired.locale.toLowerCase()
      || selectedVoice.gender !== desired.gender
      || Boolean(desired.voiceId && selectedVoice.id !== desired.voiceId);
    if (voiceFallback) warnings.push(selectedVoice
      ? `The requested ${desired.locale} ${desired.gender} voice is unavailable. Using ${selectedVoice.name} (${selectedVoice.language}); its accent may differ.`
      : `The requested ${desired.locale} ${desired.gender} voice could not be verified. Install a suitable system voice to match that preference.`);
    if (!tts && !availableVoices.length) warnings.push(platform === 'linux'
      ? 'Voice replies need espeak-ng or espeak installed at /usr/bin.'
      : 'A supported system voice was not found. Text replies remain available.');
    if (platform !== 'darwin') {
      warnings.push('Native microphone transcription is currently available on macOS. You can still type messages.');
    } else if (!speechAvailable) {
      warnings.push('Build the macOS speech helper with npm run prepare:macos before using the microphone.');
    } else {
      warnings.push('Microphone and Speech Recognition permissions are requested when you start listening. Apple may process speech online when on-device recognition is unavailable.');
    }
    return {
      platform,
      ttsAvailable: Boolean(tts || availableVoices.length),
      ttsEngine: availableVoices.length && platform === 'darwin' ? 'Apple AVSpeechSynthesizer' : tts?.name ?? null,
      speechAvailable,
      speechEngine: speechAvailable ? 'Apple Speech' : null,
      helperPath: nativePath,
      availableVoices,
      selectedVoice,
      voiceFallback,
      requestedVoice: desired,
      warnings,
    };
  }

  function stop(kind) {
    if (!active[kind]) return false;
    active[kind].cancel();
    return true;
  }

  function runProcess(kind, executable, args, input, timeoutMs, complete) {
    stop(kind);
    return new Promise((resolve, reject) => {
      let settled = false;
      let stdout = '';
      let stderr = '';
      let outputBytes = 0;
      let timeout;
      const record = { child: null, cancel: null };

      const finish = (error, value, terminate = false) => {
        if (settled) return;
        settled = true;
        clearTimeout(timeout);
        if (active[kind] === record) active[kind] = null;
        if (terminate && record.child && !record.child.killed) {
          try { record.child.kill('SIGTERM'); } catch { /* The child may already have exited. */ }
        }
        if (error) reject(error);
        else resolve(value);
      };

      record.cancel = () => finish(voiceError('Voice operation cancelled.', 'VOICE_CANCELLED'), undefined, true);
      active[kind] = record;
      timeout = setTimeout(() => finish(voiceError(
        kind === 'recognition' ? 'Listening timed out. Try again and speak after starting the microphone.' : 'Voice reply timed out.',
        'VOICE_TIMEOUT',
      ), undefined, true), timeoutMs);

      try {
        const child = spawn(executable, args, {
          shell: false,
          windowsHide: true,
          stdio: [input === undefined ? 'ignore' : 'pipe', 'pipe', 'pipe'],
        });
        record.child = child;
        child.stdout?.setEncoding?.('utf8');
        child.stderr?.setEncoding?.('utf8');
        child.once('error', (error) => finish(voiceError(`Unable to start voice service: ${error.message}`, 'VOICE_START_FAILED')));
        child.stdout?.on('data', (chunk) => {
          if (settled) return;
          outputBytes += Buffer.byteLength(chunk);
          if (outputBytes > MAX_OUTPUT_BYTES) {
            finish(voiceError('Voice service returned too much output.', 'VOICE_OUTPUT_LIMIT'), undefined, true);
            return;
          }
          stdout += chunk.toString('utf8');
        });
        child.stderr?.on('data', (chunk) => {
          if (!settled && stderr.length < 8192) stderr += chunk.toString('utf8').slice(0, 8192 - stderr.length);
        });
        child.once('close', (code, signal) => {
          if (settled) return;
          try { finish(null, complete({ code, signal, stdout, stderr })); }
          catch (error) { finish(error); }
        });
        if (input !== undefined) {
          child.stdin?.on('error', (error) => {
            // A premature exit may close stdin; the exit handler provides the useful error.
            if (error.code !== 'EPIPE') finish(voiceError(`Unable to send voice text: ${error.message}`), undefined, true);
          });
          child.stdin.end(input, 'utf8');
        }
      } catch (error) {
        finish(voiceError(`Unable to start voice service: ${error.message}`, 'VOICE_START_FAILED'), undefined, true);
      }
    });
  }

  async function speak(text, requested) {
    if (typeof text !== 'string' || !text.trim()) throw voiceError('Enter some text for the voice reply.', 'VOICE_INVALID_TEXT');
    if (text.length > MAX_TEXT_LENGTH) throw voiceError(`Voice replies are limited to ${MAX_TEXT_LENGTH} characters.`, 'VOICE_INVALID_TEXT');
    if (text.includes('\0')) throw voiceError('Voice replies cannot contain null characters.', 'VOICE_INVALID_TEXT');
    const desired = preferences(requested);
    let backend = ttsBackend();
    let input = text;
    if (platform === 'darwin' && existsSync(helperPath())) {
      backend = { executable: helperPath(), args: ['--speak'], name: 'Apple AVSpeechSynthesizer' };
      input = JSON.stringify({ text, ...desired });
    } else if (platform === 'linux' && backend) {
      const voices = [
        { id: 'es+f3', language: 'es', gender: 'female' },
        { id: 'en+f3', language: 'en', gender: 'female' },
      ];
      const selected = selectVoice(voices, desired);
      backend = { ...backend, args: ['-v', selected.id, '--stdin'] };
    } else if (platform === 'win32' && backend) {
      input = JSON.stringify({ text, ...desired });
    }
    if (!backend) throw voiceError('No supported system voice is available. Text replies remain available.', 'VOICE_UNAVAILABLE');
    return runProcess('speaking', backend.executable, backend.args, input, speakingTimeoutMs, ({ code, stderr, stdout }) => {
      if (code !== 0 && backend.name === 'Apple AVSpeechSynthesizer') {
        try {
          const response = JSON.parse(stdout.trim());
          if (response.type === 'error' && typeof response.message === 'string') throw voiceError(response.message, 'VOICE_FAILED');
        } catch (error) { if (error.code === 'VOICE_FAILED') throw error; }
      }
      if (code !== 0) throw voiceError(`Voice reply failed${stderr.trim() ? `: ${stderr.trim().slice(0, 400)}` : '.'}`, 'VOICE_FAILED');
      return { spoken: true, engine: backend.name };
    });
  }

  async function transcribeNative() {
    if (platform !== 'darwin') {
      throw voiceError('Native microphone transcription currently requires macOS. Please type your message on this operating system.', 'VOICE_UNSUPPORTED');
    }
    const executable = helperPath();
    if (!existsSync(executable)) throw voiceError('The macOS speech helper is missing. Run npm run prepare:macos, then restart Project Solis.', 'VOICE_UNAVAILABLE');
    return runProcess('recognition', executable, ['--listen'], undefined, speechTimeoutMs, ({ code, stdout, stderr }) => {
      let finalText = null;
      let helperError = null;
      for (const line of stdout.split(/\r?\n/).filter((entry) => entry.trim())) {
        let message;
        try { message = JSON.parse(line); }
        catch { throw voiceError('The speech helper returned an invalid response.', 'VOICE_INVALID_RESPONSE'); }
        if (message?.type === 'error') helperError = typeof message.message === 'string' ? message.message : 'Speech recognition failed.';
        if (message?.type === 'final' && typeof message.text === 'string') finalText = message.text.trim();
      }
      if (helperError) throw voiceError(helperError, 'VOICE_RECOGNITION_FAILED');
      if (code !== 0) throw voiceError(`Speech recognition stopped unexpectedly${stderr.trim() ? `: ${stderr.trim().slice(0, 400)}` : '.'}`, 'VOICE_RECOGNITION_FAILED');
      if (!finalText) throw voiceError('No speech was recognized. Try again and check your microphone.', 'VOICE_NO_SPEECH');
      return finalText;
    });
  }

  return {
    getStatus,
    getVoiceStatus: getStatus,
    speak,
    stopSpeaking: () => stop('speaking'),
    transcribeNative,
    stopNativeRecognition: () => stop('recognition'),
  };
}

module.exports = { createVoiceService };
