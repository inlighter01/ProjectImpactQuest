
const KEY='iq_drafts';
function getDrafts(){return JSON.parse(localStorage.getItem(KEY)||'[]');}
function saveDraft(data){const d=getDrafts();d.push({...data,status:'Draft'});localStorage.setItem(KEY,JSON.stringify(d));alert('Draft saved');}
document.addEventListener('DOMContentLoaded',()=>{
 const f=document.getElementById('questForm');
 if(f){
 document.getElementById('saveDraft').onclick=()=>saveDraft({title:title.value,category:category.value,description:description.value,impact:impact.value});
 document.getElementById('previewBtn').onclick=()=>{sessionStorage.setItem('quest_preview',JSON.stringify({title:title.value,category:category.value,description:description.value,impact:impact.value}));location='quest-preview.html';};
 f.onsubmit=(e)=>{e.preventDefault();const d=getDrafts();d.push({title:title.value,category:category.value,description:description.value,impact:impact.value,status:'Submitted'});localStorage.setItem(KEY,JSON.stringify(d));alert('Submitted for review');location='my-quests.html';};
 }
 const p=document.getElementById('preview'); if(p){const q=JSON.parse(sessionStorage.getItem('quest_preview')||'{}'); p.innerHTML=`<h2>${q.title||''}</h2><p><b>${q.category||''}</b></p><p>${q.description||''}</p><p>${q.impact||''}</p>`;}
 const l=document.getElementById('list'); if(l){l.innerHTML=getDrafts().map(q=>`<div class="quest-card"><h3>${q.title}</h3><p>${q.status}</p></div>`).join('')||'<p>No quests yet.</p>';}
});
