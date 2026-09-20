const fs = require('node:fs');
const path = require('node:path');
class AI {
  constructor(folder, safeStorage, getSettings) { this.folder = folder; this.safeStorage = safeStorage; this.getSettings = getSettings; }
  file(provider) { if (!['openai', 'claude'].includes(provider)) throw new Error('Invalid provider'); return path.join(this.folder, `${provider}.key`); }
  has(provider) { return fs.existsSync(this.file(provider)); }
  async set(provider, key) {
    const file = this.file(provider);
    if (typeof key !== 'string' || key.length > 1000) throw new Error('Invalid key');
    if (!key.trim()) { if (fs.existsSync(file)) fs.unlinkSync(file); return; }
    if (!await this.safeStorage.isAsyncEncryptionAvailable()) throw new Error('Windows credential encryption is unavailable. Key was not saved.');
    const encrypted = await this.safeStorage.encryptStringAsync(key.trim());
    fs.writeFileSync(file + '.tmp', encrypted); fs.renameSync(file + '.tmp', file);
  }
  async complete(system, messages) {
    const settings = this.getSettings(), provider = settings.provider;
    if (!this.has(provider)) throw new Error(`Add a ${provider === 'openai' ? 'OpenAI' : 'Claude'} API key in Settings to use AI features.`);
    const { result: key } = await this.safeStorage.decryptStringAsync(fs.readFileSync(this.file(provider)));
    const isOpenAI = provider === 'openai';
    const response = await fetch(isOpenAI ? 'https://api.openai.com/v1/chat/completions' : 'https://api.anthropic.com/v1/messages', {
      method: 'POST', signal: AbortSignal.timeout(90000),
      headers: { 'Content-Type': 'application/json', ...(isOpenAI ? { Authorization: `Bearer ${key}` } : { 'x-api-key': key, 'anthropic-version': '2023-06-01' }) },
      body: JSON.stringify(isOpenAI ? { model: settings.openaiModel, messages: [{ role: 'system', content: system }, ...messages], max_completion_tokens: 4096 } : { model: settings.claudeModel, system, messages, max_tokens: 4096 })
    });
    if (!response.ok) throw new Error(`${isOpenAI ? 'OpenAI' : 'Claude'} request failed (${response.status}). Check your key, model name, and provider quota.`);
    const body = await response.json();
    const text = isOpenAI ? body.choices?.[0]?.message?.content : body.content?.filter(c => c.type === 'text').map(c => c.text).join('');
    if (!text?.trim()) throw new Error('AI returned no text. Try again.');
    return text.trim();
  }
}
module.exports = { AI };
