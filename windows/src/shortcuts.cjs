const { parse } = require('./keybinding.js');
class ShortcutManager {
  constructor(native, trigger) { this.native = native; this.trigger = trigger; this.bindings = []; this.paused = false; }
  register(binding) { return this.native.register(binding.accelerator, () => this.trigger(binding.label, binding.virtualKey)); }
  initialize(primary, fallback) {
    this.bindings = [parse(primary), ...(fallback ? [parse(fallback)] : [])];
    for (const binding of this.bindings) this.register(binding);
  }
  apply(primary, fallback) {
    const next = [parse(primary), ...(fallback ? [parse(fallback)] : [])];
    if (new Set(next.map(b => b.accelerator)).size !== next.length) throw new Error('Primary and backup shortcuts must be different.');
    if (this.paused) throw new Error('Finish recording your shortcut before saving.');
    const added = [];
    try {
      for (const binding of next) {
        if (this.bindings.some(b => b.accelerator === binding.accelerator) && this.native.isRegistered(binding.accelerator)) continue;
        if (!this.register(binding)) throw new Error(`${binding.label} is unavailable. Another app or Windows may be using it. Your previous shortcuts are unchanged.`);
        added.push(binding);
      }
    } catch (error) { for (const b of added) this.native.unregister(b.accelerator); throw error; }
    for (const b of this.bindings) if (!next.some(n => n.accelerator === b.accelerator)) this.native.unregister(b.accelerator);
    this.bindings = next;
    return next;
  }
  suspend() { this.paused = true; for (const b of this.bindings) this.native.unregister(b.accelerator); }
  resume() { if (!this.paused) return; this.paused = false; for (const b of this.bindings) this.register(b); }
}
module.exports = { ShortcutManager };
