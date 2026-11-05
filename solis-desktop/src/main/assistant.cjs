'use strict';

const { validateEndpoint, normalizeProvider, PROVIDERS } = require('./settings.cjs');

const SYSTEM_PROMPT = `You are Project Solis, a desktop assistant. Reply in the user's language. When the user writes Spanish, use clear, warm Colombian Spanish without stereotypes. Be honest about what you can verify. You do not have shell access or autonomous tools. Never claim to have run commands, opened apps, changed files, or inspected hardware. Disk checks are handled separately by the app's fixed read-only diagnostics. Destructive disk operations, formatting, wiping, deleting, partition changes, and repairs are disabled. Do not generate tool calls or instructions for destructive disk operations. Return a helpful plain-text answer. Do not request passwords or API keys in chat.`;
const MAX_TEXT_LENGTH = 8000;
const REQUEST_TIMEOUT_MS = 20000;

function spanish(text) {
  return /[¿¡ñáéíóú]|\b(?:hola|buenas|buenos|gracias|puedes|ayuda|disco|unidad|espacio|hora|fecha|computador|computadora|sistema|eliminar|borrar|formatear|ejecuta)\b/i.test(text);
}

function destructiveIntent(text) {
  const action = /\b(?:format(?:ting)?|reformat|wipe|wiping|erase|erasing|delete|deleting|destroy|remove|reset|partition(?:ing)?|repartition|repair|clean|cleaning|formatea(?:r)?|borra(?:r)?|elimina(?:r)?|repara(?:r)?|particiona(?:r)?|limpia(?:r)?)\b/i;
  const storage = /\b(?:disk|disks|drive|drives|volume|volumes|partition|partitions|ssd|hdd|storage|filesystem|file\s*system|files?|folders?|computer|laptop|mac|macintosh|pc|discos?|unidad(?:es)?|volumen|partici[oó]n|particiones|archivos?|carpetas?|almacenamiento|computador|computadora)\b|\/dev\/[a-zA-Z0-9]+|\b[a-z]:[\\/]/i;
  const command = /\b(?:mkfs(?:\.[a-z0-9]+)?|fdisk|sfdisk|cfdisk|parted|wipefs|shred|fsck(?:\.[a-z0-9]+)?|chkdsk|format-volume|clear-disk|initialize-disk|remove-partition|repair-volume)\b|\brm\s+(?:-[a-z]*[rf][a-z]*\s+)|\bdd\s+[^\n]*\b(?:if|of)=|\bdiskutil\s+(?:erase\w*|partition\w*|repair\w*|zero\w*|secureErase)|\bdiskpart\b/i;
  return command.test(text) || (action.test(text) && storage.test(text)) || /^\s*(?:wipe|erase|delete)\s+(?:everything|all)\b/i.test(text);
}

function shellIntent(text) {
  return /\b(?:run|execute|launch|issue|enter|ejecuta|ejecutar)\b[\s\S]{0,100}\b(?:command|shell|terminal|bash|zsh|powershell|cmd|comando)\b/i.test(text) ||
    /\b(?:run|execute|ejecuta)\s+(?:sudo\s+)?(?:ls|pwd|cat|curl|wget|python\w*|node|osascript|open|chmod|chown|touch|mkdir|cp|mv|rm|diskutil|df|du|echo|say)\b/i.test(text) ||
    /^\s*(?:sudo\s+|\$\s*|(?:bash|zsh|sh|powershell|cmd(?:\.exe)?)\s+[-/])/i.test(text);
}

function diskIntent(text) {
  if (/\b(?:free|available|remaining|used)\s+(?:disk\s+)?space\b|\bespacio\s+(?:libre|disponible|usado)\b|\bSMART\s+(?:health|status|check)\b/i.test(text)) return true;
  const storage = /\b(?:disk|disks|drive|drives|storage|ssd|hdd|discos?|unidades?|almacenamiento)\b/i.test(text);
  const check = /\b(?:check|show|scan|inspect|diagnostic|diagnostics|health|healthy|capacity|free|space|usage|status|available|remaining|full|read-only|consulta|revisa|diagn[oó]stico|salud|sano|capacidad|libre|espacio|estado|disponible|lleno)\b/i.test(text);
  return storage && (check || /^\s*(?:disk|disks|drive|drives|storage|disco|almacenamiento)[?!.\s]*$/i.test(text));
}

