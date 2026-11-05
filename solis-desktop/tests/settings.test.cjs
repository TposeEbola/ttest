'use strict';

const test = require('node:test');
const assert = require('node:assert/strict');
const fs = require('node:fs');
const os = require('node:os');
const path = require('node:path');
const crypto = require('node:crypto');
const { createSettingsStore, validateEndpoint } = require('../src/main/settings.cjs');

function fixture(t, { available = true } = {}) {
  const directory = fs.mkdtempSync(path.join(os.tmpdir(), 'solis-settings-test-'));
  t.after(() => fs.rmSync(directory, { recursive: true, force: true }));
  const secret = crypto.randomBytes(32);
  const safeStorage = {
    isEncryptionAvailable: () => available,
    encryptString(text) {
      const iv = crypto.randomBytes(12);
      const cipher = crypto.createCipheriv('aes-256-gcm', secret, iv);
      const ciphertext = Buffer.concat([cipher.update(text, 'utf8'), cipher.final()]);
      return Buffer.concat([iv, cipher.getAuthTag(), ciphertext]);
    },
    decryptString(buffer) {
      const decipher = crypto.createDecipheriv('aes-256-gcm', secret, buffer.subarray(0, 12));
      decipher.setAuthTag(buffer.subarray(12, 28));
      return Buffer.concat([decipher.update(buffer.subarray(28)), decipher.final()]).toString('utf8');
    },
  };
  const filePath = path.join(directory, 'settings.json');
  return { directory, filePath, safeStorage, store: createSettingsStore({ filePath, safeStorage }) };
}

test('defaults are offline with Colombian Spanish female voice preference and no secret', t => {
  const { store, filePath } = fixture(t);
  const settings = store.load();
  assert.equal(settings.provider, 'local');
  assert.equal(settings.voiceReplies, true);
  assert.equal(settings.speechSource, 'native');
  assert.equal(settings.voiceLocale, 'es-CO');
  assert.equal(settings.voiceGender, 'female');
  assert.equal(settings.hasApiKey, false);
  assert.equal(Object.hasOwn(settings, 'apiKey'), false);
  assert.equal(fs.existsSync(filePath), false);
});

test('key is encrypted on disk, absent from renderer settings, and decrypts after restart', t => {
  const { store, filePath, safeStorage } = fixture(t);
  const key = 'test-key-should-never-be-written-as-plaintext';
  const saved = store.save({ provider: 'openai', apiKey: key });
  assert.equal(saved.hasApiKey, true);
  assert.equal(saved.endpoint, 'https://api.openai.com/v1');
  assert.equal(saved.model, 'gpt-4.1-mini');
  assert.equal(JSON.stringify(saved).includes(key), false);
  const text = fs.readFileSync(filePath, 'utf8');
  assert.equal(text.includes(key), false);
  const persisted = JSON.parse(text);
  assert.ok(persisted.credential.encryptedApiKey);
  assert.equal(persisted.credential.origin, 'https://api.openai.com');
  assert.equal(persisted.settings.apiKey, undefined);
  const restarted = createSettingsStore({ filePath, safeStorage });
  assert.equal(restarted.load().hasApiKey, true);
  assert.equal(restarted.getForRequest().apiKey, key);
  assert.equal(restarted.getForRequest().apiKeyOrigin, 'https://api.openai.com');
});

test('missing OS encryption persists configuration and holds key in session memory only', t => {
  const { store, filePath, safeStorage } = fixture(t, { available: false });
  const key = 'session-only-secret';
  const saved = store.save({ provider: 'openai', model: 'custom-model', apiKey: key, voiceReplies: false });
  assert.equal(saved.hasApiKey, true);
  assert.match(saved.warning, /session only/);
  assert.equal(saved.secureStorageAvailable, false);
  assert.equal(store.getForRequest().apiKey, key);
  const document = JSON.parse(fs.readFileSync(filePath, 'utf8'));
  assert.equal(document.credential, undefined);
  assert.equal(document.settings.model, 'custom-model');
  assert.equal(document.settings.voiceReplies, false);
  assert.equal(JSON.stringify(document).includes(key), false);
  store.save({ voiceReplies: true });
  assert.equal(store.getForRequest().apiKey, key);
  const restarted = createSettingsStore({ filePath, safeStorage });
  assert.equal(restarted.load().hasApiKey, false);
  assert.equal(restarted.getForRequest().apiKey, '');
  assert.equal(restarted.load().model, 'custom-model');
});

