'use strict';

const fs = require('node:fs');
const path = require('node:path');
const crypto = require('node:crypto');

const FORMAT = 'project-solis-settings';
const PROVIDERS = Object.freeze({
  local: { endpoint: '', model: '' },
  ollama: { endpoint: 'http://127.0.0.1:11434', model: 'llama3.2' },
  openai: { endpoint: 'https://api.openai.com/v1', model: 'gpt-4.1-mini' },
});
const DEFAULTS = Object.freeze({
  provider: 'local',
  endpoint: '',
  model: '',
  voiceReplies: true,
  speechSource: 'native',
  voiceLocale: 'es-CO',
  voiceGender: 'female',
  voiceId: '',
});

function normalizeProvider(value) {
  const provider = value === 'openaiCompatible' ? 'openai' : value;
  if (!Object.hasOwn(PROVIDERS, provider)) {
    throw new Error('Choose Local, Ollama, or OpenAI-compatible as the assistant provider.');
  }
  return provider;
}

function validateEndpoint(value) {
  if (typeof value !== 'string' || !value.trim() || value.length > 2048 || /[\u0000-\u001f\u007f]/.test(value)) {
    throw new Error('Enter a valid model server URL.');
  }
  let url;
  try { url = new URL(value.trim()); } catch { throw new Error('Enter a valid model server URL.'); }
  if (url.username || url.password || url.search || url.hash || value.includes('?') || value.includes('#')) {
    throw new Error('The model server URL cannot include credentials, a query, or a fragment.');
  }
  const host = url.hostname.toLowerCase();
  const ipv4 = host.split('.');
  const loopback = host === 'localhost' || host === '[::1]' || host === '::1' ||
    (ipv4.length === 4 && ipv4[0] === '127' && ipv4.every(part => /^\d+$/.test(part) && Number(part) <= 255));
  if (url.protocol !== 'https:' && !(url.protocol === 'http:' && loopback)) {
    throw new Error('Use HTTPS for a remote server. HTTP is allowed only for a loopback server on this computer.');
  }
  return url.href.replace(/\/+$/, '');
}

function endpointOrigin(endpoint) {
  return endpoint ? new URL(validateEndpoint(endpoint)).origin : '';
}

function boundedString(value, name, length, allowEmpty = false) {
  if (typeof value !== 'string' || value.length > length || /[\u0000-\u001f\u007f]/.test(value) || (!allowEmpty && !value.trim())) {
    throw new Error(`Enter a valid ${name}.`);
  }
  return value.trim();
}

function validatedSettings(partial, previous = DEFAULTS) {
  if (!partial || typeof partial !== 'object' || Array.isArray(partial)) throw new Error('Settings must be an object.');
  const next = { ...previous };
  if (Object.hasOwn(partial, 'provider')) next.provider = normalizeProvider(partial.provider);
  const changedProvider = next.provider !== previous.provider;
  if (changedProvider) Object.assign(next, PROVIDERS[next.provider]);
  if (Object.hasOwn(partial, 'endpoint')) {
    next.endpoint = next.provider === 'local' && partial.endpoint === '' ? '' : validateEndpoint(partial.endpoint);
  }
  if (Object.hasOwn(partial, 'model')) next.model = boundedString(partial.model, 'model name', 200, next.provider === 'local');
  if (next.provider !== 'local') {
    next.endpoint = validateEndpoint(next.endpoint);
    next.model = boundedString(next.model, 'model name', 200);
  }
  if (Object.hasOwn(partial, 'voiceReplies')) {
    if (typeof partial.voiceReplies !== 'boolean') throw new Error('Voice replies must be enabled or disabled.');
    next.voiceReplies = partial.voiceReplies;
  }
  if (Object.hasOwn(partial, 'speechSource')) {
    if (!['native', 'browser'].includes(partial.speechSource)) throw new Error('Choose native or browser speech recognition.');
    next.speechSource = partial.speechSource;
  }
  if (Object.hasOwn(partial, 'voiceLocale')) {
    if (typeof partial.voiceLocale !== 'string' || partial.voiceLocale.length > 48 || !/^[a-zA-Z]{2,8}(?:-[a-zA-Z0-9]{1,8})*$/.test(partial.voiceLocale)) {
      throw new Error('Enter a valid voice language, such as es-CO.');
    }
    next.voiceLocale = partial.voiceLocale;
  }
  if (Object.hasOwn(partial, 'voiceGender')) {
    if (!['female', 'male', 'any'].includes(partial.voiceGender)) throw new Error('Choose female, male, or any voice.');
    next.voiceGender = partial.voiceGender;
  }
  if (Object.hasOwn(partial, 'voiceId')) next.voiceId = boundedString(partial.voiceId, 'voice name', 200, true);
  return next;
}