function sanitizeHistory(history) {
  if (!Array.isArray(history)) return [];
  return history.filter(item => item && item.mode !== 'local' && !item.diagnostics && ['user', 'assistant'].includes(item.role) && typeof item.content === 'string' && item.content.trim())
    .slice(-20)
    .map(item => ({ role: item.role, content: item.content.slice(0, MAX_TEXT_LENGTH) }));
}

function formatBytes(value, es) {
  if (!Number.isFinite(value) || value < 0) return null;
  const units = ['B', 'KiB', 'MiB', 'GiB', 'TiB', 'PiB'];
  let amount = value;
  let index = 0;
  while (amount >= 1024 && index < units.length - 1) { amount /= 1024; index += 1; }
  return `${amount.toLocaleString(es ? 'es-CO' : 'en-US', { maximumFractionDigits: index ? 1 : 0 })} ${units[index]}`;
}

function diskSummary(diagnostics, es) {
  const summary = diagnostics?.summary || {};
  const total = Number.isFinite(summary.totalBytes) && summary.totalBytes > 0 ? summary.totalBytes : null;
  const free = Number.isFinite(summary.freeBytes) && summary.freeBytes >= 0 && total !== null && summary.freeBytes <= total ? summary.freeBytes : null;
  const capacity = total !== null && free !== null
    ? (es ? `Hay ${formatBytes(free, true)} libres de ${formatBytes(total, true)} (${((total - free) / total * 100).toFixed(1)} % utilizado).` : `${formatBytes(free, false)} free of ${formatBytes(total, false)} (${((total - free) / total * 100).toFixed(1)}% used).`)
    : (es ? 'No se pudo obtener la capacidad del almacenamiento.' : 'Storage capacity was not available.');
  const health = es
    ? 'Esta consulta es de solo lectura. La salud del disco y el estado SMART no se han evaluado; la capacidad libre no demuestra que un disco esté sano.'
    : 'This check is read-only. Drive health and SMART status have not been assessed; free space does not establish that a drive is healthy.';
  return `${capacity} ${health}`;
}

function modelSettings(value = {}) {
  const provider = normalizeProvider(value.provider || 'local');
  if (provider === 'local') return { provider };
  const endpoint = validateEndpoint(value.endpoint || PROVIDERS[provider].endpoint);
  const model = value.model || PROVIDERS[provider].model;
  if (typeof model !== 'string' || !model.trim() || model.length > 200 || /[\u0000-\u001f\u007f]/.test(model)) throw new Error('Choose a valid model name in Settings.');
  const origin = new URL(endpoint).origin;
  // The store binds credentials to the exact configured origin; a changed origin cannot inherit a key.
  const apiKey = typeof value.apiKey === 'string' && (!value.apiKeyOrigin || value.apiKeyOrigin === origin) ? value.apiKey : '';
  if (/[\r\n]/.test(apiKey) || apiKey.length > 8192) throw new Error('Enter a valid API key in Settings.');
  return { provider, endpoint, model: model.trim(), apiKey, origin };
}

