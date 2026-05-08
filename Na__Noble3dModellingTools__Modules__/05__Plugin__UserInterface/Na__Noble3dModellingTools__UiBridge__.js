(function() {
    'use strict';

    // =============================================================================
    // NA NOBLE3D MODELLING TOOLS - HTMLDIALOG UI BRIDGE
    //
    // FILE       : Na__Noble3dModellingTools__UiBridge__.js
    // PURPOSE    : Tab switching, SketchUp sketchup.run_command, footer status-line
    // =============================================================================

    // -----------------------------------------------------------------------------
    // REGION | DOM Queries And Footer Status Messaging
    // -----------------------------------------------------------------------------

    function Na__Noble3d__StatusElement() {
        return document.getElementById('naNoble3dStatus');
    }

    function Na__Noble3d__SetStatus(text, variant) {
        var statusElement = Na__Noble3d__StatusElement();
        if (!statusElement) {
            return;
        }

        statusElement.textContent = String(text || '');
        statusElement.className = 'naNoble3d__Status naNoble3d__Status--' + String(variant || 'info');
    }

    // endregion -------------------------------------------------------------------


    // -----------------------------------------------------------------------------
    // REGION | Tab Activation — Panels And Tab Buttons
    // -----------------------------------------------------------------------------

    function Na__Noble3d__ShowTab(tabId, buttonElement) {
        var tabPanels = document.querySelectorAll('.naNoble3d__TabPanel');
        for (var panelIndex = 0; panelIndex < tabPanels.length; panelIndex += 1) {
            tabPanels[panelIndex].classList.remove('naNoble3d__TabPanel--active');
        }

        var tabButtons = document.querySelectorAll('.naNoble3d__TabButton');
        for (var buttonIndex = 0; buttonIndex < tabButtons.length; buttonIndex += 1) {
            tabButtons[buttonIndex].classList.remove('naNoble3d__TabButton--active');
        }

        var panel = document.getElementById('tab-' + tabId);
        if (panel) {
            panel.classList.add('naNoble3d__TabPanel--active');
        }

        if (buttonElement) {
            buttonElement.classList.add('naNoble3d__TabButton--active');
        }
    }

    // endregion -------------------------------------------------------------------


    // -----------------------------------------------------------------------------
    // REGION | SketchUp Ruby Bridge — Deferred Command Invocation
    // -----------------------------------------------------------------------------

    function Na__Noble3d__RunCommand(commandId) {
        if (!window.sketchup || !window.sketchup.run_command) {
            Na__Noble3d__SetStatus('SketchUp bridge unavailable.', 'error');
            return;
        }

        Na__Noble3d__SetStatus('Running command: ' + commandId + '...', 'info');
        window.sketchup.run_command(String(commandId));
    }

    // endregion -------------------------------------------------------------------


    // -----------------------------------------------------------------------------
    // REGION | Bootstrap — Ready Handler And Window API Surface
    // -----------------------------------------------------------------------------

    document.addEventListener('DOMContentLoaded', function() {
        var firstTabButton = document.querySelector('.naNoble3d__TabButton');
        if (firstTabButton) {
            firstTabButton.click();
        }
    });

    window.Na__Noble3d__ShowTab = Na__Noble3d__ShowTab;
    window.Na__Noble3d__RunCommand = Na__Noble3d__RunCommand;

    // endregion -------------------------------------------------------------------


    // =============================================================================
    // END OF FILE
    // =============================================================================
})();