test('failed encryption also holds a key in memory and still saves nonsecret configuration', t => {
  const { filePath, safeStorage } = fixture(t);
  safeStorage.encryptString = () => { throw new Error('operating system refused'); };
  const store = createSettingsStore({ filePath, safeStorage });
  assert.match(store.save({ provider: 'openai', apiKey: 'memory-only', voiceId: 'Monica' }).warning, /could not be encrypted/);
  assert.equal(store.getForRequest().apiKey, 'memory-only');
  assert.equal(fs.readFileSync(filePath, 'utf8').includes('memory-only'), false);
  assert.equal(JSON.parse(fs.readFileSync(filePath, 'utf8')).settings.voiceId, 'Monica');
});

test('blank key preserves existing key and explicit clear removes it from disk and memory', t => {
  const { store, filePath } = fixture(t);
  store.save({ provider: 'openai', apiKey: 'test-key' });
  store.save({ apiKey: '   ', model: 'other-model' });
  assert.equal(store.getForRequest().apiKey, 'test-key');
  assert.equal(store.save({ clearApiKey: true, apiKey: 'ignored-value' }).hasApiKey, false);
  assert.equal(store.getForRequest().apiKey, '');
  assert.equal(JSON.parse(fs.readFileSync(filePath, 'utf8')).credential, undefined);
});

test('credentials are bound to server origin, retained for path edits and cleared for host edits', t => {
  const { store, filePath } = fixture(t);
  store.save({ provider: 'openai', apiKey: 'first-origin-key' });
  store.save({ endpoint: 'https://api.openai.com/other-prefix' });
  assert.equal(store.getForRequest().apiKey, 'first-origin-key');
  const changed = store.save({ endpoint: 'https://example.com/v1' });
  assert.equal(changed.hasApiKey, false);
  assert.match(changed.warning, /server changed/);
  assert.equal(store.getForRequest().apiKey, '');
  assert.equal(JSON.parse(fs.readFileSync(filePath, 'utf8')).credential, undefined);
  store.save({ endpoint: 'https://api.openai.com/v1' });
  assert.equal(store.getForRequest().apiKey, '');
});

test('a new endpoint can receive only a newly supplied key', t => {
  const { store } = fixture(t);
  store.save({ provider: 'openai', apiKey: 'old-key' });
  store.save({ endpoint: 'https://example.com/v1', apiKey: 'new-key' });
  assert.equal(store.getForRequest().apiKey, 'new-key');
  assert.equal(store.getForRequest().apiKeyOrigin, 'https://example.com');
});

test('switching provider picks usable defaults without carrying old credentials', t => {
  const { store } = fixture(t);
  store.save({ provider: 'openaiCompatible', apiKey: 'old-key' });
  assert.equal(store.load().provider, 'openai');
  const ollama = store.save({ provider: 'ollama' });
  assert.equal(ollama.endpoint, 'http://127.0.0.1:11434');
  assert.equal(ollama.model, 'llama3.2');
  assert.equal(ollama.hasApiKey, false);
  assert.equal(store.save({ provider: 'local' }).endpoint, '');
});

test('remote model servers require HTTPS; HTTP accepts only local loopback interfaces', () => {
  for (const endpoint of ['https://api.openai.com/v1/', 'https://example.com:9443/prefix']) assert.ok(validateEndpoint(endpoint).startsWith('https:'));
  for (const endpoint of ['http://localhost:11434', 'http://127.0.0.1:8080/v1', 'http://127.4.5.6:8080', 'http://[::1]:11434']) assert.ok(validateEndpoint(endpoint).startsWith('http:'));
  for (const endpoint of ['http://example.com/v1', 'http://192.168.0.5:8080', 'http://localhost.example.com', 'http://0.0.0.0:8080', 'ftp://localhost', 'file:///etc/passwd', 'https://user:pass@example.com', 'https://example.com?key=secret', 'https://example.com#fragment', 'https://example.com?', 'https://example.com#']) {
    assert.throws(() => validateEndpoint(endpoint));
  }
});

