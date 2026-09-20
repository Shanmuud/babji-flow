'use strict';
const { randomUUID } = require('node:crypto');
const defaults = () => ({ version: 1, settings: {
  tones: { personal: 'veryCasual', work: 'casual', email: 'formal', other: 'casual' },
  appCategories: { slack: 'work', 'ms-teams': 'work', teams: 'work', outlook: 'email', whatsapp: 'personal', telegram: 'personal', discord: 'personal' },
  provider: 'openai', openaiModel: 'gpt-4.1-mini', claudeModel: 'claude-sonnet-4-6',
  removeFillers: false, aiPolish: false, autoPaste: true, soundCues: true, language: 'english', styleSample: '', showNotch: true, notchPosition: 'top', shortcutMode: 'hold', mouthY: 70, dictationShortcut: 'Control+Shift+Space', fallbackShortcut: 'Control+Alt+Space', onboardingDismissed: false, textSize: 'normal', density: 'comfortable', reducedMotion: false, idleHideMinutes: 3, microphoneId: '', appearance: 'system', setupStep: 0, setupVersion: 0
}, dictionary: [], snippets: [], records: [], meetings: [], lastResult: '', lastRaw: '' });
const escapeRE = s => s.replace(/[.*+?^${}()|[\]\\]/g, '\\$&');
function phraseReplace(text, phrase, replacement, punctuation = false) {
  const pattern = escapeRE(phrase).replace(/ +/g, '[\\s,]+');
  return text.replace(new RegExp(`(^|[^\\p{L}\\p{N}_])${pattern}(?=$|[^\\p{L}\\p{N}_])${punctuation ? '[.,]?' : ''}`, 'giu'), (_, before) => before + replacement);
}
function capitalise(text) { return text.replace(/(^[- ]*|[.!?]\s+|\n[- ]*)(\p{L})/gu, (_, before, ch) => before + ch.toUpperCase()); }
function clean(raw, {removeFillers=true}={}) {
  let text = ` ${raw.trim()} `;
  if(removeFillers)text = text.replace(/\b(?:um+|uh+|uhm|hmm?|mhm|erm?|aah|eh)[,.]?(?=\s|$)/gi, '')
    .replace(/,?\s+you know,\s+/gi, ' ')

    .replace(/\b(\w+)(?:\s+\1\b)+/gi, '$1');
  text=text.replace(/[^.!?\n]*?\b(?:scratch that|strike that|delete that)[,.]?\s*/gi,' ');
  if (/\bfirst(?:ly| of all)?\b/i.test(text) && /\bsecond(?:ly)?\b/i.test(text) || /\b(?:number|point) (?:one|1)\b/i.test(text) && /\b(?:number|point) (?:two|2)\b/i.test(text)) {
    text = text.replace(/[,.;:]?\s*\b(?:firstly|first of all|first|secondly|second|thirdly|third|fourth|fifth|sixth|lastly|finally|(?:number|point) (?:one|two|three|four|five|six|\d))\b[,.:]?\s*/gi, '\n- ');
  }
  for (const [pattern, value] of [
    ['(?:new|next) paragraph', '\n\n'], ['(?:new|next) line', '\n'],
    ['bullet point|next bullet|next point', '\n- '], ['question mark', '?'],
    ['exclamation (?:mark|point)', '!'], ['full stop', '.'],
    ['open (?:paren|parenthesis|bracket)', ' ('], ['close (?:paren|parenthesis|bracket)', ')'],
    ['smiley face', ' :)'], ['thumbs up emoji', ' 👍'], ['at sign', '@']
  ]) text = text.replace(new RegExp(`[, .]?\\s*\\b(?:${pattern})\\b[,.]?`, 'gi'), value);
  text = text.replace(/\b(\d+(?:\.\d+)?)\s*(thousand|million|billion|lakh|crore)\b/gi, (_, n, scale) => (Number(n) * { thousand: 1e3, million: 1e6, billion: 1e9, lakh: 1e5, crore: 1e7 }[scale.toLowerCase()]).toLocaleString('en-US'));
  text = text.replace(/[ \t]+/g, ' ').replace(/ ([,.!?;:])/g, '$1').replace(/([,.!?;:])\1+/g, '$1')
    .replace(/,\s*\./g, '.').replace(/ *\n */g, '\n').replace(/\n{3,}/g, '\n\n').replace(/\bi\b/g, 'I').trim().replace(/^[,.;:\s]+/, '');
  return capitalise(text);
}
function dictionaryApply(text, entries) {
  for (const entry of entries) for (const variant of [...entry.misheard, entry.word]) if (variant) text = phraseReplace(text, variant, entry.word);
  return text;
}
function cleanup(raw, state, category = 'other') {
  let text = dictionaryApply(clean(dictionaryApply(raw, state.dictionary),{removeFillers:state.settings.removeFillers===true}), state.dictionary);
  const tone = state.settings.tones[category] || 'casual';
  if (tone === 'veryCasual') text = text.toLowerCase();
  if (tone !== 'formal') text = text.replace(/\.$/, '');
  else if (text && !/[.!?]$/.test(text) && !text.includes('\n')) text += '.';
  text = dictionaryApply(text, state.dictionary);
  // Expand after tone changes so URLs, case-sensitive passwords and signatures stay literal.
  for (const snippet of [...state.snippets].sort((a, b) => b.trigger.length - a.trigger.length)) text = phraseReplace(text, snippet.trigger, snippet.expansion, true);
  return text;
}
function statistics(records, now = new Date()) {
  const day = d => { const x = new Date(d); return `${x.getFullYear()}-${x.getMonth()}-${x.getDate()}`; };
  const words = records.reduce((n, r) => n + r.words, 0), seconds = records.reduce((n, r) => n + r.seconds, 0);
  const dates = new Set(records.map(r => day(r.date))); let streak = 0, cursor = new Date(now);
  if (!dates.has(day(cursor))) cursor.setDate(cursor.getDate() - 1);
  while (dates.has(day(cursor))) { streak++; cursor.setDate(cursor.getDate() - 1); }
  const apps = {};
  for (const r of records) apps[r.app] = (apps[r.app] || 0) + r.words;
  return { words, wpm: seconds ? Math.round(words * 60 / seconds) : 0, saved: Math.max(0, Math.round(words / 40 - seconds / 60)), streak,
    apps: Object.entries(apps).sort((a, b) => b[1] - a[1]).slice(0, 5),
    daily: Array.from({ length: 30 }, (_, i) => { const d = new Date(now); d.setDate(d.getDate() - 29 + i); return { date: d.toISOString(), words: records.filter(r => day(r.date) === day(d)).reduce((n, r) => n + r.words, 0) }; }) };
}
function string(value, name, max = 20000) { if (typeof value !== 'string' || value.length > max) throw new Error(`Invalid ${name}`); return value.trim(); }
function validateSettings(value, current) {
  const out = structuredClone(current);
  for (const key of ['removeFillers', 'aiPolish', 'autoPaste', 'soundCues', 'showNotch', 'onboardingDismissed']) if (key in value) { if (typeof value[key] !== 'boolean') throw new Error(`Invalid ${key}`); out[key] = value[key]; }
  if ('shortcutMode' in value) { if (!['hold','toggle'].includes(value.shortcutMode)) throw new Error('Invalid shortcut mode'); out.shortcutMode=value.shortcutMode; }
  for(const [key,allowed] of Object.entries({textSize:['normal','large'],density:['compact','comfortable']}))if(key in value){if(!allowed.includes(value[key]))throw new Error('Invalid '+key);out[key]=value[key];}
  if('reducedMotion' in value){if(typeof value.reducedMotion!=='boolean')throw new Error('Invalid motion setting');out.reducedMotion=value.reducedMotion;}
  if('idleHideMinutes' in value){if(!Number.isInteger(value.idleHideMinutes)||value.idleHideMinutes<0||value.idleHideMinutes>120)throw new Error('Choose 0 to 120 minutes');out.idleHideMinutes=value.idleHideMinutes;}
  if ('microphoneId' in value) out.microphoneId=string(value.microphoneId,'microphone',500);
  if ('appearance' in value) { if (!['light','dark','system'].includes(value.appearance)) throw new Error('Invalid appearance'); out.appearance=value.appearance; }
  if ('scene' in value) { if (!['forest','sea','desert'].includes(value.scene)) throw new Error('Invalid scene'); out.scene=value.scene; }
  for (const key of ['setupStep','setupVersion']) if (key in value) { if (!Number.isInteger(value[key]) || value[key]<0 || value[key]>3) throw new Error('Invalid setup progress'); out[key]=value[key]; }
  if ('mouthY' in value) { if (!Number.isFinite(value.mouthY) || value.mouthY<40 || value.mouthY>85) throw new Error('Invalid mouth position'); out.mouthY=value.mouthY; }
  if ('notchPosition' in value) { if (!['top', 'bottom'].includes(value.notchPosition)) throw new Error('Invalid notch position'); out.notchPosition = value.notchPosition; }
  if ('provider' in value) { if (!['openai', 'claude'].includes(value.provider)) throw new Error('Invalid provider'); out.provider = value.provider; }
  for (const key of ['openaiModel', 'claudeModel', 'styleSample']) if (key in value) out[key] = string(value[key], key, key === 'styleSample' ? 5000 : 100);
  if ('language' in value) { if (!['english', 'hindi', 'telugu', 'auto'].includes(value.language)) throw new Error('Invalid language'); out.language = value.language; }
  if (value.tones) for (const [category, tone] of Object.entries(value.tones)) { if (!Object.hasOwn(out.tones, category) || !['formal', 'casual', 'veryCasual'].includes(tone)) throw new Error('Invalid tone'); out.tones[category] = tone; }
  if (value.appCategories) { out.appCategories = {}; for (const [name, category] of Object.entries(value.appCategories)) { if (!/^[\w.-]{1,80}$/.test(name) || !Object.hasOwn(out.tones, category)) throw new Error('Invalid app category'); out.appCategories[name.toLowerCase()] = category; } }
  return out;
}
function wav(samples) {
  const buffer = Buffer.alloc(44 + samples.length * 2);
  buffer.write('RIFF'); buffer.writeUInt32LE(buffer.length - 8, 4); buffer.write('WAVEfmt ', 8); buffer.writeUInt32LE(16, 16); buffer.writeUInt16LE(1, 20); buffer.writeUInt16LE(1, 22); buffer.writeUInt32LE(16000, 24); buffer.writeUInt32LE(32000, 28); buffer.writeUInt16LE(2, 32); buffer.writeUInt16LE(16, 34); buffer.write('data', 36); buffer.writeUInt32LE(samples.length * 2, 40);
  samples.forEach((v, i) => buffer.writeInt16LE(Math.round(Math.max(-1, Math.min(1, v)) * 32767), 44 + i * 2)); return buffer;
}
function learnCorrection(state, heardValue, wordValue) {
 const heard=string(heardValue,"misheard phrase",100),word=string(wordValue,"correct spelling",100);
 if(!heard||!word||heard===word)throw new Error("Enter the misheard phrase and a different correct spelling.");
 const entry=state.dictionary.find(e=>e.word.toLowerCase()===word.toLowerCase());
 if(entry){entry.word=word;if(!entry.misheard.some(v=>v.toLowerCase()===heard.toLowerCase()))entry.misheard.push(heard);}
 else state.dictionary.unshift({id:randomUUID(),word,misheard:[heard],source:"correction"});
}
function preservesFillers(before,after){const tokens=s=>s.toLowerCase().match(/\b(?:um+|uh+|uhm|hmm+|hm|mhm|erm?|aah|eh|you know)\b/g)||[];const a=tokens(before),b=tokens(after);return a.every(word=>b.filter(x=>x===word).length>=a.filter(x=>x===word).length);}
module.exports = { preservesFillers, learnCorrection, defaults, clean, cleanup, dictionaryApply, statistics, validateSettings, string, wav, randomUUID };
