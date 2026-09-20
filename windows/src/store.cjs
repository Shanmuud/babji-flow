const fs = require('node:fs');
const path = require('node:path');
const { defaults } = require('./core.cjs');
class Store {
  constructor(folder) {
    this.folder = folder; this.file = path.join(folder, 'state.json'); fs.mkdirSync(folder, { recursive: true });
    const base = defaults();
    if (fs.existsSync(this.file)) {
      // Never overwrite unreadable user data with a fresh state.
      const saved = JSON.parse(fs.readFileSync(this.file, 'utf8'));
      for (const key of ['dictionary', 'snippets', 'records', 'meetings']) if (!Array.isArray(saved[key])) throw new Error(`Damaged data file: ${key}`);
      this.state = { ...base, ...saved, settings: { ...base.settings, ...saved.settings, tones: { ...base.settings.tones, ...saved.settings.tones } } };
    } else this.state = base;
    if (!this.state.settings.compactFaceVersion) { this.state.settings.notchPosition = 'top'; this.state.settings.compactFaceVersion = 1; }
  }
  save() { const temporary = this.file + '.tmp'; fs.writeFileSync(temporary, JSON.stringify(this.state, null, 2)); fs.renameSync(temporary, this.file); }
}
module.exports = { Store };