function createSettingsStore({ filePath, safeStorage } = {}) {
  if (typeof filePath !== 'string' || !path.isAbsolute(filePath)) throw new Error('An absolute settings file path is required.');
  let settings = { ...DEFAULTS };
  let loaded = false;
  let apiKey = '';
  let keyOrigin = '';
  let encryptedApiKey = '';
  let warnings = [];
  let fileBlocked = false;

  function encryptionAvailable() {
    try { return Boolean(safeStorage?.isEncryptionAvailable()); } catch { return false; }
  }

  function readDocument() {
    const stat = fs.lstatSync(filePath);
    if (!stat.isFile() || stat.isSymbolicLink() || stat.size > 262144) throw new Error('Unrecognized settings file.');
    const fd = fs.openSync(filePath, fs.constants.O_RDONLY | (fs.constants.O_NOFOLLOW || 0));
    try {
      const document = JSON.parse(fs.readFileSync(fd, 'utf8'));
      if (document.format !== FORMAT || document.version !== 1 || !document.settings || typeof document.settings !== 'object') {
        throw new Error('Unrecognized settings file.');
      }
      return document;
    } finally { fs.closeSync(fd); }
  }

  function ensureLoaded() {
    if (loaded) return;
    loaded = true;
    let document;
    try { document = readDocument(); } catch (error) {
      if (error.code === 'ENOENT') return;
      fileBlocked = true;
      warnings.push('The existing settings file could not be read safely. It has been preserved; move it aside before saving new settings.');
      return;
    }
    try { settings = validatedSettings(document.settings); } catch {
      fileBlocked = true;
      warnings.push('The existing settings contain invalid values. The file has been preserved; move it aside before saving new settings.');
      return;
    }
    const credential = document.credential;
    if (!credential) return;
    if (typeof credential.encryptedApiKey !== 'string' || credential.encryptedApiKey.length > 65536 || !/^[A-Za-z0-9+/]+={0,2}$/.test(credential.encryptedApiKey) || credential.origin !== endpointOrigin(settings.endpoint)) {
      warnings.push('The saved API key is unavailable for this model server. Enter the key again in Settings.');
      return;
    }
    encryptedApiKey = credential.encryptedApiKey;
    keyOrigin = credential.origin;
    if (!encryptionAvailable()) {
      warnings.push('Secure credential storage is unavailable. The saved API key cannot be unlocked; enter a key for this session if needed.');
      return;
    }
    try {
      const unlocked = safeStorage.decryptString(Buffer.from(encryptedApiKey, 'base64'));
      apiKey = boundedString(unlocked, 'API key', 8192);
    } catch {
      warnings.push('The saved API key could not be unlocked. Enter the key again in Settings.');
    }
  }

  function publicSettings() {
    const available = encryptionAvailable();
    const visibleWarnings = [...warnings];
    if (!available && !visibleWarnings.some(message => message.includes('Secure credential storage'))) {
      visibleWarnings.push('Secure credential storage is unavailable. New API keys stay in memory for this session only.');
    }
    return {
      ...settings,
      hasApiKey: Boolean(apiKey && keyOrigin === endpointOrigin(settings.endpoint)),
      secureStorageAvailable: available,
      warnings: visibleWarnings,
      warning: visibleWarnings.join(' '),
    };
  }

  function writeDocument(document) {
    fs.mkdirSync(path.dirname(filePath), { recursive: true, mode: 0o700 });
    try { readDocument(); } catch (error) {
      if (error.code !== 'ENOENT') throw new Error('The existing settings file was preserved. Move it aside before saving new settings.');
    }
    const temporary = `${filePath}.${process.pid}.${crypto.randomUUID()}.tmp`;
    let fd;
    try {
      fd = fs.openSync(temporary, 'wx', 0o600);
      fs.writeFileSync(fd, `${JSON.stringify(document, null, 2)}\n`, 'utf8');
      fs.fsyncSync(fd);
      fs.closeSync(fd);
      fd = undefined;
      fs.renameSync(temporary, filePath);
    } catch {
      throw new Error('Settings could not be saved. Check that the app can write to its settings folder.');
    } finally {
      if (fd !== undefined) fs.closeSync(fd);
      try { fs.unlinkSync(temporary); } catch (error) { if (error.code !== 'ENOENT') { /* Best-effort temporary-file cleanup. */ } }
    }
  }

  return {
    load() { ensureLoaded(); return publicSettings(); },
    getForRequest() {
      ensureLoaded();
      return { ...settings, apiKey: keyOrigin === endpointOrigin(settings.endpoint) ? apiKey : '', apiKeyOrigin: keyOrigin };
    },
    save(partial) {
      ensureLoaded();
      if (fileBlocked) {
        try { fs.lstatSync(filePath); } catch (error) { if (error.code === 'ENOENT') fileBlocked = false; }
        if (fileBlocked) throw new Error('The existing settings file was preserved. Move it aside before saving new settings.');
      }
      const next = validatedSettings(partial, settings);
      if (Object.hasOwn(partial, 'clearApiKey') && typeof partial.clearApiKey !== 'boolean') throw new Error('Clear API key must be enabled or disabled.');
      if (Object.hasOwn(partial, 'apiKey') && typeof partial.apiKey !== 'string') throw new Error('Enter a valid API key.');
      const incomingKey = partial.apiKey?.trim() || '';
      if (incomingKey) boundedString(incomingKey, 'API key', 8192);
      const nextOrigin = endpointOrigin(next.endpoint);
      const changedOrigin = endpointOrigin(settings.endpoint) !== nextOrigin;
      let nextKey = changedOrigin || partial.clearApiKey ? '' : apiKey;
      let nextEncrypted = changedOrigin || partial.clearApiKey ? '' : encryptedApiKey;
      let nextKeyOrigin = changedOrigin || partial.clearApiKey ? '' : keyOrigin;
      const nextWarnings = [];
      if (incomingKey && !partial.clearApiKey) {
        if (next.provider === 'local' || !nextOrigin) throw new Error('Choose a model server before adding an API key.');
        nextKey = incomingKey;
        nextKeyOrigin = nextOrigin;
        nextEncrypted = '';
        if (encryptionAvailable()) {
          try { nextEncrypted = safeStorage.encryptString(nextKey).toString('base64'); } catch {
            nextWarnings.push('The API key could not be encrypted. It will stay in memory for this session only.');
          }
        } else nextWarnings.push('Secure credential storage is unavailable. The API key will stay in memory for this session only.');
      }
      if (nextKey && !nextEncrypted && !nextWarnings.length) {
        nextWarnings.push('The API key is held in memory for this session only.');
      }
      if (nextEncrypted && !nextKey) {
        nextWarnings.push('The saved API key could not be unlocked. Enter the key again in Settings.');
      }
      if (changedOrigin && !incomingKey && (apiKey || encryptedApiKey)) {
        nextWarnings.push('The previous API key was cleared because the model server changed.');
      }
      const document = { format: FORMAT, version: 1, settings: next };
      if (nextEncrypted) document.credential = { encryptedApiKey: nextEncrypted, origin: nextKeyOrigin };
      writeDocument(document);
      settings = next;
      apiKey = nextKey;
      encryptedApiKey = nextEncrypted;
      keyOrigin = nextKeyOrigin;
      warnings = nextWarnings;
      return publicSettings();
    },
  };
}

module.exports = { createSettingsStore, validateEndpoint, normalizeProvider, DEFAULTS, PROVIDERS };
