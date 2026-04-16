/* ----------------------------------------------------------------- */
/* REGION | Na Edge Util - UI Helpers                                */
/* ----------------------------------------------------------------- */

(function() {
    'use strict';

/* ----------------------------------------------------------------- */
/* REGION | Tab Switching                                            */
/* ----------------------------------------------------------------- */

    function naShowTab(tabId, button) {
        var tabs = document.querySelectorAll('.naTabContent');
        for (var i = 0; i < tabs.length; i += 1) {
            tabs[i].classList.remove('naTabContent--active');
        }

        var buttons = document.querySelectorAll('.naTabBtn');
        for (var j = 0; j < buttons.length; j += 1) {
            buttons[j].classList.remove('naTabBtn--active');
        }

        var targetTab = document.getElementById('tab-' + tabId);
        if (targetTab) {
            targetTab.classList.add('naTabContent--active');
        }

        if (button) {
            button.classList.add('naTabBtn--active');
        }
    }

/* endregion ----------------------------------------------------------------- */

/* ----------------------------------------------------------------- */
/* REGION | Repair Corner - Max Gap Input                            */
/* ----------------------------------------------------------------- */

    function Na__EdgeTools__ReadCornerMaxGapMm() {
        var input = document.getElementById('naRepairCornerMaxGapMm');
        if (!input) {
            return 100;
        }

        var numericValue = parseFloat(input.value);
        if (isNaN(numericValue) || numericValue < 1) {
            numericValue = 1;
        }

        input.value = String(numericValue);
        return numericValue;
    }

    function Na__EdgeTools__PersistCornerMaxGapMm() {
        if (!window.sketchup || !window.sketchup.set_repair_corner_max_gap_mm) {
            return;
        }

        var maxGapMm = Na__EdgeTools__ReadCornerMaxGapMm();
        window.sketchup.set_repair_corner_max_gap_mm(maxGapMm);
    }

/* endregion ----------------------------------------------------------------- */

/* ----------------------------------------------------------------- */
/* REGION | Chamfer Corner - Inputs and Toggle                       */
/* ----------------------------------------------------------------- */

    function Na__EdgeTools__ReadChamferSizeMm() {
        var input = document.getElementById('naChamferSizeMm');
        if (!input) {
            return 20;
        }

        var numericValue = parseFloat(input.value);
        if (isNaN(numericValue) || numericValue < 0) {
            numericValue = 0;
        }

        input.value = String(numericValue);
        return numericValue;
    }

    function Na__EdgeTools__ReadChamferBuildCornersEnabled() {
        var toggle = document.getElementById('naChamferBuildCornersEnabled');
        return !!(toggle && toggle.checked);
    }

    function Na__EdgeTools__ReadChamferBuildCornerMaxGapMm() {
        var input = document.getElementById('naChamferBuildCornerMaxGapMm');
        if (!input) {
            return 100;
        }

        var numericValue = parseFloat(input.value);
        if (isNaN(numericValue) || numericValue < 1) {
            numericValue = 1;
        }

        input.value = String(numericValue);
        return numericValue;
    }

    function Na__EdgeTools__ToggleChamferBuildCornerConfig() {
        var panel = document.getElementById('naChamferBuildCornerConfig');
        if (!panel) {
            return;
        }

        panel.style.display = Na__EdgeTools__ReadChamferBuildCornersEnabled() ? 'block' : 'none';
    }

    function Na__EdgeTools__PersistChamferSizeMm() {
        if (!window.sketchup || !window.sketchup.set_chamfer_size_mm) {
            return;
        }

        window.sketchup.set_chamfer_size_mm(Na__EdgeTools__ReadChamferSizeMm());
    }

    function Na__EdgeTools__PersistChamferBuildCornersEnabled() {
        Na__EdgeTools__ToggleChamferBuildCornerConfig();

        if (!window.sketchup || !window.sketchup.set_chamfer_build_corners_enabled) {
            return;
        }

        window.sketchup.set_chamfer_build_corners_enabled(
            Na__EdgeTools__ReadChamferBuildCornersEnabled()
        );
    }

    function Na__EdgeTools__PersistChamferBuildCornerMaxGapMm() {
        if (!window.sketchup || !window.sketchup.set_chamfer_build_corner_max_gap_mm) {
            return;
        }

        window.sketchup.set_chamfer_build_corner_max_gap_mm(
            Na__EdgeTools__ReadChamferBuildCornerMaxGapMm()
        );
    }

/* endregion ----------------------------------------------------------------- */

/* ----------------------------------------------------------------- */
/* REGION | SketchUp Bridge - Edge Tool Runners                      */
/* ----------------------------------------------------------------- */

    function Na__EdgeTools__RunEdgeCleaner() {
        if (window.sketchup && window.sketchup.run_edge_cleaner) {
            window.sketchup.run_edge_cleaner();
        }
    }

    function Na__EdgeTools__RunRepairCorners() {
        if (window.sketchup && window.sketchup.run_repair_corners) {
            var maxGapMm = Na__EdgeTools__ReadCornerMaxGapMm();
            window.sketchup.run_repair_corners(maxGapMm);
        }
    }

    function Na__EdgeTools__RunInsertPointsAlongPath() {
        if (window.sketchup && window.sketchup.run_insert_points_along_path) {
            window.sketchup.run_insert_points_along_path();
        }
    }

    function Na__EdgeTools__RunChamferEdgeCorners() {
        if (window.sketchup && window.sketchup.run_chamfer_edge_corners) {
            window.sketchup.run_chamfer_edge_corners(
                Na__EdgeTools__ReadChamferSizeMm(),
                Na__EdgeTools__ReadChamferBuildCornersEnabled(),
                Na__EdgeTools__ReadChamferBuildCornerMaxGapMm()
            );
        }
    }

/* endregion ----------------------------------------------------------------- */

/* ----------------------------------------------------------------- */
/* REGION | DOM Initialisation and Window Exports                    */
/* ----------------------------------------------------------------- */

    document.addEventListener('DOMContentLoaded', function() {
        var repairGapInput = document.getElementById('naRepairCornerMaxGapMm');
        if (repairGapInput) {
            repairGapInput.addEventListener('change', Na__EdgeTools__PersistCornerMaxGapMm);
        }

        var chamferSizeInput = document.getElementById('naChamferSizeMm');
        if (chamferSizeInput) {
            chamferSizeInput.addEventListener('change', Na__EdgeTools__PersistChamferSizeMm);
        }

        var chamferBuildToggle = document.getElementById('naChamferBuildCornersEnabled');
        if (chamferBuildToggle) {
            chamferBuildToggle.addEventListener('change', Na__EdgeTools__PersistChamferBuildCornersEnabled);
        }

        var chamferBuildMaxGapInput = document.getElementById('naChamferBuildCornerMaxGapMm');
        if (chamferBuildMaxGapInput) {
            chamferBuildMaxGapInput.addEventListener('change', Na__EdgeTools__PersistChamferBuildCornerMaxGapMm);
        }

        Na__EdgeTools__ToggleChamferBuildCornerConfig();
    });

    window.naShowTab = naShowTab;
    window.Na__EdgeTools__RunEdgeCleaner = Na__EdgeTools__RunEdgeCleaner;
    window.Na__EdgeTools__RunRepairCorners = Na__EdgeTools__RunRepairCorners;
    window.Na__EdgeTools__RunInsertPointsAlongPath = Na__EdgeTools__RunInsertPointsAlongPath;
    window.Na__EdgeTools__RunChamferEdgeCorners = Na__EdgeTools__RunChamferEdgeCorners;
    window.Na__EdgeTools__PersistCornerMaxGapMm = Na__EdgeTools__PersistCornerMaxGapMm;
    window.Na__EdgeTools__PersistChamferSizeMm = Na__EdgeTools__PersistChamferSizeMm;
    window.Na__EdgeTools__PersistChamferBuildCornersEnabled = Na__EdgeTools__PersistChamferBuildCornersEnabled;
    window.Na__EdgeTools__PersistChamferBuildCornerMaxGapMm = Na__EdgeTools__PersistChamferBuildCornerMaxGapMm;

/* endregion ----------------------------------------------------------------- */

})();

/* endregion ----------------------------------------------------------------- */
