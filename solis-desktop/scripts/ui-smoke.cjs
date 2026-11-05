'use strict';

const { _electron } = require('playwright');
const assert = require('node:assert/strict');
const fs = require('node:fs');
const os = require('node:os');
const path = require('node:path');
const http = require('node:http');

async function main() {
  const root = path.resolve(__dirname, '..');
  const profile = fs.mkdtempSync(path.join(os.tmpdir(), 'solis-ui-'));
  const artifacts = path.join(root, 'test-results');
  fs.mkdirSync(artifacts, { recursive: true });
  const requests = [];
  const server = http.createServer((request, response) => {
    let body = '';
    request.on('data', chunk => { body += chunk; });
    request.on('end', () => {
      if (request.method === 'POST') requests.push(JSON.parse(body));
      response.setHeader('Content-Type', 'application/json');
      response.end(JSON.stringify(request.url === '/api/tags'
        ? { models: [{ name: 'solis-test-model' }] }
        : { message: { content: 'Model connection verified. <img src=x onerror="window.injected=true">' } }));
    });
  });
  await new Promise(resolve => server.listen(0, '127.0.0.1', resolve));
  const endpoint = `http://127.0.0.1:${server.address().port}`;
  const args = [root, '--disable-gpu', '--disable-dev-shm-usage'];
  const virtualMedia = process.platform === 'linux';
  if (virtualMedia) args.push('--use-fake-device-for-media-stream');
  // Only this explicit test flag permits the container workaround. Normal app
  // startup and packaged applications never add --no-sandbox.
  if (process.env.SOLIS_TEST_NO_SANDBOX === '1') {
    if (process.platform !== 'linux') throw new Error('The test-only sandbox override is Linux-only.');
    args.push('--no-sandbox');
  }
  let application;
  try {
    application = await _electron.launch({ args, env: { ...process.env, SOLIS_USER_DATA_DIR: profile }, timeout: 30000 });
    const page = await application.firstWindow();
    const errors = [];
    page.on('pageerror', error => errors.push(error.message));
    await page.waitForFunction(() => window.solis && !document.querySelector('#status-copy').textContent.includes('Connecting'));
    await page.waitForFunction(() => [...document.images].some(image => image.complete && image.naturalWidth > 0));
    const status = await page.evaluate(() => window.solis.getStatus());
    assert.equal(status.appName, 'Project Solis');
    assert.equal(status.platform, process.platform);
    assert.equal(status.safety.readOnly, true);
    assert.equal(status.safety.destructiveCommandsEnabled, false);
    assert.equal(await page.evaluate(() => typeof window.require), 'undefined');
    assert.equal(await page.evaluate(() => typeof window.solis.runCommand), 'undefined');
    const protection = await application.evaluate(({ BrowserWindow }) => {
      const prefs = BrowserWindow.getAllWindows()[0].webContents.getLastWebPreferences();
      return { sandbox: prefs.sandbox, isolation: prefs.contextIsolation, node: prefs.nodeIntegration };
    });
    assert.deepEqual(protection, { sandbox: true, isolation: true, node: false });
    await page.screenshot({ path: path.join(artifacts, 'solis-desktop.png') });

    await page.evaluate(() => window.solis.saveSettings({ voiceReplies: false }));
    await page.reload();
    await page.waitForFunction(() => !document.querySelector('#status-copy').textContent.includes('Connecting'));
    await page.getByTestId('chat-input').fill('Hello Solis');
    await page.getByTestId('send').click();
    await page.waitForFunction(() => document.querySelector('#conversation').textContent.includes('Local mode'));
    const denied = await page.evaluate(() => window.solis.sendMessage({ text: 'format my disk', history: [] }));
    assert.match(denied.text, /disabled|cannot|won.t|refuse/i);
    assert.equal(denied.mode, 'local');

    await page.getByTestId('diagnostics').click();
    await page.locator('#run-diagnostics').click();
    await page.waitForFunction(() => document.querySelector('#diagnostics-status').textContent.includes('complete'));
    const report = await page.evaluate(() => window.solis.getDiagnostics());
    assert.equal(report.readOnly, true);
    assert.equal(report.health, 'not-assessed');
    assert.ok(report.summary.totalBytes > 0);
    await page.screenshot({ path: path.join(artifacts, 'solis-diagnostics.png') });

    if (virtualMedia) {
      const audio = await page.evaluate(async () => {
        const stream = await navigator.mediaDevices.getUserMedia({ audio: true });
        const count = stream.getAudioTracks().length;
        stream.getTracks().forEach(track => track.stop());
        return count;
      });
      assert.equal(audio, 1, 'Trusted renderer can request the virtual microphone');
      const cameraDenied = await page.evaluate(async () => {
        try { const stream = await navigator.mediaDevices.getUserMedia({ video: true }); stream.getTracks().forEach(track => track.stop()); return false; }
        catch { return true; }
      });
      assert.equal(cameraDenied, true, 'Camera permission is denied');
    }

    await page.evaluate(endpoint => window.solis.saveSettings({ provider: 'ollama', endpoint, model: 'solis-test-model' }), endpoint);
    const connection = await page.evaluate(() => window.solis.testConnection());
    assert.equal(connection.ok, true);
    await page.reload();
    await page.waitForFunction(() => !document.querySelector('#status-copy').textContent.includes('Connecting'));
    await page.getByTestId('chat-input').fill('Say hello from the model');
    await page.getByTestId('send').click();
    await page.waitForFunction(() => document.querySelector('#conversation').textContent.includes('Model connection verified'));
    assert.equal(await page.evaluate(() => window.injected === true), false);
    assert.equal(await page.locator('#conversation img').count(), 0);
    assert.equal(requests.length, 1);
    assert.equal(requests[0].model, 'solis-test-model');
    assert.ok(!JSON.stringify(requests).includes(report.generatedAt), 'Disk report is not silently sent to a model');
    assert.deepEqual(errors, []);
    await page.screenshot({ path: path.join(artifacts, 'solis-model-chat.png') });
    console.log(JSON.stringify({ desktop: 'passed', diagnostics: 'read-only live host check passed',
      microphone: virtualMedia ? 'virtual device and permission policy passed; physical Mac unverified' : 'manual Mac hardware check pending',
      model: 'local mock API integration passed; live LLM not configured', voice: status.voice.ttsAvailable ? 'installed backend detected; audible hardware check pending' : 'unavailable on test host; truthful fallback verified',
      sandboxTestOverride: process.env.SOLIS_TEST_NO_SANDBOX === '1', screenshots: artifacts }, null, 2));
  } finally {
    if (application) await application.close();
    await new Promise(resolve => server.close(resolve));
  }
}
main().catch(error => { console.error(error); process.exitCode = 1; });
