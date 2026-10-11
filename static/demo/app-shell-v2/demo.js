import { contractor, owner, icons } from './navigation.js?v=sidebar-v2-1';
const $ = (s) => document.querySelector(s);
let scenario = 'full';
let selected = '/jobs';
let collapsed = false;
let currentGroups = [];
let toastTimer;
const escape = (s) => s.replace(/[&<>"']/g, (c) => ({'&':'&amp;','<':'&lt;','>':'&gt;','"':'&quot;',"'":'&#39;'}[c]));
const icon = (name) => `<span aria-hidden="true">${icons[name] || icons.dashboard}</span>`;
function hydrateIcons(root = document) { root.querySelectorAll('[data-icon]').forEach(el => { el.innerHTML = icons[el.dataset.icon] || icons.dashboard; if (!el.matches('button, a')) el.setAttribute('aria-hidden','true'); else el.querySelector('svg')?.setAttribute('aria-hidden','true'); }); }
function isOwner() { return ['owner','teammate'].includes(scenario); }
function allowed(item) {
 if(scenario === 'restricted') return ['Dashboard','Schedule','Requests','Jobs','Settings','Growth Feed','Team','Notifications','Usage'].includes(item.label);
 if(scenario === 'small') return ['Dashboard','Clients','Reviews','Settings','Growth Feed','Team','Notifications','Usage'].includes(item.label);
 if(scenario === 'teammate') return ['Leads','Deals','Calendar','Support','My preferences'].includes(item.label);
 return true;
}
function render() {
 currentGroups = (isOwner() ? owner : contractor).map(g => ({...g,items:g.items.map(i=>scenario==='teammate' && i.label==='Settings'?{...i,label:'My preferences',href:'/jafar/settings/preferences'}:i).filter(allowed)})).filter(g=>g.items.length);
 const all = currentGroups.flatMap(g=>g.items);
 if(!all.some(i=>i.href===selected && !i.soon)) selected=all.find(i=>!i.soon).href;
 const long=$('#long-name').checked;
 const brand=isOwner()?'Control Room':long?'Oak & Stone Landscape, Property Care and Outdoor Living':'Oak & Stone';
 const eyebrow=isOwner()?(scenario==='teammate'?'Uplift team':'Platform owner'):'Business workspace';
 const html=`${isOwner()?`<div class="sidebar__brand"><span class="sidebar__mark">${icon('arrow-up-right')}</span><span class="sidebar__wordmark">uplift</span></div>`:''}<div class="sidebar__identity"><span class="sidebar__initial">${isOwner()?'U':'O'}</span><div class="sidebar__business"><strong>${brand}</strong><p>${eyebrow}</p></div></div><nav aria-label="${eyebrow}">${currentGroups.map(g=>`<section class="sidebar__group" aria-label="${g.label}"><p class="sidebar__heading">${g.label}</p><ul class="sidebar__list">${g.items.map(i=>`<li>${i.soon?`<span class="sidebar__link" aria-disabled="true" title="${i.label} — coming soon">${icon(i.icon)}<span class="sidebar__label">${i.label}</span><span class="sidebar__badge">Soon</span></span>`:`<a class="sidebar__link" href="#preview-${i.href.replaceAll('/','-')}" data-destination="${i.href}" title="${i.label}" ${i.href===selected?'aria-current="page"':''}>${icon(i.icon)}<span class="sidebar__label">${i.label}</span>${isOwner() && i.label==='Support'?'<span class="sidebar__badge">4</span>':''}</a>`}</li>`).join('')}</ul></section>`).join('')}</nav>`;
 $('#desktop-nav').innerHTML=html+`<div class="sidebar__footer"><button class="sidebar__collapse" id="collapse" aria-label="${collapsed?'Expand':'Collapse'} navigation" aria-pressed="${collapsed}">${icon(collapsed?'layout-sidebar-left-expand':'layout-sidebar-left-collapse')}<span class="sidebar__collapse-label">Collapse navigation</span></button></div>`;
 $('#mobile-nav-content').innerHTML=`<div class="sidebar">${html}<button class="sidebar__collapse" data-open="theme-dialog">${icon('moon')}Appearance options</button></div>`;
 $('#shell').classList.toggle('shell--collapsed',collapsed);
 $('#shell').classList.toggle('shell--business',!isOwner());
 $('#mobile-nav').classList.toggle('drawer--business',!isOwner());
 $('#account-name').textContent=long?'Alexandra Morgan-Sutherland':scenario==='teammate'?'Sam Seller':'Alex Morgan';
 $('#account-role').textContent=`${eyebrow} · fictional account`;
 $('#security').hidden=isOwner();
 $('#search').hidden=isOwner();
 $('#workspace-label').textContent=isOwner()?'Control Room':'Workspace';
 const item=all.find(i=>i.href===selected);
 const group=currentGroups.find(g=>g.items.includes(item));
 $('#page-title').textContent=item.label;
 $('#current-label').textContent=item.label;
 $('#page-context').textContent=group.label.toUpperCase();
 $('#page-description').textContent=`${item.label} destination preview. Your real ${isOwner()?'Control Room':'business'} page would open here.`;
 $('.hero__icon').innerHTML=icon(item.icon);
 $('#scenario-note').textContent=scenario==='full'?'Full-access sample. Actual access is decided by the business package and staff permissions.':scenario==='owner'?'Control Room owner navigation from the current app. Search is not offered in this workspace.':'Illustrative restricted access, not a fixed role definition. Production visibility follows the server’s resolved permissions and package.';
 $('#collapse').onclick=()=>{collapsed=!collapsed;render();$('#collapse').focus();};
 searchResults();
}
function toast(message) { $('#toast').textContent=message;$('#toast').hidden=false;clearTimeout(toastTimer);toastTimer=setTimeout(()=>$('#toast').hidden=true,5000); }
function openDialog(id) { const dialog=document.getElementById(id); if(!dialog)return; document.querySelectorAll('dialog[open]').forEach(d=>d.close()); dialog.showModal(); if(id==='search-dialog') $('#search-input').focus(); if(id==='mobile-nav') $('#open-nav').setAttribute('aria-expanded','true'); }
function navigate(href) { selected=href;document.querySelectorAll('dialog[open]').forEach(d=>d.close());render();$('#main').focus(); }
function searchResults() { const term=$('#search-input').value.toLowerCase();const matches=currentGroups.flatMap(g=>g.items).filter(i=>!i.soon && i.label.toLowerCase().includes(term));$('#search-results').innerHTML=matches.length?matches.map(i=>`<a href="#preview-${i.href.replaceAll('/','-')}" data-destination="${i.href}">${icon(i.icon)}${escape(i.label)}</a>`).join(''):'<p class="notice" role="status">No matching pages. Try another name.</p>'; }
function notifications() { const state=$('#notification-state').value;$('#notification-content').innerHTML=state==='empty'?'<p class="notice">You’re all caught up. No notifications.</p>':state==='loading'?'<p class="notice" role="status">Loading notifications…</p>':state==='error'?'<div class="notice notice--error" role="alert">Notifications couldn’t load. <button class="button" id="retry-notifications">Try again</button></div>':'<div class="notice"><strong>Visit starts tomorrow</strong><p>Backyard transformation · 9:00 AM</p><p class="disclaimer">Fictional notification · 5 minutes ago</p></div>'; }
document.addEventListener('click',event=> { const destination=event.target.closest('[data-destination]');if(destination){event.preventDefault();navigate(destination.dataset.destination);return;} const opener=event.target.closest('[data-open]');if(opener){openDialog(opener.dataset.open);return;} if(event.target.closest('[data-close]'))event.target.closest('dialog').close();const preview=event.target.closest('[data-preview]');if(preview){event.target.closest('dialog').close();toast(`Demo: ${preview.dataset.preview}`);} if(event.target.closest('#retry-notifications')){$('#notification-state').value='populated';notifications();} });
document.querySelectorAll('dialog').forEach(dialog=>{ dialog.addEventListener('click',e=>{if(e.target===dialog){const r=dialog.getBoundingClientRect();if(e.clientX<r.left || e.clientX>r.right || e.clientY<r.top || e.clientY>r.bottom)dialog.close();}});dialog.addEventListener('close',()=>$('#open-nav').setAttribute('aria-expanded','false')); });
$('#open-nav').onclick=()=>openDialog('mobile-nav');
$('#scenario').onchange=e=>{scenario=e.target.value;$('#search-input').value='';render();};
$('#long-name').onchange=render;
$('#search-input').oninput=searchResults;
$('#notification-state').onchange=notifications;
$('#sign-out-error').onclick=()=>$('#account-error').textContent='Could not sign out. Please try again. (Simulated failure)';
document.addEventListener('keydown',e=>{if((e.ctrlKey||e.metaKey) && e.key.toLowerCase()==='k' && !isOwner()){e.preventDefault();openDialog('search-dialog');}});
matchMedia('(min-width:768px)').addEventListener('change',e=>{if(e.matches && $('#mobile-nav').open)$('#mobile-nav').close();});
hydrateIcons();render();notifications();

// Close the layer on the first Escape even when a search input would consume it.
document.addEventListener('keydown', event => { if (event.key === 'Escape') { const dialog = document.querySelector('dialog[open]'); if (dialog) { event.preventDefault(); dialog.close(); } } }, true);