function createAssistant({ getDiagnostics, getSettings = () => ({ provider: 'local' }), getStatus = () => ({ platform: process.platform }), fetch: fetchImpl = globalThis.fetch, now = () => new Date(), timeoutMs = REQUEST_TIMEOUT_MS } = {}) {
  const localTranscript = new Set();
  async function request(settings, route, body) {
    if (typeof fetchImpl !== 'function') throw new Error('network');
    const controller = new AbortController();
    const timer = setTimeout(() => controller.abort(), timeoutMs);
    const headers = { Accept: 'application/json' };
    if (body !== undefined) headers['Content-Type'] = 'application/json';
    if (settings.apiKey) headers.Authorization = `Bearer ${settings.apiKey}`;
    try {
      const response = await fetchImpl(`${settings.endpoint}${route}`, {
        method: body === undefined ? 'GET' : 'POST',
        headers,
        redirect: 'error',
        signal: controller.signal,
        ...(body === undefined ? {} : { body: JSON.stringify(body) }),
      });
      if (!response.ok) {
        const error = new Error('http');
        error.status = response.status;
        throw error;
      }
      const result = await response.json();
      if (!result || typeof result !== 'object') throw new Error('response');
      return result;
    } catch (error) {
      if (controller.signal.aborted || error?.name === 'AbortError') throw new Error('timeout');
      if (error?.message === 'http') throw error;
      throw new Error('network-or-response');
    } finally { clearTimeout(timer); }
  }

  function failure(error, es = false) {
    if (error?.message === 'timeout') return es ? 'El servidor del modelo tardó más de 20 segundos. Revisa la conexión e inténtalo de nuevo.' : 'The model server took longer than 20 seconds. Check the connection and try again.';
    if (error?.status === 401 || error?.status === 403) return es ? 'El servidor rechazó la conexión. Revisa la clave API y los permisos en Ajustes.' : 'The model server refused access. Check the API key and permissions in Settings.';
    if (error?.status === 404) return es ? 'No se encontró el modelo o la ruta del servidor. Revisa la URL y el nombre del modelo en Ajustes.' : 'The model or server route was not found. Check the endpoint and model name in Settings.';
    if (error?.status === 429) return es ? 'El servidor alcanzó un límite de solicitudes o de cuota. Revisa tu cuenta e inténtalo de nuevo más tarde.' : 'The model server reached a rate or usage limit. Check your account and try again later.';
    if (Number.isInteger(error?.status)) return es ? `El servidor respondió con el estado HTTP ${error.status}. Inténtalo de nuevo o revisa Ajustes.` : `The model server returned HTTP ${error.status}. Try again or check Settings.`;
    return es ? 'No pude obtener una respuesta del modelo. Revisa que el servidor esté activo y que la URL y el modelo sean correctos en Ajustes. Puedes usar el modo Local mientras tanto.' : 'I could not get a model response. Check that the server is running and that the endpoint and model are correct in Settings. You can use Local mode in the meantime.';
  }

  const api = {
    async reply({ text, history = [] } = {}) {
      if (typeof text !== 'string' || !text.trim()) throw new Error('Enter a message first.');
      if (text.length > MAX_TEXT_LENGTH) throw new Error('Keep messages to 8,000 characters or fewer.');
      text = text.trim();
      const es = spanish(text);
      if (destructiveIntent(text)) return { mode: 'local', text: es ? 'Las operaciones destructivas están deshabilitadas. No puedo formatear, borrar, particionar ni reparar discos o archivos. Puedo consultar el espacio disponible con un diagnóstico de solo lectura.' : 'Destructive operations are disabled. I cannot format, wipe, delete, partition, or repair disks or files. I can check available storage with a read-only diagnostic.' };
      if (shellIntent(text)) return { mode: 'local', text: es ? 'No ejecuto comandos de terminal ni scripts. Puedo explicar un comando o usar el diagnóstico de disco de solo lectura que incluye la app.' : 'I do not execute terminal commands or scripts. I can explain a command or use the app’s built-in read-only disk diagnostic.' };
      if (diskIntent(text)) {
        try {
          if (typeof getDiagnostics !== 'function') throw new Error('unavailable');
          const diagnostics = await getDiagnostics();
          return { mode: 'local', text: diskSummary(diagnostics, es), diagnostics };
        } catch {
          return { mode: 'local', text: es ? 'No pude consultar el almacenamiento. No se modificó ningún disco. La salud del disco no se ha evaluado; vuelve a intentar desde Diagnóstico.' : 'I could not read storage information. No disks were changed. Drive health has not been assessed; try again from Diagnostics.' };
        }
      }
      if (/\b(?:time|date|day|hora|fecha|d[ií]a)\b/i.test(text) && /\b(?:what|current|today|tell|is|now|hora|fecha|d[ií]a|hoy)\b/i.test(text)) {
        const date = new Date(now());
        if (!Number.isNaN(date.valueOf())) return { mode: 'local', text: es ? `Según el reloj de este computador: ${date.toLocaleString('es-CO', { dateStyle: 'full', timeStyle: 'short' })}.` : `According to this computer’s clock: ${date.toLocaleString('en-US', { dateStyle: 'full', timeStyle: 'short' })}.` };
      }
      if (/\b(?:operating system|platform|system info|computer info|sistema operativo|plataforma|qu[eé] computador|what (?:computer|os))\b/i.test(text)) {
        let status = {};
        try { status = await getStatus() || {}; } catch { /* Use the actual process platform if status is unavailable. */ }
        const platform = { darwin: 'macOS', win32: 'Windows', linux: 'Linux' }[status.platform || process.platform] || 'this operating system';
        return { mode: 'local', text: es ? `Project Solis está ejecutándose en ${platform}. Los diagnósticos de disco son de solo lectura; los comandos destructivos están deshabilitados.` : `Project Solis is running on ${platform}. Disk diagnostics are read-only; destructive commands are disabled.` };
      }
      let settings;
      try { settings = modelSettings(await getSettings()); } catch {
        return { mode: 'local', text: es ? 'Revisa la configuración del proveedor en Ajustes. Los servidores remotos requieren HTTPS; HTTP solo se permite en este computador.' : 'Check the provider configuration in Settings. Remote servers require HTTPS; HTTP is allowed only on this computer’s loopback interface.' };
      }
      if (settings.provider === 'local') {
        const welcome = /^\s*(?:hello|hi|hey|hola|buenas)(?:[!, .]|$)/i.test(text);
        const intro = welcome ? (es ? 'Hola, soy Solis. ' : 'Hello, I’m Solis. ') : '';
        return { mode: 'local', text: es ? `${intro}Estoy en modo Local y funciono sin conexión. Puedo consultar la hora y la fecha, identificar el sistema operativo y mostrar la capacidad del disco de forma segura. Prueba «¿cuánto espacio libre tengo?». Para conversar con un modelo, configura Ollama o un servidor compatible con OpenAI en Ajustes.` : `${intro}I’m in Local mode and work offline. I can tell the time and date, identify the operating system, and safely report disk capacity. Try “How much free space do I have?” For model conversations, configure Ollama or an OpenAI-compatible server in Settings.` };
      }
      const modelHistory = sanitizeHistory(history).filter(message => !localTranscript.has(message.content));
      const messages = [{ role: 'system', content: SYSTEM_PROMPT }, ...modelHistory, { role: 'user', content: text }];
      try {
        const result = await request(settings, settings.provider === 'ollama' ? '/api/chat' : '/chat/completions', { model: settings.model, messages, stream: false });
        const message = settings.provider === 'ollama' ? result.message : result.choices?.[0]?.message;
        const content = message?.content;
        if (typeof content !== 'string' || !content.trim()) {
          return { mode: 'model', text: es ? 'El modelo no devolvió texto. Solis no ejecuta llamadas a herramientas ni comandos. Inténtalo de nuevo con una solicitud de texto.' : 'The model did not return text. Solis does not execute tool calls or commands. Try asking for a text response.' };
        }
        return { mode: 'model', text: content.trim().slice(0, 32000) };
      } catch (error) { return { mode: 'model', text: failure(error, es) }; }
    },
    async testConnection() {
      let settings;
      try { settings = modelSettings(await getSettings()); } catch {
        return { ok: false, mode: 'local', text: 'Check the provider settings. Remote endpoints require HTTPS; HTTP is allowed only on loopback.' };
      }
      if (settings.provider === 'local') return { ok: true, mode: 'local', text: 'Local mode is ready and needs no model server or internet connection.' };
      try {
        const result = await request(settings, settings.provider === 'ollama' ? '/api/tags' : '/models');
        const models = (settings.provider === 'ollama' ? result.models : result.data);
        if (!Array.isArray(models)) return { ok: false, mode: 'model', text: 'The server responded, but its model list was not compatible. Check the provider and endpoint in Settings.' };
        const names = models.map(model => model?.name || model?.id || model?.model).filter(name => typeof name === 'string');
        const installed = names.includes(settings.model) || (settings.provider === 'ollama' && names.includes(`${settings.model}:latest`));
        return { ok: installed, mode: 'model', models: names.slice(0, 100), text: installed ? `Connected. The server lists ${settings.model}. Send a message to verify an actual model reply.` : 'Connected to the server, but the selected model was not listed. Choose an available model in Settings.' };
      } catch (error) { return { ok: false, mode: 'model', text: failure(error) }; }
    },
  };
  return {
    ...api,
    async reply(input) {
      const response = await api.reply(input);
      if (response.mode === 'local') {
        // Keep local diagnostics and other local-only turns out of later remote-model context,
        // including callers that accidentally include every displayed turn in their history.
        for (const text of [input?.text, response.text]) {
          if (typeof text === 'string') localTranscript.add(text.trim().slice(0, MAX_TEXT_LENGTH));
        }
        while (localTranscript.size > 400) localTranscript.delete(localTranscript.values().next().value);
      }
      return response;
    },
  };
}

module.exports = { createAssistant, sanitizeHistory, destructiveIntent, SYSTEM_PROMPT };
