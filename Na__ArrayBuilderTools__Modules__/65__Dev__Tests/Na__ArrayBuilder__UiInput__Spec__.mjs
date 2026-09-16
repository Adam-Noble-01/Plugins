// Native geometry is covered separately; these exercise real browser modules.
import assert from 'node:assert/strict';
import { Na__UiInput__ParseLength } from '../Na__ArrayBuilder__UiInput__.js';
import { Na__Preview__Markup, Na__Preview__Sample } from '../Na__ArrayBuilder__UiPreview__.js';

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
console.log('Array Builder: 23 JavaScript input and preview checks passed.');
