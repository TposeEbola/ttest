'use strict';

const test = require('node:test');
const assert = require('node:assert/strict');
const { readFileSync } = require('node:fs');
const { createRequire } = require('node:module');
const path = require('node:path');
const { pathToFileURL } = require('node:url');
const vm = require('node:vm');

test('the actual native-listening IPC handler returns the transcript shape consumed by the renderer', async () => {
  const mainPath = path.resolve(__dirname, '../src/main/main.cjs');
  const entryUrl = pathToFileURL(path.resolve(__dirname, '../src/renderer/index.html')).href;
  const requireFromMain = createRequire(mainPath);
  const handlers = new Map();
  let transcriptions = 0;
  const electron = {
    app: {
      setName: () => {},
      isPackaged: false,
      on: () => {},
      // Register the real handlers below without launching an Electron window in this unit test.
      whenReady: () => new Promise(() => {}),
    },
    ipcMain: { handle: (channel, callback) => handlers.set(channel, callback) },
  };
  const context = vm.createContext({
    __dirname: path.dirname(mainPath),
    process: { env: {}, platform: 'darwin' },
    console,
    require: (name) => name === 'electron' ? electron : requireFromMain(name),
    injectedVoice: {
      transcribeNative: async () => { transcriptions += 1; return 'What time is it?'; },
    },
  });
  vm.runInContext(readFileSync(mainPath, 'utf8'), context, { filename: mainPath });
  vm.runInContext('voice = injectedVoice; window = { webContents: { id: 99 } }; registerIPC();', context);

  const listen = handlers.get('solis:listen');
  assert.equal(typeof listen, 'function');
  const trustedEvent = { sender: { id: 99, getURL: () => entryUrl }, senderFrame: { url: entryUrl, parent: null } };
  const result = await listen(trustedEvent);
  assert.deepEqual(Object.keys(result), ['text']);
  assert.equal(result.text, 'What time is it?');
  assert.equal(transcriptions, 1);
  await assert.rejects(listen({ ...trustedEvent, sender: { id: 100 } }), { code: 'UNTRUSTED_SENDER' });
  assert.equal(transcriptions, 1, 'untrusted IPC cannot start a recording');
});
