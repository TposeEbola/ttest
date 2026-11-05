'use strict';

document.addEventListener('DOMContentLoaded', () => {
  const byId = (id) => document.getElementById(id);
  const bridge = window.solis;
  const state = {
    status: null,
    settings: { provider: 'local', endpoint: '', model: '', voiceReplies: true, speechSource: 'native', voiceLocale: 'es-CO', voiceGender: 'female', voiceId: '' },
    history: [],
    busy: false,
    listening: false,
    speaking: false,
    speechRun: 0,
    voiceRun: 0,
    recognition: null,
    diagnosticsBusy: false,
    connected: false,
    activePanel: 'assistant',
  };

  const browserSpeech = window.SpeechRecognition || window.webkitSpeechRecognition;
  const prettyError = (error) => {
    const message = error && typeof error.message === 'string' ? error.message : String(error || 'Something went wrong.');
    return message.replace(/^Error invoking remote method '[^']+': (?:Error: )?/, '').slice(0, 1000);
  };

  document.querySelectorAll('img').forEach((img) => {
    const fallback = () => {
      img.hidden = true;
      const mark = img.parentElement.querySelector('.brand-fallback');
      if (mark) mark.hidden = false;
    };
    img.addEventListener('error', fallback);
    if (img.complete && img.naturalWidth === 0) fallback();
  });

  function activity(message, isError = false) {
    byId('activity').textContent = message;
    byId('activity').classList.toggle('is-error', isError);
  }

  function renderStatus() {
    let label = 'Desktop connection unavailable';
    if (state.connected) {
      label = state.listening ? 'Listening · click mic to stop' : state.speaking ? 'Speaking · Esc to stop' : state.busy ? 'Working on your request…' : state.settings.provider === 'local' ? 'Local tools ready' : 'AI provider configured';
    }
    byId('status-copy').textContent = label;
    byId('status-dot').classList.toggle('is-active', state.connected);
    byId('status-dot').classList.toggle('is-busy', state.listening || state.speaking || state.busy);
    byId('send-button').disabled = !state.connected || state.busy || state.listening || !byId('chat-input').value.trim();
    byId('send-button').firstChild.textContent = state.busy ? 'Thinking ' : 'Send ';
    byId('microphone-button').disabled = !state.connected || state.busy;
    byId('microphone-button').classList.toggle('is-listening', state.listening);
    byId('microphone-button').setAttribute('aria-pressed', String(state.listening));
    byId('microphone-button').setAttribute('aria-label', state.listening ? 'Cancel microphone' : 'Start microphone');
    byId('microphone-button').title = state.listening ? 'Cancel microphone' : 'Start microphone';
    byId('stop-voice').hidden = !state.speaking;
    byId('quick-voice').disabled = !state.connected || state.speaking;
    byId('quick-microphone').disabled = !state.connected || state.busy || state.listening;
    byId('composer-note').textContent = state.settings.provider === 'local'
      ? 'Local tools work without an AI provider. Connect a model in Settings for open-ended chat.'
      : 'Messages are sent to your configured model. Review voice transcripts before sending.';
  }

  function showPanel(panel, focusHeading = false) {
    if (!['assistant', 'diagnostics', 'settings'].includes(panel)) return;
    state.activePanel = panel;
    ['assistant', 'diagnostics', 'settings'].forEach((name) => {
      byId(`${name}-panel`).hidden = name !== panel;
    });
    document.querySelectorAll('[data-panel]').forEach((button) => {
      if (button.dataset.panel === panel) button.setAttribute('aria-current', 'page');
      else button.removeAttribute('aria-current');
    });
    byId('section-eyebrow').textContent = panel.toUpperCase();
    byId('workspace-heading').textContent = { assistant: 'Your space to think.', diagnostics: 'A little peace of mind.', settings: 'Make it feel like you.' }[panel];
    if (focusHeading) {
      const heading = byId(`${panel}-panel`).querySelector('h2');
      if (heading) { heading.tabIndex = -1; heading.focus({ preventScroll: true }); }
    }
  }

  document.querySelectorAll('[data-panel]').forEach((button) => button.addEventListener('click', () => showPanel(button.dataset.panel)));

  function appendMessage(role, text, mode) {
    byId('welcome-state').hidden = true;
    const row = document.createElement('article');
    row.className = `message ${role}`;
    const avatar = document.createElement('div');
    avatar.className = 'message-avatar';
    avatar.setAttribute('aria-hidden', 'true');
    avatar.textContent = role === 'user' ? 'Y' : 'S';
    const body = document.createElement('div');
    body.className = 'message-body';
    const label = document.createElement('div');
    label.className = 'message-role';
    label.textContent = role === 'user' ? 'You' : 'Solis';
    const message = document.createElement('div');
    message.className = 'message-text';
    message.textContent = String(text || '');
    body.append(label, message);
    if (mode) {
      const meta = document.createElement('div');
      meta.className = 'message-meta';
      meta.textContent = mode === 'model' ? 'AI model response' : 'Built-in local assistant';
      body.append(meta);
    }
    row.append(avatar, body);
    byId('conversation').append(row);
    row.scrollIntoView({ block: 'end', behavior: 'smooth' });
  }

  function resizeComposer() {
    const input = byId('chat-input');
    input.rows = Math.min(5, Math.max(2, input.value.split('\n').length));
    renderStatus();
  }

  async function stopSpeaking() {
    state.voiceRun += 1;
    state.speaking = false;
    try { if (bridge) await bridge.stopSpeaking(); } catch (error) { activity(`Could not stop voice: ${prettyError(error)}`, true); }
    renderStatus();
  }

  async function speak(text, sample = false) {
    if (!state.connected) return;
    if (!state.status?.voice?.ttsAvailable) {
      activity('A system voice is not available on this computer. Text replies still work.', true);
      return;
    }
    if (state.speaking) await stopSpeaking();
    const run = ++state.voiceRun;
    state.speaking = true;
    activity(sample ? 'Playing a hello with your system voice…' : 'Reading the reply aloud…');
    renderStatus();
    try {
      const result = await bridge.speak(text);
      if (run !== state.voiceRun) return;
      if (!result || result.ok !== true) throw new Error(result?.message || result?.error || 'The system voice could not confirm playback of this reply.');
      activity(sample ? 'Voice playback finished. Did you hear Solis? Check your Mac’s output volume if needed.' : 'Voice reply finished.');
    } catch (error) {
      if (run === state.voiceRun) activity(`Voice unavailable: ${prettyError(error)}`, true);
    } finally {
      if (run === state.voiceRun) { state.speaking = false; renderStatus(); }
    }
  }

  async function sendMessage(event) {
    event.preventDefault();
    const input = byId('chat-input');
    const text = input.value.trim();
    if (!text || state.busy || state.listening || !state.connected) return;
    if (state.speaking) await stopSpeaking();
    const history = state.history.slice(-24).map(({ role, content }) => ({ role, content }));
    appendMessage('user', text);
    input.value = '';
    resizeComposer();
    state.busy = true;
    activity('Solis is working on your request…');
    renderStatus();
    try {
      const response = await bridge.sendMessage({ text, history });
      if (!response || typeof response.text !== 'string' || !response.text.trim()) throw new Error('No reply was returned. Please try again.');
      appendMessage('assistant', response.text, response.mode);
      // Keep filesystem reports and other local tool output out of model context.
      if (response.mode === 'model') state.history.push({ role: 'user', content: text }, { role: 'assistant', content: response.text });
      if (response.diagnostics) renderDiagnostics(response.diagnostics);
      activity('');
      if (state.settings.voiceReplies) void speak(response.text);
    } catch (error) {
      appendMessage('error', `I couldn’t complete that request. ${prettyError(error)}`);
      activity('Your message is kept above. You can try again.', true);
    } finally {
      state.busy = false;
      renderStatus();
      input.focus();
    }
  }

  function permissionLabel(status) {
    return ({ granted: 'Granted', denied: 'Denied', restricted: 'Restricted', 'not-determined': 'Not requested', unknown: 'Not checked', unavailable: 'Unavailable', 'not-supported': 'Unavailable' })[status] || String(status || 'Not requested');
  }

  async function requestMicrophone() {
    if (!state.connected) throw new Error('The desktop connection is unavailable.');
    const permission = await bridge.requestMicrophone();
    byId('microphone-permission').textContent = permissionLabel(permission?.status);
    if (state.status) state.status.microphone = { status: permission?.status };
    return permission;
  }

  function applyTranscript(text) {
    if (!text || !String(text).trim()) {
      activity('No speech was captured. Try again when you’re ready.');
      return;
    }
    const input = byId('chat-input');
    const prefix = input.value.trim();
    input.value = `${prefix ? `${prefix} ` : ''}${String(text).trim()}`.slice(0, 12000);
    resizeComposer();
    showPanel('assistant');
    input.focus();
    input.setSelectionRange(input.value.length, input.value.length);
    activity('Transcript ready. Review your message, then press Send.');
  }

  async function stopListening(cancel = false) {
    if (!state.listening) return;
    if (cancel) state.speechRun += 1;
    try {
      if (state.recognition) {
        if (cancel) state.recognition.abort(); else state.recognition.stop();
      } else if (bridge) await bridge.stopListening();
    } catch (error) { activity(`Microphone stopped: ${prettyError(error)}`, true); }
    if (cancel) {
      state.listening = false;
      state.recognition = null;
      activity('Listening cancelled.');
      renderStatus();
    } else activity('Finishing your transcript…');
  }

  function listenInBrowser(run) {
    return new Promise((resolve, reject) => {
      if (!browserSpeech) { reject(new Error('Browser speech recognition is not available in this desktop runtime. Use native macOS recognition in Settings.')); return; }
      const recognition = new browserSpeech();
      state.recognition = recognition;
      recognition.lang = state.settings.voiceLocale || 'es-CO';
      recognition.interimResults = false;
      recognition.continuous = false;
      let transcript = '';
      let failure = null;
      recognition.onresult = (event) => {
        for (let index = event.resultIndex; index < event.results.length; index += 1) {
          if (event.results[index].isFinal) transcript += `${event.results[index][0].transcript} `;
        }
      };
      recognition.onerror = (event) => { failure = new Error(event.error === 'not-allowed' ? 'Microphone or speech permission was denied. Allow it in your system privacy settings.' : `Browser speech recognition: ${event.error || 'unavailable'}.`); };
      recognition.onend = () => {
        if (run === state.speechRun) state.recognition = null;
        if (failure) reject(failure); else resolve(transcript.trim());
      };
      try { recognition.start(); } catch (error) { state.recognition = null; reject(error); }
    });
  }

  async function startListening() {
    if (state.listening) { await stopListening(); return; }
    if (state.busy || !state.connected) return;
    showPanel('assistant');
    if (state.speaking) await stopSpeaking();
    const run = ++state.speechRun;
    state.listening = true;
    activity('Requesting microphone access…');
    renderStatus();
    try {
      const permission = await requestMicrophone();
      if (run !== state.speechRun) return;
      if (permission?.granted === false && !['unknown', 'not-determined'].includes(permission?.status)) throw new Error('Microphone access is not granted. Open System Settings → Privacy & Security → Microphone and allow Project Solis.');
      activity('Listening… Pause when finished to review your text. Esc or the microphone button cancels.');
      let text;
      if (state.settings.speechSource === 'browser') text = await listenInBrowser(run);
      else if (state.status?.voice?.speechAvailable) {
        const result = await bridge.startListening();
        text = result?.text;
      } else if (browserSpeech) {
        activity('Native recognition is unavailable. Using browser recognition…');
        text = await listenInBrowser(run);
      } else throw new Error('Speech recognition is unavailable here. On macOS, build the native speech helper and grant Speech Recognition access. You can always type a message.');
      if (run === state.speechRun) applyTranscript(text);
    } catch (error) {
      if (run === state.speechRun) activity(`Couldn’t capture speech. ${prettyError(error)}`, true);
    } finally {
      if (run === state.speechRun) { state.listening = false; state.recognition = null; renderStatus(); }
    }
  }

  function bytes(value) {
    const amount = Number(value);
    if (value === null || value === undefined || !Number.isFinite(amount) || amount < 0) return 'Unavailable';
    if (amount === 0) return '0 GB';
    const unit = amount >= 1e12 ? 'TB' : amount >= 1e9 ? 'GB' : amount >= 1e6 ? 'MB' : 'KB';
    const scale = { TB: 1e12, GB: 1e9, MB: 1e6, KB: 1e3 }[unit];
    return `${(amount / scale).toLocaleString(undefined, { maximumFractionDigits: 1 })} ${unit}`;
  }

  function appendDetail(title, detail, capacity) {
    const row = document.createElement('div');
    row.className = 'detail-row';
    const icon = document.createElement('span');
    icon.className = 'device-icon';
    icon.textContent = '▤';
    icon.setAttribute('aria-hidden', 'true');
    const text = document.createElement('div');
    text.className = 'device-copy';
    const name = document.createElement('strong');
    name.textContent = title;
    const info = document.createElement('span');
    info.textContent = detail;
    text.append(name, info);
    const size = document.createElement('span');
    size.className = 'device-capacity';
    size.textContent = capacity;
    row.append(icon, text, size);
    byId('disk-devices').append(row);
  }

  function renderDiagnostics(report) {
    if (!report || typeof report !== 'object') throw new Error('The storage report was unavailable.');
    const summary = report.summary || {};
    byId('diagnostics-empty').hidden = true;
    byId('diagnostics-report').hidden = false;
    byId('disk-total').textContent = bytes(summary.totalBytes);
    byId('disk-free').textContent = bytes(summary.freeBytes);
    byId('disk-used').textContent = bytes(summary.usedBytes);
    byId('legend-used').textContent = bytes(summary.usedBytes);
    byId('legend-free').textContent = bytes(summary.freeBytes);
    const percent = summary.usedPercent !== null && summary.usedPercent !== undefined && Number.isFinite(Number(summary.usedPercent)) ? Number(summary.usedPercent) : summary.totalBytes > 0 && summary.usedBytes >= 0 ? summary.usedBytes / summary.totalBytes * 100 : null;
    byId('disk-percent').textContent = percent === null ? 'Usage unavailable' : `${percent.toFixed(1)}% of reported capacity`;
    if (percent === null) byId('capacity-progress').removeAttribute('value');
    else byId('capacity-progress').value = Math.max(0, Math.min(100, percent));
    const generated = new Date(report.generatedAt);
    byId('report-generated').textContent = Number.isNaN(generated.getTime()) ? '' : `Updated ${generated.toLocaleTimeString([], { hour: '2-digit', minute: '2-digit' })}`;
    byId('disk-devices').replaceChildren();
    const volumes = Array.isArray(report.volumes) ? report.volumes : [];
    const devices = Array.isArray(report.devices) ? report.devices : [];
    volumes.forEach((volume) => appendDetail(
      String(volume.name || volume.label || volume.device || volume.mountPoint || volume.mount || 'Filesystem'),
      [volume.mountPoint || volume.mount, volume.fileSystem || volume.filesystem || volume.fsType || volume.type].filter(Boolean).join(' · ') || 'Reported volume',
      bytes(volume.totalBytes ?? volume.sizeBytes ?? volume.size),
    ));
    devices.forEach((device) => appendDetail(
      String(device.name || device.model || device.identifier || 'Storage device'),
      [device.type, device.fileSystem || device.filesystem, ...(Array.isArray(device.mountpoints) ? device.mountpoints : Array.isArray(device.mountPoints) ? device.mountPoints : [])].filter(Boolean).join(' · ') || 'Reported storage device',
      bytes(device.sizeBytes ?? device.totalBytes ?? device.size),
    ));
    if (!volumes.length && !devices.length) appendDetail('Current filesystem', 'Device details were not returned by this operating system.', bytes(summary.totalBytes));
    const warnings = Array.isArray(report.warnings) ? report.warnings : [];
    byId('diagnostic-warnings').replaceChildren();
    warnings.forEach((warning) => { const item = document.createElement('li'); item.textContent = String(warning); byId('diagnostic-warnings').append(item); });
    byId('diagnostic-warnings').hidden = warnings.length === 0;
  }

  async function runDiagnostics() {
    if (!state.connected || state.diagnosticsBusy) return;
    state.diagnosticsBusy = true;
    byId('run-diagnostics').disabled = true;
    byId('refresh-diagnostics').disabled = true;
    byId('diagnostics-status').textContent = 'Reading storage capacity and device information…';
    byId('diagnostics-status').classList.remove('is-error');
    try {
      renderDiagnostics(await bridge.getDiagnostics());
      byId('diagnostics-status').textContent = 'Read-only check complete. No disk changes were made.';
    } catch (error) {
      byId('diagnostics-status').textContent = `Couldn’t read storage information. ${prettyError(error)}`;
      byId('diagnostics-status').classList.add('is-error');
    } finally {
      state.diagnosticsBusy = false;
      byId('run-diagnostics').disabled = false;
      byId('refresh-diagnostics').disabled = false;
    }
  }

  function providerFields() {
    const provider = byId('provider').value;
    byId('model-fields').hidden = provider === 'local';
    byId('api-key-field').hidden = provider !== 'openai';
    byId('endpoint').placeholder = provider === 'ollama' ? 'http://127.0.0.1:11434' : 'https://api.openai.com/v1';
    byId('model').placeholder = provider === 'ollama' ? 'llama3.2' : 'gpt-4.1-mini';
  }

  function renderVoiceSettings() {
    const voice = state.status?.voice || {};
    const selected = voice.selectedVoice;
    const select = byId('voice-id');
    select.replaceChildren();
    const automatic = document.createElement('option');
    automatic.value = '';
    automatic.textContent = 'Automatic — closest available system voice';
    select.append(automatic);
    (Array.isArray(voice.availableVoices) ? voice.availableVoices : []).forEach((item) => {
      const option = document.createElement('option');
      option.value = String(item.id || item.identifier || item.name || '');
      option.textContent = [item.name, item.language || item.locale, item.gender].filter(Boolean).join(' · ');
      select.append(option);
    });
    if (state.settings.voiceId && !Array.from(select.options).some((option) => option.value === state.settings.voiceId)) {
      const saved = document.createElement('option'); saved.value = state.settings.voiceId; saved.textContent = `Saved voice: ${state.settings.voiceId}`; select.append(saved);
    }
    select.value = state.settings.voiceId || '';
    byId('selected-voice').textContent = selected
      ? `System voice: ${selected.name || selected.id || 'Unnamed'} · ${selected.language || selected.locale || 'language not reported'}${voice.voiceFallback ? '. This voice differs from the preferred female Colombian Spanish voice.' : ''}`
      : voice.ttsAvailable ? 'The closest installed system voice will be used. Exact Colombian Spanish availability depends on your computer.' : 'No system voice is available in this environment. Text replies remain available.';
    const nativeOption = Array.from(byId('speech-source').options).find((option) => option.value === 'native');
    nativeOption.textContent = state.status?.platform === 'darwin' ? 'Native macOS recognition' : 'Native recognition (macOS)';
    byId('speech-support').textContent = voice.speechAvailable
      ? `Native recognition available${voice.speechEngine ? ` · ${voice.speechEngine}` : ''}. Dictation recognizes English (en-US); reply voices have a separate preference.`
      : browserSpeech ? 'Browser recognition is available as a fallback. It may use the browser provider’s online speech service.' : 'Speech recognition is unavailable in this runtime. Native macOS support requires the speech helper and permissions.';
    if (voice.speechAvailable && browserSpeech) byId('speech-support').textContent += ' Browser recognition may use an online speech service.';
  }

  function fillSettings(settings) {
    state.settings = { ...state.settings, ...settings, provider: settings.provider === 'openaiCompatible' ? 'openai' : settings.provider || 'local' };
    byId('provider').value = state.settings.provider;
    byId('endpoint').value = state.settings.endpoint || '';
    byId('model').value = state.settings.model || '';
    byId('voice-replies').checked = state.settings.voiceReplies !== false;
    byId('speech-source').value = state.settings.speechSource || 'native';
    byId('api-key').value = '';
    byId('api-key').placeholder = state.settings.hasApiKey ? 'Saved key · leave blank to keep it' : 'Enter your API key';
    byId('api-key-help').textContent = state.settings.hasApiKey ? 'A key is saved. Leave this blank to keep it, or enter a replacement.' : 'Your saved key is never displayed here.';
    const warnings = [settings.warning, ...(Array.isArray(settings.warnings) ? settings.warnings : [])].filter(Boolean);
    byId('settings-status').textContent = [...new Set(warnings)].join(' ');
    providerFields();
    renderVoiceSettings();
    renderStatus();
  }

  function settingsInput() {
    const settings = {
      provider: byId('provider').value,
      endpoint: byId('endpoint').value.trim(),
      model: byId('model').value.trim(),
      voiceReplies: byId('voice-replies').checked,
      speechSource: byId('speech-source').value,
      voiceLocale: 'es-CO',
      voiceGender: 'female',
      voiceId: byId('voice-id').value,
    };
    if (byId('api-key').value) settings.apiKey = byId('api-key').value;
    return settings;
  }

  async function saveSettings(event) {
    event.preventDefault();
    if (!state.connected) return;
    byId('save-settings').disabled = true;
    byId('settings-status').textContent = 'Saving preferences…';
    byId('settings-status').classList.remove('is-error');
    try {
      const settings = await bridge.saveSettings(settingsInput());
      fillSettings(settings);
      byId('settings-status').textContent = `Preferences saved.${settings.warning ? ` ${settings.warning}` : ''}`;
      try { state.status = await bridge.getStatus(); renderVoiceSettings(); } catch { /* Keep the last honest capability report if a refresh fails. */ }
    } catch (error) {
      byId('settings-status').textContent = `Couldn’t save preferences. ${prettyError(error)}`;
      byId('settings-status').classList.add('is-error');
    } finally { byId('save-settings').disabled = false; renderStatus(); }
  }

  async function testConnection() {
    if (!state.connected) return;
    byId('test-connection').disabled = true;
    byId('settings-status').textContent = 'Testing the saved provider settings…';
    byId('settings-status').classList.remove('is-error');
    try {
      const result = await bridge.testConnection();
      byId('settings-status').textContent = result?.message || (result?.ok ? 'Connection succeeded.' : 'Connection could not be established.');
      byId('settings-status').classList.toggle('is-error', !result?.ok);
    } catch (error) {
      byId('settings-status').textContent = prettyError(error);
      byId('settings-status').classList.add('is-error');
    } finally { byId('test-connection').disabled = false; }
  }

  byId('chat-form').addEventListener('submit', sendMessage);
  byId('chat-input').addEventListener('input', resizeComposer);
  byId('chat-input').addEventListener('keydown', (event) => {
    if (event.key === 'Enter' && !event.shiftKey && !event.isComposing) { event.preventDefault(); byId('chat-form').requestSubmit(); }
  });
  byId('microphone-button').addEventListener('click', startListening);
  byId('quick-microphone').addEventListener('click', startListening);
  byId('quick-voice').addEventListener('click', () => { void speak('Hola, soy Solis, tu asistente de escritorio. Estoy aquí para ayudarte.', true); });
  byId('stop-voice').addEventListener('click', stopSpeaking);
  byId('quick-diagnostics').addEventListener('click', () => { showPanel('diagnostics', true); void runDiagnostics(); });
  byId('run-diagnostics').addEventListener('click', runDiagnostics);
  byId('refresh-diagnostics').addEventListener('click', runDiagnostics);
  byId('provider').addEventListener('change', providerFields);
  byId('settings-form').addEventListener('submit', saveSettings);
  byId('test-connection').addEventListener('click', testConnection);
  byId('request-microphone').addEventListener('click', async () => {
    byId('request-microphone').disabled = true;
    try {
      const result = await requestMicrophone();
      byId('settings-status').textContent = result?.granted ? 'Microphone access granted. Start listening from the Assistant tab.' : `Microphone access: ${permissionLabel(result?.status)}. Check your system privacy settings if needed.`;
    } catch (error) { byId('settings-status').textContent = prettyError(error); }
    finally { byId('request-microphone').disabled = false; }
  });
  document.addEventListener('keydown', (event) => {
    if (event.key !== 'Escape') return;
    if (state.listening) void stopListening(true);
    if (state.speaking) { void stopSpeaking(); activity('Voice reply stopped.'); }
  });

  async function initialize() {
    renderStatus();
    if (!bridge || typeof bridge.getStatus !== 'function') {
      byId('global-banner').hidden = false;
      byId('global-banner').textContent = 'The desktop connection is unavailable. Launch Project Solis through the desktop app to use chat, voice, and diagnostics.';
      byId('settings-status').textContent = 'Desktop preferences are unavailable in a standalone browser.';
      ['run-diagnostics', 'refresh-diagnostics', 'save-settings', 'test-connection', 'request-microphone'].forEach((id) => { byId(id).disabled = true; });
      return;
    }
    const results = await Promise.allSettled([bridge.getStatus(), bridge.getSettings()]);
    if (results[0].status === 'fulfilled') {
      state.status = results[0].value;
      state.connected = true;
      byId('platform-label').textContent = state.status.osLabel || ({ darwin: 'macOS', win32: 'Windows', linux: 'Linux' })[state.status.platform] || 'Desktop';
      byId('version-label').textContent = `PROJECT SOLIS${state.status.version ? ` / ${state.status.version}` : ''}`;
      byId('microphone-permission').textContent = permissionLabel(state.status.microphone?.status);
    } else {
      byId('global-banner').hidden = false;
      byId('global-banner').textContent = `Couldn’t connect to the desktop app. ${prettyError(results[0].reason)}`;
    }
    if (results[1].status === 'fulfilled') fillSettings(results[1].value);
    else {
      byId('settings-status').textContent = `Couldn’t load preferences. ${prettyError(results[1].reason)}`;
      renderVoiceSettings();
    }
    renderStatus();
  }

  void initialize();
});
