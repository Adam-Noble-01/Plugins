/* Real scatter HTML in Chromium, with the SketchUp transport boundary doubled. */
const { chromium } = require(process.argv[2] || 'playwright');
const fs = require('node:fs'), path = require('node:path'), assert = require('node:assert/strict');
const root = path.resolve(__dirname,'..'), prefix = 'Na__Noble3dModellingTools__VegetationSketcher__';
let checks = 0;
function check(value,message) { assert.ok(value,message); checks++; }
(async () => {
  const browser = await chromium.launch({ headless:true,...(process.argv[3] ? { executablePath:process.argv[3] } : {}) });
  try {
    const page=await browser.newPage({ viewport:{ width:540,height:840 } });
    const errors=[]; page.on('pageerror',e=>errors.push(e.message));
    const html=fs.readFileSync(path.join(root,prefix+'ScatterUi__.html'),'utf8')
      .replace('{{STYLESHEET_CONTENT}}',fs.readFileSync(path.join(root,prefix+'Styles__.css'),'utf8')).replace('{{UI_BRIDGE_SCRIPT}}','');
    await page.setContent(html);
    await page.evaluate(() => {
      window.requests=[];
      window.scatterState={ session:'scatter-test', context:1, target_id:null, painting:false, count:null, selected:2, load:true, sources:[],
        options:{ radius:10000,spacing:3000,chance:100,limit:2000,scale_min:85,scale_max:115,rotation:360,slope:60,seed:12345,align:false } };
      window.sketchup={
        na_scatter_ready() { window.Na__VegetationScatter__Receive('state',window.scatterState); },
        na_scatter_event(raw) {
          const r=JSON.parse(raw); window.requests.push(r);
          setTimeout(()=>{
            const s=window.scatterState;
            if(r.payload.options) {
              s.options=r.payload.options;
              s.sources=s.sources.map(source=>({...source,weight:r.payload.weights[source.key]}));
            }
            if(r.action==='capture') { s.context++; s.sources=[{key:'10',name:'Douglas fir',weight:100},{key:'11',name:'<Oak & shrub>',weight:100}]; }
            if(r.action==='bed_mix') {
              s.context++; s.target_id=null;
              s.options={...s.options,radius:1200,spacing:650,scale_min:90,scale_max:110,limit:1500};
              s.sources=['spreading','cushion','rounded','loose','upright','arching'].flatMap((type,i)=>[1,2].map(v=>({key:type+v,name:type+' '+v,weight:[15,20,25,20,10,10][i]/2})));
            }
            if(r.action==='flower_mix') {
              s.context++; s.target_id=null;
              s.options={...s.options,radius:900,spacing:500,scale_min:90,scale_max:110,limit:1000};
              s.sources=['daisy_clump','flower_spikes','umbel_clump','tuft_grass','fountain_grass','plume_grass'].flatMap((type,i)=>[1,2].map(v=>({key:type+v,name:type+' '+v,weight:[25,20,15,20,15,5][i]/2})));
            }
            if(r.action==='paint') { s.painting=true; s.target_id=null; s.context++; }
            if(r.action==='finish') { s.painting=false; s.target_id='500'; s.count=123; s.context++; }
            if(r.action==='variation') s.options.seed++;
            s.load=true;
            window.Na__VegetationScatter__Receive('state',s);
            window.Na__VegetationScatter__Receive('ack',{id:r.id,success:true});
          },5);
        }
      };
    });
    await page.addScriptTag({content:fs.readFileSync(path.join(root,prefix+'ScatterUi__.js'),'utf8')});
    await page.waitForFunction(()=>!document.querySelector('#naScatter_capture').disabled);
    check(await page.locator('#naScatter_paint').isDisabled(),'painting requires a captured palette');
    check(await page.evaluate(()=>Array.from(document.querySelectorAll('[data-scatter]')).every(e=>e.checkValidity())),'default scatter inputs valid');
    await page.locator('#naScatter_capture').click();
    await page.waitForFunction(()=>document.querySelectorAll('[data-weight]').length===2 && !document.querySelector('#naScatter_paint').disabled);
    check((await page.locator('#naScatter_sources').textContent()).includes('<Oak & shrub>'),'source names safely displayed as text');
    check(await page.locator('#naScatter_sources script').count()===0,'source names cannot inject HTML');
    await page.locator('[data-weight="10"]').fill('75'); await page.locator('[data-weight="11"]').fill('25');
    check((await page.locator('.naScatter__Share').allTextContents()).join(',')==='75.0%,25.0%','weights show normalized probability');
    await page.locator('[data-scatter="spacing"]').fill('2400');
    await page.waitForTimeout(750);
    check(await page.evaluate(()=>window.requests.length===1),'editing controls does not sync with Ruby');
    await page.locator('[data-weight="10"]').fill('0'); await page.locator('[data-weight="11"]').fill('0');
    check(await page.locator('#naScatter_paint').isDisabled(),'all-zero mix cannot start painting');
    await page.locator('[data-weight="10"]').fill('75'); await page.locator('[data-weight="11"]').fill('25');
    await page.locator('[data-scatter="spacing"]').fill('');
    await page.locator('#naScatter_paint').click();
    check(await page.evaluate(()=>window.requests.length===1),'invalid spacing blocks bridge action');
    check((await page.locator('#naScatter_status').textContent()).includes('spacing'),'validation identifies invalid field');
    await page.locator('[data-scatter="spacing"]').fill('2400');
    await page.locator('[data-scatter="scale_min"]').fill('150');
    await page.locator('#naScatter_paint').click();
    check((await page.locator('#naScatter_status').textContent()).includes('Minimum scale'),'reversed scale interval rejected');
    await page.locator('[data-scatter="scale_min"]').fill('85');
    await page.evaluate(()=>{document.querySelector('main').scrollTop=0;window.Na__VegetationScatter__Receive('status',{message:'Sources ready. Set your mix and paint onto a surface.',error:false});});
    await page.screenshot({path:path.join(__dirname,'scatter-verified.png')});
    await page.locator('#naScatter_paint').click();
    await page.waitForFunction(()=>window.scatterState.painting && !document.querySelector('#naScatter_finish').disabled);
    check(await page.evaluate(()=>window.requests.at(-1).payload.weights['10']===75 && window.requests.at(-1).payload.options.spacing===2400),'paint sends current mix and dimensions');
    check(await page.locator('[data-weight="10"]').isDisabled() && await page.locator('[data-scatter="radius"]').isDisabled(),'painting freezes the stroke settings');
    check(await page.locator('#naScatter_finish').isVisible(),'brush can be finished from the menu');
    await page.locator('#naScatter_finish').click();
    await page.waitForFunction(()=>!document.querySelector('#naScatter_regenerate').disabled);
    check((await page.locator('#naScatter_info').textContent()).includes('123 plants'),'selected forest summary loads after Finish');
    await page.locator('[data-weight="10"]').fill('0'); await page.locator('[data-weight="11"]').fill('100');
    await page.locator('[data-scatter="align"]').check();
    await page.locator('#naScatter_regenerate').click();
    await page.waitForFunction(()=>window.requests.at(-1).action==='regenerate' && !document.querySelector('#naScatter_regenerate').disabled);
    check(await page.evaluate(()=>window.requests.at(-1).payload.target_id==='500' && window.requests.at(-1).payload.options.align),'regeneration addresses selected forest and alignment choice');
    await page.locator('#naScatter_variation').click();
    await page.waitForFunction(()=>window.scatterState.options.seed===12346);
    check(await page.locator('[data-scatter="seed"]').inputValue()==='12346','new variation loads acknowledged seed');
    await page.locator('#naScatter_bed_mix').click();
    await page.waitForFunction(()=>document.querySelectorAll('[data-weight]').length===12 && !document.querySelector('#naScatter_paint').disabled);
    check(await page.locator('[data-scatter="radius"]').inputValue()==='1200' && await page.locator('[data-scatter="spacing"]').inputValue()==='650','bed mix loads smaller brush and spacing');
    check(await page.locator('#naScatter_regenerate').isDisabled(),'loading bed mix releases existing forest target');
    check(await page.locator('[data-weight]').count()===12,'two variations of all six shrub types can be weighted');
    await page.locator('[data-weight="spreading1"]').fill('0');
    await page.locator('#naScatter_paint').click();
    await page.waitForFunction(()=>window.scatterState.painting && !document.querySelector('#naScatter_finish').disabled);
    check(await page.evaluate(()=>window.requests.at(-1).payload.weights.spreading1===0 && Object.keys(window.requests.at(-1).payload.weights).length===12),'bed painting forwards edited probabilities');
    check(await page.locator('#naScatter_bed_mix').isDisabled(),'cannot replace source recipes during a stroke');
    check(await page.locator('#naScatter_flower_mix').isDisabled(),'cannot load flowers during an active stroke');
    await page.locator('#naScatter_finish').click();
    await page.waitForFunction(()=>!document.querySelector('#naScatter_flower_mix').disabled);
    await page.locator('#naScatter_flower_mix').click();
    await page.waitForFunction(()=>document.querySelector('[data-weight="daisy_clump1"]') && !document.querySelector('#naScatter_paint').disabled);
    check(await page.locator('[data-weight]').count()===12 && await page.locator('[data-scatter="spacing"]').inputValue()==='500','flowers and grasses mix loads twelve sources and closer spacing');
    check(await page.locator('#naScatter_regenerate').isDisabled(),'new flower mix does not overwrite a selected forest');
    await page.locator('[data-weight="plume_grass1"]').fill('0');
    await page.locator('#naScatter_paint').click();
    await page.waitForFunction(()=>window.scatterState.painting && !document.querySelector('#naScatter_finish').disabled);
    check(await page.evaluate(()=>window.requests.at(-1).payload.weights.plume_grass1===0 && window.requests.at(-1).payload.options.radius===900),'flower painting passes edited weights and brush settings');
    check(errors.length===0,'no browser runtime errors: '+errors.join(', '));
    console.log(`PASS: ${checks} scatter browser controls and bridge checks.`);
  } finally { await browser.close(); }
})().catch(e=>{console.error(e);process.exitCode=1;});
