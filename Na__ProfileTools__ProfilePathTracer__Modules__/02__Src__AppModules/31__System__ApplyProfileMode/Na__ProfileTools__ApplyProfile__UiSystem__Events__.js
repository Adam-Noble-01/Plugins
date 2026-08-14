/* =============================================================================
   NA PROFILE TOOLS - APPLY PROFILE - UI SYSTEM - EVENTS
   =============================================================================
   FILE       : Na__ProfileTools__ApplyProfile__UiSystem__Events__.js
   NAMESPACE  : window.Na__ProfilePathTracer__Ui__Events
   PURPOSE    : Attach DOM event listeners to Apply Profile tab controls,
                the Create Profile form, and the header action buttons.
   ============================================================================= */

(function() {
    'use strict';
    let na_is_header_reload_bound = false;

    // -------------------------------------------------------------------------
    // REGION | Main Controls Event Wiring
    // -------------------------------------------------------------------------

    function Na__Ui__AttachEvents(handlers) {
        var btnGenerate             = document.getElementById('naBtnGenerate');
        var btnPickSceneProfile     = document.getElementById('naBtnPickSceneProfile');
        var btnClearSceneProfile    = document.getElementById('naBtnClearSceneProfile');

        var switchOptions = document.querySelectorAll('.na-switch__option[data-na-switch-key]');
        if (switchOptions && switchOptions.length > 0) {
            Array.prototype.forEach.call(switchOptions, function(switchOption) {
                switchOption.addEventListener('click', function() {
                    var switchKey   = switchOption.getAttribute('data-na-switch-key') || '';
                    var switchValue = switchOption.getAttribute('data-na-switch-value') || '';
                    if (switchOption.getAttribute('aria-pressed') === 'true') return;

                    if (switchKey === 'profileSourceMode') {
                        handlers.Na__Events__OnProfileSourceModeChange(switchValue);
                    } else if (switchKey === 'pathMode') {
                        handlers.Na__Events__OnPathModeChange(switchValue);
                    }
                });
            });
        }

        Na__Ui__AttachInsertPointEvents(handlers);

        var toggleBtns = document.querySelectorAll('.na-toggle-btn[data-na-toggle-key]');
        if (toggleBtns && toggleBtns.length > 0) {
            Array.prototype.forEach.call(toggleBtns, function(toggleBtn) {
                toggleBtn.addEventListener('click', function() {
                    var toggleKey = toggleBtn.getAttribute('data-na-toggle-key') || '';
                    var isCurrentlyActive = toggleBtn.getAttribute('aria-pressed') === 'true';
                    toggleBtn.setAttribute('aria-pressed', String(!isCurrentlyActive));
                    toggleBtn.classList.toggle('na-toggle-btn--active', !isCurrentlyActive);
                    handlers.Na__Events__OnToggleChange(toggleKey, !isCurrentlyActive);
                });
            });
        }

        var rotationPills = document.querySelectorAll('.na-rotation-pill[data-na-rotation-step]');
        if (rotationPills && rotationPills.length > 0) {
            Array.prototype.forEach.call(rotationPills, function(pill) {
                pill.addEventListener('click', function() {
                    var stepValue = parseInt(pill.getAttribute('data-na-rotation-step'), 10) || 0;
                    handlers.Na__Events__OnRotateToStep(stepValue);
                });
            });
        }

        if (btnGenerate) {
            btnGenerate.addEventListener('click', function() {
                handlers.Na__Events__OnGenerate();
            });
        }

        var btnReverseDirection = document.getElementById('naBtnReverseDirection');
        if (btnReverseDirection) {
            btnReverseDirection.addEventListener('click', function() {
                handlers.Na__Events__OnReverseDirectionToggle();
            });
        }

        if (btnPickSceneProfile) {
            btnPickSceneProfile.addEventListener('click', function() {
                handlers.Na__Events__OnPickSceneProfile();
            });
        }

        if (btnClearSceneProfile) {
            btnClearSceneProfile.addEventListener('click', function() {
                handlers.Na__Events__OnClearSceneProfile();
            });
        }

    }

    // endregion ----------------------------------------------------------------

    // -------------------------------------------------------------------------
    // REGION | Insert Point Picker Events
    // -------------------------------------------------------------------------

    // The preview SVG is re-rendered on every state change, so vertex clicks are
    // delegated from the <svg> element instead of bound per handle.
    function Na__Ui__AttachInsertPointEvents(handlers) {
        var btnSetInsertPoint   = document.getElementById('naBtnSetInsertPoint');
        var btnResetInsertPoint = document.getElementById('naBtnResetInsertPoint');
        var viewportSvg         = document.getElementById('naProfileViewportSvg');

        if (btnSetInsertPoint) {
            btnSetInsertPoint.addEventListener('click', function() {
                handlers.Na__Events__OnToggleInsertPointPick();
            });
        }

        if (btnResetInsertPoint) {
            btnResetInsertPoint.addEventListener('click', function() {
                handlers.Na__Events__OnResetInsertPoint();
            });
        }

        if (viewportSvg) {
            viewportSvg.addEventListener('click', function(clickEvent) {
                var target = clickEvent.target;
                if (!target || !target.getAttribute) return;

                var vertexIndex = target.getAttribute('data-na-vertex-index');
                if (vertexIndex === null) return;

                handlers.Na__Events__OnPickInsertPointVertex(parseInt(vertexIndex, 10));
            });
        }
    }

    // endregion ----------------------------------------------------------------

    // -------------------------------------------------------------------------
    // REGION | Create Profile Form Events
    // -------------------------------------------------------------------------

    function Na__Ui__AttachCreateProfileFormEvents(handlers) {
        var btnSave   = document.getElementById('naBtnSaveProfile');
        var btnCancel = document.getElementById('naBtnCancelCreateProfile');

        if (btnSave) {
            btnSave.addEventListener('click', function() {
                handlers.Na__Events__OnSaveProfile();
            });
        }

        if (btnCancel) {
            btnCancel.addEventListener('click', function() {
                handlers.Na__Events__OnCancelCreateProfile();
            });
        }
    }

    // endregion ----------------------------------------------------------------

    // -------------------------------------------------------------------------
    // REGION | Header Events (bound once only)
    // -------------------------------------------------------------------------

    function Na__Ui__AttachHeaderEvents(handlers) {
        if (na_is_header_reload_bound) return;

        const btnReloadPlugin = document.getElementById('na-btn-reload-plugin');
        if (!btnReloadPlugin) return;

        btnReloadPlugin.addEventListener('click', function() {
            handlers.Na__Events__OnReloadPlugin();
        });
        na_is_header_reload_bound = true;
    }

    // endregion ----------------------------------------------------------------

    // -------------------------------------------------------------------------
    // REGION | Public Exports
    // -------------------------------------------------------------------------

    window.Na__ProfilePathTracer__Ui__Events = {
        Na__Ui__AttachEvents: Na__Ui__AttachEvents,
        Na__Ui__AttachHeaderEvents: Na__Ui__AttachHeaderEvents,
        Na__Ui__AttachCreateProfileFormEvents: Na__Ui__AttachCreateProfileFormEvents
    };

    // endregion ----------------------------------------------------------------
})();
