import {page} from 'vitest/browser';
import {it, expect, vi} from 'vitest';
import {render} from 'vitest-browser-svelte';
import MoneyInput from './MoneyInput.svelte';
import QuantityInput from './QuantityInput.svelte';
import TagSelect from '../ui/TagSelect.svelte';
import FilterChip from '../ui/FilterChip.svelte';
import '$lib/styles/app.scss';
vi.mock('$app/state',()=>({page:{data:{currencyCode:'USD'}}}));
it('captures focused shared-control screen checks',async()=>{
 document.body.style.padding='24px';
 document.body.style.background='var(--color-surface--background)';
 const fixtures=[
 render(FilterChip,{id:'filter',label:'Status',value:'late',restValue:'all',variant:'toolbar',options:[{value:'all',label:'All'},{value:'late',label:'Late'}],onchange:()=>{}}),
 render(MoneyInput,{id:'amount',label:'Amount',value:125000}),
 render(QuantityInput,{id:'quantity',label:'Quantity',value:2.5}),
 render(QuantityInput,{id:'disabled-quantity',label:'Cannot change',value:1,disabled:true}),
 render(MoneyInput,{id:'invalid-amount',label:'Amount',value:0,errorMessage:'Enter more than $0.00'}),
 render(TagSelect,{searchId:'visual-tags',catalog:[{id:'a',name:'VIP client',color:'#5b40bf'},{id:'b',name:'A very long customer tag name',color:'#118197'}],tagIds:['a','b']})
 ];
 for(const fixture of fixtures){fixture.container.style.maxWidth='420px';fixture.container.style.marginBottom='24px';}
 for(const width of [1440,390]) {
  await page.viewport(width,900);
  for(const theme of ['light','dark']) {
   document.documentElement.dataset.theme=theme;
   await page.screenshot({path:`../../../../docs/evidence/2026-10-19-batch6b/controls-${width}-${theme}.png`});
  }
 }
 expect(document.querySelectorAll('input').length).toBe(4);
});
