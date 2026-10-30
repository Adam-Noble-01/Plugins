// =============================================================================
// NA PAINTERLYNPR ASSETS - MATERIALS - UI SYSTEM - MAIN UI LOGIC
// =============================================================================
//
// FILE       : Na__PainterlyAssets__Materials__UiSystem__MainUiLogic__.js
// NAMESPACE  : window.Na__PainterlyAssets__MaterialsUi
// PURPOSE    : The Materials tab: one swatch per PainterlyNPR material class,
//              in the library's groups, each as PainterlyNPR draws it (its
//              RND picture, else its colour). A click paints the selection
//              (Ruby decides how, by what is selected).
// CREATED    : 30-Oct-2026
//
// RUBY CALLS : paintMaterial { key }
// LISTENS TO : state
//
// =============================================================================

(function () {
    'use strict';

    var Shell  = window.Na__PainterlyAssets__Shell;
    var Bridge = window.Na__PainterlyAssets__Bridge;

    function na_render(palette) {
        var box   = Shell.na_clear(document.getElementById('na-mat-groups'));
        var fault = document.getElementById('na-mat-fault');
        if (!box || !fault) return;
        if (!palette || !palette.ok) {
            fault.textContent = palette ? palette.message : 'The swatches have not been read yet.';
            fault.classList.remove('na-hidden');
            Shell.na_text('na-mat-count', '');
            return;
        }
        fault.classList.add('na-hidden');
        Shell.na_text('na-mat-count', palette.count + ' swatches');

        (palette.groups || []).forEach(function (group) {
            var section = Shell.na_el('section', 'na-card na-mat-group');
            section.appendChild(Shell.na_el('h3', 'na-card__title', group.label));
            var grid = Shell.na_el('div', 'na-mat-grid');
            grid.setAttribute('role', 'list');
            group.swatches.forEach(function (swatch) { grid.appendChild(na_tile(swatch)); });
            section.appendChild(grid);
            box.appendChild(section);
        });
    }

    function na_tile(swatch) {
        var tile = Shell.na_el('button', 'na-mat-tile');
        tile.type  = 'button';
        tile.title = swatch.label + ' (' + swatch.name + ')\n' + swatch.description;
        tile.setAttribute('role', 'listitem');

        var face = Shell.na_el('span', 'na-mat-tile__face');
        face.style.backgroundColor = swatch.colour;
        if (swatch.picture) {
            var img = Shell.na_el('img');
            img.src     = swatch.picture;
            img.alt     = '';
            img.onerror = function () { img.remove(); };                                                   // <-- The colour stands in
            face.appendChild(img);
        }
        var chip = Shell.na_el('span', 'na-mat-tile__chip');
        chip.style.backgroundColor = swatch.colour;
        chip.title = 'In SketchUp: ' + swatch.colour + (swatch.opacity < 1 ? ', ' + Math.round(swatch.opacity * 100) + '% opaque' : '');
        face.appendChild(chip);

        tile.appendChild(face);
        tile.appendChild(Shell.na_el('span', 'na-mat-tile__label', swatch.label));
        tile.addEventListener('click', function () {
            if (!Bridge.na_call('paintMaterial', { key: swatch.key })) Shell.na_set_status('Painting needs SketchUp: this is a preview of the page.', 'warn');
        });
        return tile;
    }

    Shell.na_on('state', function (state) { na_render(state ? state.materials : null); });

    window.Na__PainterlyAssets__MaterialsUi = { na_render: na_render };
})();

// =============================================================================
// END OF FILE
// =============================================================================
