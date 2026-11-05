'use strict';

function securityError(code, message) {
  const error = new Error(message);
  error.code = code;
  return error;
}

function own(object, key) {
  return object !== null && typeof object === 'object' && Object.hasOwn(object, key);
}

function validEntryUrl(entryUrl) {
  return typeof entryUrl === 'string' && entryUrl.length > 0 && !entryUrl.includes('\0');
}

function trustedOrigin(origin, entryUrl) {
  if (typeof origin !== 'string' || !origin) return false;
  if (origin === entryUrl) return true;
  try {
    const entry = new URL(entryUrl);
    // Electron represents local file origins as file://. A different file URL
    // is not enough to identify this app, so only the bare origin is accepted.
    if (entry.protocol === 'file:') return origin === 'file://' || origin === 'file:///';
    return origin === entry.origin;
  } catch {
    return false;
  }
}

function createPermissionPolicy({ entryUrl, getWebContents } = {}) {
  if (!validEntryUrl(entryUrl) || typeof getWebContents !== 'function') {
    throw new TypeError('A trusted entry URL and window accessor are required.');
  }

  function trustedWindow(webContents) {
    try {
      const trusted = getWebContents();
      return Boolean(
        trusted && webContents
        && Number.isSafeInteger(trusted.id) && trusted.id > 0
        && webContents.id === trusted.id
        && typeof trusted.getURL === 'function' && trusted.getURL() === entryUrl
        && typeof webContents.getURL === 'function' && webContents.getURL() === entryUrl
        && !(typeof trusted.isDestroyed === 'function' && trusted.isDestroyed())
        && !(typeof webContents.isDestroyed === 'function' && webContents.isDestroyed()),
      );
    } catch {
      return false;
    }
  }

  function trustedDetails(details) {
    if (!details || typeof details !== 'object') return false;
    if ('isMainFrame' in details && (!own(details, 'isMainFrame') || details.isMainFrame !== true)) return false;
    if ('requestingUrl' in details && (!own(details, 'requestingUrl') || details.requestingUrl !== entryUrl)) return false;
    if ('securityOrigin' in details && (!own(details, 'securityOrigin') || !trustedOrigin(details.securityOrigin, entryUrl))) return false;
    return true;
  }

  function requestHandler(webContents, permission, callback, details) {
    let allowed = false;
    try {
      if (permission === 'media' && trustedWindow(webContents) && trustedDetails(details)
        && own(details, 'mediaTypes') && Array.isArray(details.mediaTypes)
        && details.mediaTypes.length > 0 && details.mediaTypes.length <= 8) {
        allowed = true;
        for (let index = 0; index < details.mediaTypes.length; index += 1) {
          if (!Object.hasOwn(details.mediaTypes, index) || details.mediaTypes[index] !== 'audio') {
            allowed = false;
            break;
          }
        }
      }
    } catch {
      allowed = false;
    }
    callback(allowed);
  }

  function checkHandler(webContents, permission, requestingOrigin, details) {
    try {
      return permission === 'media'
        && trustedWindow(webContents)
        && trustedOrigin(requestingOrigin, entryUrl)
        && trustedDetails(details)
        && own(details, 'mediaType')
        && details.mediaType === 'audio';
    } catch {
      return false;
    }
  }

  return Object.freeze({ requestHandler, checkHandler });
}

function assertTrustedSender(event, { entryUrl, webContentsId } = {}) {
  try {
    if (!validEntryUrl(entryUrl) || !Number.isSafeInteger(webContentsId) || webContentsId <= 0
      || !event || !event.sender || event.sender.id !== webContentsId
      || !event.senderFrame || event.senderFrame.url !== entryUrl
      || (event.senderFrame.parent !== undefined && event.senderFrame.parent !== null)
      || (typeof event.sender.getURL === 'function' && event.sender.getURL() !== entryUrl)
      || (typeof event.sender.isDestroyed === 'function' && event.sender.isDestroyed())) {
      throw new Error('Untrusted sender');
    }
  } catch {
    throw securityError('UNTRUSTED_SENDER', 'This request did not come from the trusted application window.');
  }
}

function validateText(value, { maxLength = 8000, label = 'message' } = {}) {
  if (!Number.isSafeInteger(maxLength) || maxLength < 1 || maxLength > 1_000_000) {
    throw new TypeError('The text limit must be a positive integer no greater than 1000000.');
  }
  const name = typeof label === 'string' && label.trim() ? label.trim().slice(0, 64) : 'message';
  if (typeof value !== 'string' || value.includes('\0')) {
    throw securityError('INVALID_TEXT', `The ${name} must be plain text without null characters.`);
  }
  if (value.length > maxLength) {
    throw securityError('TEXT_TOO_LONG', `The ${name} must be ${maxLength} characters or fewer.`);
  }
  const trimmed = value.trim();
  if (!trimmed) throw securityError('INVALID_TEXT', `The ${name} cannot be empty.`);
  return trimmed;
}

module.exports = { createPermissionPolicy, assertTrustedSender, validateText };
