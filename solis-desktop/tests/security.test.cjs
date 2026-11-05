'use strict';

const { test } = require('node:test');
const assert = require('node:assert/strict');
const { createPermissionPolicy, assertTrustedSender, validateText } = require('../src/main/security.cjs');

const entryUrl = 'file:///Applications/Project%20Solis.app/Contents/Resources/app/src/renderer/index.html';
const trusted = { id: 7, getURL: () => entryUrl, isDestroyed: () => false };
const policy = createPermissionPolicy({ entryUrl, getWebContents: () => trusted });

function request(webContents = trusted, permission, details) {
  if (arguments.length < 2) permission = 'media';
  if (arguments.length < 3) details = { mediaTypes: ['audio'] };
  const decisions = [];
  policy.requestHandler(webContents, permission, (allowed) => decisions.push(allowed), details);
  assert.equal(decisions.length, 1, 'permission callbacks settle exactly once');
  return decisions[0];
}

test('only the bound application window receives audio-only microphone permission', () => {
  assert.equal(request(), true);
  assert.equal(request(trusted, 'media', {
    mediaTypes: ['audio'], requestingUrl: entryUrl, isMainFrame: true, securityOrigin: 'file://',
  }), true);
  assert.equal(policy.checkHandler(trusted, 'media', 'file://', { mediaType: 'audio' }), true);
  assert.equal(policy.checkHandler(trusted, 'media', entryUrl, {
    mediaType: 'audio', requestingUrl: entryUrl, isMainFrame: true,
  }), true);
});

test('camera, screen capture, and every other permission deny by default', () => {
  for (const permission of [
    'camera', 'display-capture', 'mediaKeySystem', 'notifications', 'clipboard-read',
    'clipboard-sanitized-write', 'fileSystem', 'geolocation', 'midi', 'midiSysex',
    'pointerLock', 'fullscreen', 'serial', 'usb', 'hid', 'unknown', '__proto__',
    'constructor', '', undefined, null, new String('media'),
  ]) {
    assert.equal(request(trusted, permission), false);
    assert.equal(policy.checkHandler(trusted, permission, 'file://', { mediaType: 'audio' }), false);
  }
  for (const mediaTypes of [[], ['video'], ['audio', 'video'], ['audio', 'screen'], ['Audio'], ['audio', null], Array(1)]) {
    assert.equal(request(trusted, 'media', { mediaTypes }), false);
  }
  for (const mediaType of ['video', 'unknown', 'audio,video', '', null, undefined, new String('audio')]) {
    assert.equal(policy.checkHandler(trusted, 'media', 'file://', { mediaType }), false);
  }
});

test('different windows, navigated windows, remote frames, and spoofed file URLs cannot request microphone access', () => {
  for (const webContents of [
    null, { ...trusted, id: 8 }, { ...trusted, getURL: () => 'https://example.com' },
    { ...trusted, getURL: () => `${entryUrl}#spoof` }, { ...trusted, isDestroyed: () => true },
    { ...trusted, getURL: () => { throw new Error('destroyed'); } },
  ]) {
    assert.equal(request(webContents), false);
    assert.equal(policy.checkHandler(webContents, 'media', 'file://', { mediaType: 'audio' }), false);
  }
  for (const detail of [
    { isMainFrame: false }, { requestingUrl: 'https://example.com' },
    { requestingUrl: 'file:///tmp/other.html' }, { requestingUrl: `${entryUrl}?spoof` },
    { securityOrigin: 'https://example.com' }, { securityOrigin: 'file:///tmp/other.html' },
  ]) {
    assert.equal(request(trusted, 'media', { ...detail, mediaTypes: ['audio'] }), false);
    assert.equal(policy.checkHandler(trusted, 'media', 'file://', { ...detail, mediaType: 'audio' }), false);
  }
  for (const origin of ['https://example.com', 'file:///tmp/other.html', 'file://evil.example', 'null', '', null]) {
    assert.equal(policy.checkHandler(trusted, 'media', origin, { mediaType: 'audio' }), false);
  }
});

