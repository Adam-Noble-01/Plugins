(function() {
    'use strict';

    // =============================================================================
    // NA NOBLE3D MODELLING TOOLS - HTMLDIALOG UI BRIDGE
    //
    // FILE       : Na__Noble3dModellingTools__UiBridge__.js
    // PURPOSE    : Tab switching, SketchUp sketchup.run_command, footer status-line,
    //              real-time cross-tab search
    //
    // CONFIG-FIRST DESIGN NOTE:
    // This bridge should stay generic. Tool tabs, groups, labels, command IDs,
    // ordering, and hotkey visibility come from the JSON registry rendered by Ruby.
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
    // REGION | Search State — Tracks Last Active Non-Search Tab
    // -----------------------------------------------------------------------------

    var naSearchState = {
        lastTabId: '',
        lastTabButton: null
    };

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

        if (tabId !== 'search') {
            naSearchState.lastTabId = tabId;
            naSearchState.lastTabButton = buttonElement;
            var searchInput = document.getElementById('naNoble3dSearchInput');
            if (searchInput) {
                searchInput.value = '';
            }
        }
    }

    function Na__Noble3d__ShowSearchTab(buttonElement) {
        Na__Noble3d__ShowTab('search', buttonElement);
        var searchInput = document.getElementById('naNoble3dSearchInput');
        if (searchInput) {
            searchInput.focus();
        }
    }

    // endregion -------------------------------------------------------------------


    // -----------------------------------------------------------------------------
    // REGION | Real-Time Cross-Tab Search
    // -----------------------------------------------------------------------------

    function Na__Noble3d__SearchTools(query) {
        var resultsContainer = document.getElementById('naNoble3dSearchResults');
        if (!resultsContainer) {
            return;
        }

        var trimmed = (query || '').trim();

        if (trimmed === '') {
            na__Noble3d__RestorePreviousTab();
            return;
        }

        var searchTabButton = document.querySelector('.naNoble3d__TabButton--search');
        Na__Noble3d__ShowTab('search', searchTabButton);

        resultsContainer.innerHTML = '';

        var lowerQuery = trimmed.toLowerCase();
        var allCards = document.querySelectorAll('.naNoble3d__TabPanel:not(#tab-search) .naNoble3d__ToolCard');
        var matchCount = 0;

        for (var i = 0; i < allCards.length; i += 1) {
            var card = allCards[i];
            var titleEl = card.querySelector('.naNoble3d__ToolTitle');
            var descEl = card.querySelector('.naNoble3d__ToolDescription');
            var titleText = (titleEl ? titleEl.textContent : '').toLowerCase();
            var descText = (descEl ? descEl.textContent : '').toLowerCase();

            if (titleText.indexOf(lowerQuery) === -1 && descText.indexOf(lowerQuery) === -1) {
                continue;
            }

            var clonedCard = card.cloneNode(true);
            var tabName = card.getAttribute('data-tab-name') || '';
            if (tabName) {
                var badge = document.createElement('span');
                badge.className = 'naNoble3d__SearchResultTab';
                badge.textContent = tabName;
                clonedCard.appendChild(badge);
            }

            resultsContainer.appendChild(clonedCard);
            matchCount += 1;
        }

        if (matchCount === 0) {
            var emptyMsg = document.createElement('p');
            emptyMsg.className = 'naNoble3d__EmptyState';
            emptyMsg.textContent = 'No tools found for \u201c' + trimmed + '\u201d';
            resultsContainer.appendChild(emptyMsg);
        }
    }

    function na__Noble3d__RestorePreviousTab() {
        if (naSearchState.lastTabId) {
            Na__Noble3d__ShowTab(naSearchState.lastTabId, naSearchState.lastTabButton);
        } else {
            var firstRegularButton = document.querySelector('.naNoble3d__TabButton:not(.naNoble3d__TabButton--search)');
            if (firstRegularButton) {
                firstRegularButton.click();
            }
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
        var firstTabButton = document.querySelector('.naNoble3d__TabButton:not(.naNoble3d__TabButton--search)');
        if (firstTabButton) {
            firstTabButton.click();
        }

        var searchInput = document.getElementById('naNoble3dSearchInput');
        if (searchInput) {
            searchInput.addEventListener('input', function() {
                Na__Noble3d__SearchTools(this.value);
            });
        }
    });

    window.Na__Noble3d__ShowTab = Na__Noble3d__ShowTab;
    window.Na__Noble3d__ShowSearchTab = Na__Noble3d__ShowSearchTab;
    window.Na__Noble3d__RunCommand = Na__Noble3d__RunCommand;
    window.Na__Noble3d__SearchTools = Na__Noble3d__SearchTools;

    // endregion -------------------------------------------------------------------


    // =============================================================================
    // END OF FILE
    // =============================================================================
})();
