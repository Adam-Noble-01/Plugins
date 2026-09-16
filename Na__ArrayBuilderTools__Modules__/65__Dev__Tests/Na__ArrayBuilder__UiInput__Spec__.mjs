// Native geometry is covered separately; these exercise real browser modules.
import assert from 'node:assert/strict';
import { Na__UiInput__ParseLength, Na__UiInput__Resolve, Na__UiInput__Nudge } from '../Na__ArrayBuilder__UiInput__.js';
import { Na__Arithmetic__Evaluate } from '../Na__ArrayBuilder__Arithmetic__.js';
import { Na__Preview__Markup, Na__Preview__Sample, Na__Preview__Transform } from '../Na__ArrayBuilder__UiPreview__.js';

for (const [na_text, na_expected] of [['150',150],['15 cm',150],['.15 m',150],['6 in',152.4],['6"',152.4],['2 ft',609.6]]) {
    assert.ok(Math.abs(Na__UiInput__ParseLength(na_text,'unit_width_mm')-na_expected)<1e-6);
}
for (const na_text of ['', '-', '.', '1e', '12oops', 'NaN', 'Infinity', '0', '-1', '1000001']) {
    assert.equal(Na__UiInput__ParseLength(na_text,'unit_width_mm'),null,na_text);
}
assert.equal(Na__UiInput__ParseLength('0','spacing_mm'),0);
assert.equal(Na__UiInput__ParseLength('-20','offset_lateral_mm'),-20);
assert.equal(Na__UiInput__ParseLength('1; alert(1)','spacing_mm'),null);
const na_markup = Na__Preview__Markup(Na__Preview__Sample({unit_width_mm:100,unit_depth_mm:30,unit_height_mm:75,spacing_mm:100}));
assert.match(na_markup, /<svg/);
assert.equal((na_markup.match(/<polygon/g)||[]).length,7);
assert.ok(!/NaN|Infinity/.test(na_markup));
assert.equal(Na__Preview__Markup({boxes:[],path:[]}), '');
assert.equal(Na__UiInput__ParseLength('-50', 'inset_mm'), -50);
for (const [na_expression, na_expected] of [['1200/3',400],['(250+50)*2',600],['2^3^2',512],['-2^2',-4],['1 m - 25 cm',750],['6 in + 25.4',177.8],['2×5+10÷2',15],['2*-3',-6]]) {
    assert.ok(Math.abs(Na__Arithmetic__Evaluate(na_expression)-na_expected)<1e-6, na_expression);
}
for (const na_expression of ['', '1/0', '1/(2-2)', '2+', '(1+2', '2 5', 'Infinity', '1;alert(1)', 'process.exit()', '2**3', '9^99999']) {
    assert.throws(() => Na__Arithmetic__Evaluate(na_expression), Error, na_expression);
}
assert.equal(Na__UiInput__Resolve('+50','unit_width_mm',100),150);
assert.equal(Na__UiInput__Resolve('-50','unit_width_mm',100),50);
assert.equal(Na__UiInput__Resolve('-50','inset_mm',100),-50);
assert.equal(Na__UiInput__Resolve('-50','offset_lateral_mm',100),-50);
assert.equal(Na__UiInput__Resolve('*2','unit_width_mm',100),200);
assert.equal(Na__UiInput__Resolve('/2','unit_width_mm',100),50);
assert.equal(Na__UiInput__Resolve('9000','unit_width_mm',100),9000);
assert.equal(Na__UiInput__Resolve('1000001','unit_width_mm',100),1000000);
assert.equal(Na__UiInput__Nudge(100,'unit_width_mm',1,false),105);
assert.equal(Na__UiInput__Nudge(100,'unit_width_mm',-1,true),50);
assert.equal(Na__UiInput__Nudge(0,'inset_mm',-1,true),-50);
assert.equal(Na__UiInput__Nudge(0.1,'unit_width_mm',-1,true),0.1);
const na_matrix = [0,2,0,0, -3,0,0,0, 0,0,4,0, 10,20,30,1];
assert.deepEqual(Na__Preview__Transform([1,2,3], na_matrix), [4,22,42]);
const na_mesh_markup = Na__Preview__Markup({ mesh: {points:[[0,0,0],[10,0,0],[3,5,9]],triangles:[[0,1,2,[50,150,200]]],edges:[[0,1],[1,2],[2,0]]}, instances:[na_matrix,na_matrix],path:[[0,0,0],[40,0,0]] });
assert.equal((na_mesh_markup.match(/<polygon/g)||[]).length,2);
assert.match(na_mesh_markup,/rgb\(/);
assert.ok(!/NaN|Infinity|undefined/.test(na_mesh_markup));
console.log('Array Builder: JavaScript input, arithmetic and mesh checks passed.');
