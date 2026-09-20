const { test } = require('node:test');
const assert = require('node:assert/strict');
const fs = require('node:fs');
const os = require('node:os');
const path = require('node:path');
const { defaults, clean, cleanup, statistics, validateSettings, wav } = require('../src/core.cjs');
const { Store } = require('../src/store.cjs');
test('fillers, stutters, spoken paragraphs and corrections', () => {
  assert.equal(clean('um hello hello new paragraph see you tomorrow question mark'), 'Hello\n\nSee you tomorrow?');
  assert.equal(clean('Send this Friday scratch that send it Monday'), 'Send it Monday');
  assert.equal(clean('first send the draft second review it third ship it'), '- Send the draft\n- Review it\n- Ship it');
});
test('literal dictionary replacements preserve special characters and word boundaries', () => {
  const s = defaults(); s.dictionary = [{ word: 'Rishi $&', misheard: ['rishy'] }];
  assert.equal(cleanup('rishy met parishy', s), 'Rishi $& met parishy');
  s.dictionary = [{ word: 'C++', misheard: ['see plus plus'] }];
  assert.equal(cleanup('see plus plus', s), 'C++');
});
test('snippet values remain literal, longest triggers first, and preserve case', () => {
  const s = defaults(); s.snippets = [{ trigger: 'my email', expansion: 'Rishi+Work@example.com' }, { trigger: 'my', expansion: 'WRONG' }];
  assert.equal(cleanup('my email.', s, 'personal'), 'Rishi+Work@example.com');
});
test('tone and scale formatting', () => {
  const s = defaults(); assert.equal(cleanup('hello there', s, 'email'), 'Hello there.');
  assert.equal(cleanup('Hello there.', s, 'personal'), 'hello there');
  assert.equal(clean('19 thousand and 2.5 million'), '19,000 and 2,500,000');
});
test('stats compute real totals, time savings and yesterday-continuing streak', () => {
  const now = new Date(2026, 8, 20, 12); const records = [19,18].map(day => ({ date: new Date(2026,8,day,12).toISOString(), words: 100, seconds: 30, app: 'Notepad' }));
  const stats = statistics(records,now); assert.equal(stats.words,200); assert.equal(stats.wpm,200); assert.equal(stats.saved,4); assert.equal(stats.streak,2); assert.equal(stats.daily.length,30);
});
test('settings reject unknown values and prototype keys', () => {
  const s = defaults().settings;
  assert.throws(()=>validateSettings({provider:'attacker'},s)); assert.throws(()=>validateSettings({autoPaste:'yes'},s));
  assert.throws(()=>validateSettings({tones:JSON.parse('{"__proto__":"formal"}')},s));
  assert.equal(validateSettings({tones:{work:'formal'}},s).tones.work,'formal'); assert.equal(s.tones.work,'casual');
});
test('store survives reopening and refuses corrupt JSON', () => {
  const folder = fs.mkdtempSync(path.join(os.tmpdir(),'babji-test-'));
  try { const s=new Store(folder);s.state.dictionary.push({word:'Babji',misheard:[]});s.save();assert.equal(new Store(folder).state.dictionary[0].word,'Babji');fs.writeFileSync(s.file,'bad');assert.throws(()=>new Store(folder));assert.equal(fs.readFileSync(s.file,'utf8'),'bad'); }
  finally { fs.rmSync(folder,{recursive:true,force:true}); }
});
test('WAV header and clipping encode signed mono 16kHz PCM',()=>{const b=wav(new Float32Array([0,1,-1,2]));assert.equal(b.toString('ascii',0,4),'RIFF');assert.equal(b.readUInt32LE(24),16000);assert.equal(b.readUInt32LE(40),8);assert.equal(b.readInt16LE(50),32767);});
