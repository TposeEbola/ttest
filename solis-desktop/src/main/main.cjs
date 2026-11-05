'use strict';

const { app, BrowserWindow, ipcMain, session, systemPreferences, safeStorage, Menu } = require('electron');
const path = require('node:path');
const os = require('node:os');
const { pathToFileURL } = require('node:url');
const { getDiskDiagnostics, DESTRUCTIVE_ACTIONS_DISABLED } = require('./diagnostics.cjs');
const { createVoiceService } = require('./voice.cjs');
const { createAssistant } = require('./assistant.cjs');
const { createSettingsStore } = require('./settings.cjs');
const { createPermissionPolicy, assertTrustedSender, validateText } = require('./security.cjs');

app.setName('Project Solis');
if (!app.isPackaged && process.env.SOLIS_USER_DATA_DIR) {
  if (!path.isAbsolute(process.env.SOLIS_USER_DATA_DIR)) throw new Error('SOLIS_USER_DATA_DIR must be absolute.');
  app.setPath('userData', process.env.SOLIS_USER_DATA_DIR);
}
const entryPath = path.join(__dirname, '..', 'renderer', 'index.html');
const entryUrl = pathToFileURL(entryPath).href;
let window;
let voice;
let settings;
let assistant;

function preferences() {
  const config = settings.load();
  return { locale: config.voiceLocale, gender: config.voiceGender, voiceId: config.voiceId };
}

function microphoneStatus() {
  if (process.platform === 'darwin') {
    return { status: systemPreferences.getMediaAccessStatus('microphone'), requestedOnClickOnly: true };
  }
  return { status: 'unknown', requestedOnClickOnly: true };
}

async function status() {
  return {
    appName: app.getName(), version: app.getVersion(), platform: process.platform,
    osLabel: `${process.platform === 'darwin' ? 'macOS' : process.platform === 'win32' ? 'Windows' : 'Linux'} · ${os.arch()}`,
    microphone: microphoneStatus(), voice: await voice.getStatus(preferences()),
    safety: { readOnly: true, destructiveCommandsEnabled: !DESTRUCTIVE_ACTIONS_DISABLED },
  };
}

function handle(channel, action) {
  ipcMain.handle(channel, async (event, ...args) => {
    assertTrustedSender(event, { entryUrl, webContentsId: window?.webContents.id });
    try { return await action(...args); }
    catch (error) { throw new Error(String(error?.message || 'The request could not be completed.').slice(0, 1500)); }
  });
}

function registerIPC() {
  handle('solis:status', status);
  handle('solis:message', async (message) => {
    if (!message || typeof message !== 'object' || Array.isArray(message)) throw new Error('Enter a message.');
    const text = validateText(message.text, { maxLength: 8000, label: 'message' });
    return assistant.reply({ text, history: message.history });
  });
  handle('solis:diagnostics', () => getDiskDiagnostics());
  handle('solis:settings', () => settings.load());
  handle('solis:save-settings', (value) => settings.save(value));
  handle('solis:test-connection', async () => {
    const result = await assistant.testConnection();
    return { ...result, message: result.text };
  });
  handle('solis:microphone', async () => {
    if (process.platform !== 'darwin') return { status: 'unknown', granted: null, message: 'Your browser or operating system will request access when capture begins.' };
    let access = systemPreferences.getMediaAccessStatus('microphone');
    if (access === 'not-determined') {
      await systemPreferences.askForMediaAccess('microphone');
      access = systemPreferences.getMediaAccessStatus('microphone');
    }
    return { status: access, granted: access === 'granted' };
  });
  handle('solis:listen', async () => ({ text: await voice.transcribeNative() }));
  handle('solis:stop-listening', () => { voice.stopNativeRecognition(); return { ok: true }; });
  handle('solis:speak', async (value) => {
    const text = validateText(value, { maxLength: 4000, label: 'voice reply' });
    const result = await voice.speak(text, preferences());
    return { ...result, ok: result.spoken === true };
  });
  handle('solis:stop-speaking', () => { voice.stopSpeaking(); return { ok: true }; });
}

function makeWindow() {
  window = new BrowserWindow({
    title: 'Project Solis', width: 1280, height: 880, minWidth: 960, minHeight: 680,
    backgroundColor: '#111210', show: false,
    icon: path.join(app.getAppPath(), 'assets', 'logo.png'),
    webPreferences: {
      preload: path.join(__dirname, 'preload.cjs'),
      nodeIntegration: false, contextIsolation: true, sandbox: true,
      webSecurity: true, allowRunningInsecureContent: false, webviewTag: false,
    },
  });
  window.webContents.setWindowOpenHandler(() => ({ action: 'deny' }));
  window.webContents.on('will-navigate', (event, url) => { if (url !== entryUrl) event.preventDefault(); });
  window.webContents.on('will-attach-webview', event => event.preventDefault());
  window.on('ready-to-show', () => window.show());
  window.on('closed', () => { voice.stopSpeaking(); voice.stopNativeRecognition(); window = undefined; });
  void window.loadFile(entryPath);
}

app.whenReady().then(() => {
  // Chromium's basic_text backend does not provide encrypted credential storage.
  const secureStorage = {
    isEncryptionAvailable: () => safeStorage.isEncryptionAvailable() && safeStorage.getSelectedStorageBackend?.() !== 'basic_text',
    encryptString: value => safeStorage.encryptString(value),
    decryptString: value => safeStorage.decryptString(value),
  };
  settings = createSettingsStore({ filePath: path.join(app.getPath('userData'), 'preferences.json'), safeStorage: secureStorage });
  voice = createVoiceService({ appPath: app.getAppPath(), ...(app.isPackaged ? { resourcesPath: process.resourcesPath } : {}) });
  assistant = createAssistant({ getDiagnostics: getDiskDiagnostics, getSettings: () => settings.getForRequest(), getStatus: status });
  const policy = createPermissionPolicy({ entryUrl, getWebContents: () => window?.webContents });
  session.defaultSession.setPermissionRequestHandler(policy.requestHandler);
  session.defaultSession.setPermissionCheckHandler(policy.checkHandler);
  session.defaultSession.setDisplayMediaRequestHandler((_request, callback) => callback({}));
  Menu.setApplicationMenu(Menu.buildFromTemplate([
    ...(process.platform === 'darwin' ? [{ role: 'appMenu' }] : []),
    { role: 'editMenu' }, { role: 'viewMenu' }, { role: 'windowMenu' },
  ]));
  registerIPC();
  makeWindow();
  app.on('activate', () => { if (BrowserWindow.getAllWindows().length === 0) makeWindow(); });
}).catch(error => { console.error(`Solis could not start: ${error.message}`); app.quit(); });

app.on('window-all-closed', () => { if (process.platform !== 'darwin') app.quit(); });
app.on('before-quit', () => { voice?.stopSpeaking(); voice?.stopNativeRecognition(); });