test('missing or inherited media metadata and exceptional getters fail closed', () => {
  for (const details of [undefined, null, {}, Object.create({ mediaTypes: ['audio'], mediaType: 'audio' }), {
    get mediaTypes() { throw new Error('unexpected'); },
    get mediaType() { throw new Error('unexpected'); },
  }]) {
    assert.equal(request(trusted, 'media', details), false);
    assert.equal(policy.checkHandler(trusted, 'media', 'file://', details), false);
  }
  const inheritedFrame = Object.assign(Object.create({ isMainFrame: false }), { mediaTypes: ['audio'], mediaType: 'audio' });
  assert.equal(request(trusted, 'media', inheritedFrame), false);
  assert.equal(policy.checkHandler(trusted, 'media', 'file://', inheritedFrame), false);
  let decision;
  policy.requestHandler(trusted, 'media', (allowed) => { decision = allowed; }, undefined);
  assert.equal(decision, false);
  const noWindow = createPermissionPolicy({ entryUrl, getWebContents: () => null });
  noWindow.requestHandler(trusted, 'media', (allowed) => { decision = allowed; }, { mediaTypes: ['audio'] });
  assert.equal(decision, false);
});

test('permission policy observes the current bound window after replacement or navigation', () => {
  let current = trusted;
  const live = createPermissionPolicy({ entryUrl, getWebContents: () => current });
  assert.equal(live.checkHandler(trusted, 'media', 'file://', { mediaType: 'audio' }), true);
  current = { ...trusted, id: 9 };
  assert.equal(live.checkHandler(trusted, 'media', 'file://', { mediaType: 'audio' }), false);
  assert.equal(live.checkHandler(current, 'media', 'file://', { mediaType: 'audio' }), true);
  current = { ...current, getURL: () => 'https://example.com' };
  assert.equal(live.checkHandler(current, 'media', 'file://', { mediaType: 'audio' }), false);
});

test('IPC requires the exact trusted sender ID and top-frame URL', () => {
  const event = { sender: trusted, senderFrame: { url: entryUrl, parent: null } };
  assert.equal(assertTrustedSender(event, { entryUrl, webContentsId: trusted.id }), undefined);
  for (const spoof of [
    null, {}, { ...event, sender: { ...trusted, id: 8 } },
    { ...event, senderFrame: null },
    { ...event, senderFrame: { url: 'https://example.com', parent: null } },
    { ...event, senderFrame: { url: 'file:///tmp/other.html', parent: null } },
    { ...event, senderFrame: { url: `${entryUrl}#spoof`, parent: null } },
    { ...event, senderFrame: { url: entryUrl, parent: { url: 'https://example.com' } } },
    { ...event, sender: { ...trusted, getURL: () => 'https://example.com' } },
    { ...event, sender: { ...trusted, isDestroyed: () => true } },
  ]) {
    assert.throws(() => assertTrustedSender(spoof, { entryUrl, webContentsId: trusted.id }), { code: 'UNTRUSTED_SENDER' });
  }
});

test('text payload validation trims real text, enforces limits, and rejects non-text/null payloads', () => {
  assert.equal(validateText('  hello Solis\n'), 'hello Solis');
  assert.equal(validateText('a'.repeat(8000)), 'a'.repeat(8000));
  assert.equal(validateText(' OK ', { maxLength: 4, label: 'reply' }), 'OK');
  for (const value of ['', ' \n\t ', 'hello\0world', { toString: () => 'text' }, ['text'], new String('text'), null, undefined, 1]) {
    assert.throws(() => validateText(value), { code: 'INVALID_TEXT' });
  }
  assert.throws(() => validateText('a'.repeat(8001)), { code: 'TEXT_TOO_LONG' });
  assert.throws(() => validateText('abc', { maxLength: 2, label: 'reply' }), { code: 'TEXT_TOO_LONG' });
  for (const maxLength of [0, -1, 1.5, Infinity, '8000', 1_000_001]) {
    assert.throws(() => validateText('text', { maxLength }), TypeError);
  }
});
