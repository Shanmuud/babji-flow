'use strict';
let historyQuery='',historyLimit=40;
function renderHistory(){
 $('#main').innerHTML=heading('History','Search your dictations, recover text, and teach Babji a spelling.')+'<div class="history-toolbar"><input id="history-search" type="search" placeholder="Search text or app" aria-label="Search dictation history"><span id="history-count" class="muted"></span></div><p class="history-privacy">Transcripts are saved locally on this PC. Older sessions may contain activity totals only.</p><div id="history-results"></div><button id="history-more" class="secondary" hidden>Show more</button>';
 $('#history-search').value=historyQuery;on('#history-search','input',()=>{historyQuery=$('#history-search').value;historyLimit=40;renderHistoryRows();});on('#history-more','click',()=>{historyLimit+=40;renderHistoryRows();});renderHistoryRows();
}
function renderHistoryRows(){
 const query=historyQuery.trim().toLowerCase(),records=[...state.records].reverse().filter(r=>[r.text,r.raw,r.app].some(v=>String(v||'').toLowerCase().includes(query)));
 $('#history-count').textContent=records.length+' dictations';$('#history-more').hidden=records.length<=historyLimit;
 $('#history-results').innerHTML=records.slice(0,historyLimit).map(r=>'<article class="card history-entry"><div class="row"><strong>'+escape(r.app)+'</strong><small>'+escape(new Date(r.date).toLocaleString())+' &middot; '+r.words+' words</small></div><p class="note-body spaced">'+escape(r.text||'Text was not saved for this older session.')+'</p>'+(r.raw?'<details class="transcript-compare spaced"><summary>Original transcription</summary><p class="note-body spaced">'+escape(r.raw)+'</p></details>':'')+(r.text?'<div class="actions spaced"><button class="secondary" data-history-copy="'+escape(r.id)+'">Copy text</button><button class="quiet" data-history-correct="'+escape(r.id)+'">Save a correction</button></div>':'')+'</article>').join('')||'<div class="card empty">'+(query?'No dictations match your search.':'Your next dictation will appear here.')+'</div>';
 document.querySelectorAll('[data-history-copy]').forEach(b=>b.onclick=guarded(async()=>{await invoke('text:copy',records.find(r=>r.id===b.dataset.historyCopy).text);notice('Dictation copied');}));
 document.querySelectorAll('[data-history-correct]').forEach(b=>b.onclick=()=>openCorrection(records.find(r=>r.id===b.dataset.historyCorrect)));
}
function openCorrection(record){
 const selected=window.getSelection()?.toString().trim()||'';
 openEditor('<h2>Teach Babji a spelling</h2><p class="muted">Save a misheard word or phrase and its correct spelling. It will apply to future dictations; the original history stays unchanged.</p><label class="field">Babji heard<input id="correction-heard" required maxlength="100" value="'+escape(selected.length<=100?selected:'')+'" placeholder="e.g. rishy"></label><label class="field">Correct spelling<input id="correction-word" required maxlength="100" placeholder="e.g. Rishi"></label><details class="spaced"><summary>Reference transcript</summary><p class="note-body spaced">'+escape(record.raw||record.text)+'</p></details>',async()=>{await invoke('dictionary:learn',$('#correction-heard').value,$('#correction-word').value);notice('Correction saved to Dictionary for future dictations.');});
}
