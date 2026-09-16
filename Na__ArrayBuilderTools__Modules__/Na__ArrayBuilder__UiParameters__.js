/* =============================================================================
   NA ARRAY BUILDER TOOLS - PARAMETER CONTROLS
   FILE       : Na__ArrayBuilder__UiParameters__.js
   AUTHOR     : Noble Architecture
   PURPOSE    : Live sliders, override boxes, calculations and dimensional nudges.
   ============================================================================= */

import { Na__UiInput__ParseLength, Na__UiInput__Minimum, Na__UiInput__Resolve, Na__UiInput__Nudge } from './Na__ArrayBuilder__UiInput__.js';

// FUNCTION | Keep Slider Bounds Open to Typed Overrides
// -----------------------------------------------------------------------------
export function Na__Parameters__Sync(na_field, na_commit = false) {
    const na_slider = na_field.parentElement.querySelector('input[type="range"]');
    if (!na_slider) return;
    const na_value = Na__UiInput__ParseLength(na_field.value, na_field.dataset.naField);
    if (na_value === null) return;
    na_slider.min = Math.min(Number(na_slider.dataset.naMin), na_value);
    na_slider.max = Math.max(Number(na_slider.dataset.naMax), na_value);
    na_slider.value = na_value;
    if (na_commit) {
        na_field.dataset.naCommitted = na_value;
        delete na_field.dataset.naExpressionPending;
    }
}

export function Na__Parameters__Commit(na_field) {
    if (!na_field.dataset.naParameter) return true;
    try {
        na_field.value = Na__UiInput__Resolve(na_field.value, na_field.dataset.naField, na_field.dataset.naCommitted);
        Na__Parameters__Sync(na_field, true);
        na_field.removeAttribute('aria-invalid');
        na_field.setCustomValidity('');
        return true;
    } catch (na_error) {
        na_field.setAttribute('aria-invalid', 'true');
        na_field.setCustomValidity(na_error.message);
        return false;
    }
}

// FUNCTION | Add Family-Style Range Controls to Each Dimensional Text Box
// -----------------------------------------------------------------------------
export function Na__Parameters__Install(na_fields, Na__Parameters__Changed) {
    na_fields.filter(na_field => na_field.tagName === 'INPUT' && na_field.type !== 'checkbox').forEach(na_field => {
        const na_key = na_field.dataset.naField;
        const na_label = na_field.closest('label').childNodes[0].textContent.trim();
        const na_slider = document.createElement('input');
        na_slider.type = 'range';
        na_slider.step = 'any';
        na_slider.dataset.naMin = Na__UiInput__Minimum(na_key) < 0 ? '-2000' : String(Na__UiInput__Minimum(na_key));
        na_slider.dataset.naMax = '2000';
        na_slider.setAttribute('aria-label', na_label + ' slider');
        const na_control = document.createElement('span');
        na_control.className = 'na-parameter-control';
        na_field.before(na_control);
        na_control.append(na_slider, na_field);
        na_field.dataset.naParameter = 'true';
        na_field.setAttribute('aria-label', na_label);
        na_field.title = '↑ / ↓: 5 mm · Shift: 50 mm · Enter or leave the field to calculate, e.g. 1200/3, +50, *2.';
        Na__Parameters__Sync(na_field, true);
        na_slider.addEventListener('input', () => {
            na_field.value = Number(Number(na_slider.value).toFixed(1));
            Na__Parameters__Sync(na_field, true);
            Na__Parameters__Changed();
        });
        na_field.addEventListener('input', () => {
            na_field.setCustomValidity('');
            const na_pending = /^[+*/^]/.test(na_field.value.trim()) || Na__UiInput__ParseLength(na_field.value, na_key) === null;
            if (na_pending) na_field.dataset.naExpressionPending = 'true';
            else delete na_field.dataset.naExpressionPending;
            Na__Parameters__Sync(na_field);
            Na__Parameters__Changed();
        });
        na_field.addEventListener('blur', () => {
            const na_before = Na__UiInput__ParseLength(na_field.value, na_key);
            const na_expression = !!na_field.dataset.naExpressionPending;
            const na_valid = Na__Parameters__Commit(na_field);
            if (!na_valid || na_expression || Number(na_field.value) !== na_before) Na__Parameters__Changed();
        });
        [na_field, na_slider].forEach(na_input => na_input.addEventListener('keydown', na_event => {
            if (na_event.key === 'Enter' && na_input === na_field) {
                na_event.preventDefault();
                Na__Parameters__Commit(na_field);
                Na__Parameters__Changed();
            } else if (['ArrowUp', 'ArrowDown', 'ArrowLeft', 'ArrowRight'].includes(na_event.key) &&
                       (na_input === na_slider || ['ArrowUp', 'ArrowDown'].includes(na_event.key))) {
                na_event.preventDefault();
                if (!Na__Parameters__Commit(na_field)) return;
                na_field.value = Na__UiInput__Nudge(Number(na_field.value), na_key, ['ArrowUp', 'ArrowRight'].includes(na_event.key) ? 1 : -1, na_event.shiftKey);
                Na__Parameters__Sync(na_field, true);
                Na__Parameters__Changed();
            }
        }));
    });
}
