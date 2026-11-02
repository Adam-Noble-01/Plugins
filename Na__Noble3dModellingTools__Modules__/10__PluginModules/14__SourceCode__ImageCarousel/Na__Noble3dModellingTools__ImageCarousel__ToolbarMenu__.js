// =============================================================================
// NA NOBLE3D MODELLING TOOLS - IMAGE VIEWER - TOOLBAR MENU
//
// FILE       : Na__Noble3dModellingTools__ImageCarousel__ToolbarMenu__.js
// PURPOSE    : The top bar's nesting. The home row shows the folder, the
//              toolsets (View, Measure) and Markup. A toolset's button swaps
//              the row for that set's tools; Back or Esc returns to home.
//
// DESIGN     : Knows nothing about the tools. They keep their own buttons,
//              ids and click handlers wherever those buttons now sit, and
//              only their --active class is read here, by watching the bar:
//                - a set holding a tool that is on shows it on its home button
//                - a tool switched on by its shortcut (C for Count) opens its
//                  set, so its related buttons are in view
//              A set stays open after a press, so the next tool in it is one
//              click away. Moving to another set never stops a running tool.
//
// =============================================================================

(function() {
    'use strict';

    // -------------------------------------------------------------------------
    // REGION | State
    // -------------------------------------------------------------------------

    var NA_ACTIVE_CLASS = 'naImageViewer__Btn--active';
    var NA_HOLDS_CLASS  = 'naImageViewer__Tile--holdsActive';
    var NA_SHOWN_CLASS  = 'naImageViewer__ToolRow--shown';

    var na_bar     = null;
    var na_home    = null;
    var na_sets    = {};      // set name -> its row
    var na_openers = {};      // set name -> its button on the home row
    var na_open    = null;    // the open set's name, null on the home row
    var na_wasOn   = [];      // tools that were on at the last look

    // endregion ---------------------------------------------------------------


    // -------------------------------------------------------------------------
    // REGION | Showing A Row
    // -------------------------------------------------------------------------

    function Na__ImageViewerToolbar__Show(name) {
        var target = name && na_sets[name] ? name : null;
        if (target === na_open) return;
        na_open = target;
        Na__ImageViewerToolbar__SetClass(na_home, NA_SHOWN_CLASS, !na_open);
        Object.keys(na_sets).forEach(function(key) {
            Na__ImageViewerToolbar__SetClass(na_sets[key], NA_SHOWN_CLASS, key === na_open);
            na_openers[key].setAttribute('aria-expanded', key === na_open ? 'true' : 'false');
        });
    }

    // A class set to what it already is still counts as a change to the
    // observer below, which would then wake itself for ever.
    function Na__ImageViewerToolbar__SetClass(el, name, on) {
        if (el.classList.contains(name) !== on) el.classList.toggle(name, on);
    }

    // endregion ---------------------------------------------------------------


    // -------------------------------------------------------------------------
    // REGION | Following The Tools
    // -------------------------------------------------------------------------

    function Na__ImageViewerToolbar__ToolsOn() {
        return Array.prototype.slice.call(na_bar.querySelectorAll('.' + NA_ACTIVE_CLASS));
    }

    function Na__ImageViewerToolbar__Sync() {
        var on = Na__ImageViewerToolbar__ToolsOn();
        Object.keys(na_sets).forEach(function(key) {
            var holds = on.some(function(tool) { return na_sets[key].contains(tool); });
            Na__ImageViewerToolbar__SetClass(na_openers[key], NA_HOLDS_CLASS, holds);
        });
        on.forEach(function(tool) {
            if (na_wasOn.indexOf(tool) !== -1) return;
            var row = tool.closest('[data-toolset]');
            if (row) Na__ImageViewerToolbar__Show(row.getAttribute('data-toolset'));
        });
        na_wasOn = on;
    }

    // Esc belongs to a running tool first; with none running it steps back here.
    function Na__ImageViewerToolbar__OnKeyCapture(e) {
        if (e.key !== 'Escape' || !na_open) return;
        if (e.target && (e.target.tagName === 'INPUT' || e.target.tagName === 'TEXTAREA' || e.target.tagName === 'SELECT')) return;
        if (Na__ImageViewerToolbar__ToolsOn().length) return;
        Na__ImageViewerToolbar__Show(null);
    }

    // endregion ---------------------------------------------------------------


    // -------------------------------------------------------------------------
    // REGION | Setting Up
    // -------------------------------------------------------------------------

    // The folder button leads until there are photos to look at.
    function Na__ImageViewerToolbar__WatchPhotos() {
        var thumbs = document.getElementById('naImageViewer_thumbs');
        var choose = document.getElementById('naImageViewer_btnChoose');
        if (!thumbs || !choose) return;
        function refresh() { Na__ImageViewerToolbar__SetClass(choose, 'naImageViewer__Btn--primary', !thumbs.children.length); }
        new MutationObserver(refresh).observe(thumbs, { childList: true });
        refresh();
    }

    // If the bar wraps to another line the canvas changes shape with no window resize.
    function Na__ImageViewerToolbar__WatchHeight() {
        if (!window.ResizeObserver) return;
        var height = na_bar.offsetHeight;
        new ResizeObserver(function() {
            if (na_bar.offsetHeight === height) return;
            height = na_bar.offsetHeight;
            if (window.Na__ImageViewer__Core) window.Na__ImageViewer__Core.resize();
        }).observe(na_bar);
    }

    function Na__ImageViewerToolbar__Init() {
        na_bar  = document.getElementById('naImageViewer_toolbar');
        na_home = document.getElementById('naImageViewer_toolHome');
        if (!na_bar || !na_home) return;

        Array.prototype.forEach.call(na_bar.querySelectorAll('[data-toolset]'), function(row) {
            var name = row.getAttribute('data-toolset');
            var opener = na_bar.querySelector('[data-toolset-open="' + name + '"]');
            if (!opener) return;
            na_sets[name] = row;
            na_openers[name] = opener;
            opener.addEventListener('click', function() { Na__ImageViewerToolbar__Show(name); });
            row.querySelector('[data-toolset-back]').addEventListener('click', function() { Na__ImageViewerToolbar__Show(null); });
        });

        new MutationObserver(Na__ImageViewerToolbar__Sync).observe(na_bar, { subtree: true, attributes: true, attributeFilter: ['class'] });
        window.addEventListener('keydown', Na__ImageViewerToolbar__OnKeyCapture, true);
        Na__ImageViewerToolbar__WatchPhotos();
        Na__ImageViewerToolbar__WatchHeight();
        Na__ImageViewerToolbar__Sync();
    }

    window.Na__ImageViewer__ToolbarMenu = {
        open: Na__ImageViewerToolbar__Show,
        home: function() { Na__ImageViewerToolbar__Show(null); },
        inspect: function() {
            return {
                open: na_open,
                on: Na__ImageViewerToolbar__ToolsOn().map(function(tool) { return tool.id; }),
                holding: Object.keys(na_sets).filter(function(key) { return na_openers[key].classList.contains(NA_HOLDS_CLASS); })
            };
        }
    };

    if (document.readyState === 'loading') {
        document.addEventListener('DOMContentLoaded', Na__ImageViewerToolbar__Init);
    } else {
        Na__ImageViewerToolbar__Init();
    }

    // endregion ---------------------------------------------------------------

    // =============================================================================
    // END OF FILE
    // =============================================================================

})();