test('invalid settings never replace the saved file or active configuration', t => {
  const { store, filePath } = fixture(t);
  store.save({ provider: 'ollama', voiceId: 'Monica' });
  const before = fs.readFileSync(filePath, 'utf8');
  for (const partial of [{ provider: 'unknown' }, { endpoint: 'http://example.com' }, { model: '' }, { model: 'x'.repeat(201) }, { voiceReplies: 'yes' }, { speechSource: 'shell' }, { voiceLocale: '../../en' }, { voiceGender: 'invented' }, { voiceId: 'x'.repeat(201) }, { apiKey: 4 }, { clearApiKey: 'yes' }, null]) {
    assert.throws(() => store.save(partial));
    assert.equal(fs.readFileSync(filePath, 'utf8'), before);
  }
  assert.equal(store.load().model, 'llama3.2');
  assert.equal(store.load().voiceId, 'Monica');
});

test('saved settings use atomic sibling replacement and owner-only permissions', t => {
  const { store, filePath, directory } = fixture(t);
  store.save({ voiceReplies: false });
  const oldInode = fs.statSync(filePath).ino;
  store.save({ voiceReplies: true });
  assert.equal(JSON.parse(fs.readFileSync(filePath, 'utf8')).settings.voiceReplies, true);
  if (process.platform !== 'win32') {
    assert.equal(fs.statSync(filePath).mode & 0o777, 0o600);
    assert.notEqual(fs.statSync(filePath).ino, oldInode);
  }
  assert.deepEqual(fs.readdirSync(directory), ['settings.json']);
});

test('unrecognized or corrupt files are preserved instead of overwritten', t => {
  const { filePath, safeStorage } = fixture(t);
  for (const contents of ['a user-owned file', '{"unrelated":"project"}', '{"format":"project-solis-settings","version":1,"settings":{"provider":"bad"}}']) {
    fs.writeFileSync(filePath, contents);
    const store = createSettingsStore({ filePath, safeStorage });
    assert.match(store.load().warning, /preserved/);
    assert.throws(() => store.save({ voiceReplies: false }), /preserved/);
    assert.equal(fs.readFileSync(filePath, 'utf8'), contents);
  }
});

test('a symbolic link settings target cannot overwrite an unrelated file', { skip: process.platform === 'win32' }, t => {
  const { filePath, safeStorage, directory } = fixture(t);
  const otherFile = path.join(directory, 'unrelated.txt');
  fs.writeFileSync(otherFile, 'keep this file');
  fs.symlinkSync(otherFile, filePath);
  const store = createSettingsStore({ filePath, safeStorage });
  assert.match(store.load().warning, /preserved/);
  assert.throws(() => store.save({ provider: 'local' }), /preserved/);
  assert.equal(fs.readFileSync(otherFile, 'utf8'), 'keep this file');
});

test('unavailable decryption never reports a usable key or exposes decrypt errors', t => {
  const { filePath, store, safeStorage } = fixture(t);
  store.save({ provider: 'openai', apiKey: 'original-key' });
  safeStorage.decryptString = () => { throw new Error('do not expose original-key'); };
  const restarted = createSettingsStore({ filePath, safeStorage });
  const config = restarted.load();
  assert.equal(config.hasApiKey, false);
  assert.match(config.warning, /could not be unlocked/);
  assert.equal(JSON.stringify(config).includes('original-key'), false);
  assert.equal(restarted.getForRequest().apiKey, '');
  assert.match(restarted.save({ voiceReplies: false }).warning, /could not be unlocked/);
});

test('credential origin tampering cannot attach a saved secret to another host', t => {
  const { filePath, store, safeStorage } = fixture(t);
  store.save({ provider: 'openai', apiKey: 'original-key' });
  const document = JSON.parse(fs.readFileSync(filePath, 'utf8'));
  document.settings.endpoint = 'https://different.example/v1';
  fs.writeFileSync(filePath, JSON.stringify(document));
  const restarted = createSettingsStore({ filePath, safeStorage });
  assert.equal(restarted.load().hasApiKey, false);
  assert.equal(restarted.getForRequest().apiKey, '');
  assert.match(restarted.load().warning, /unavailable for this model server/);
});

test('unknown input properties and API key fields never leak into persisted config', t => {
  const { store, filePath } = fixture(t);
  store.save({ provider: 'openai', apiKey: 'only-encrypted', systemPrompt: 'ignored', extra: { apiKey: 'ignored-secret' } });
  const document = JSON.parse(fs.readFileSync(filePath, 'utf8'));
  assert.equal(document.settings.systemPrompt, undefined);
  assert.equal(document.settings.extra, undefined);
  assert.equal(JSON.stringify(document).includes('ignored-secret'), false);
});
