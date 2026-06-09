(function() {
    'use strict';

    // =============================================================================
    // NA NOBLE3D MODELLING TOOLS - SELECTED HIERARCHY TAG REPORTER - UI BRIDGE
    // =============================================================================

    var Na__SelectedHierarchyTagReporter__State = {
        reportData: null,
        includeSiblings: false
    };

    function Na__SelectedHierarchyTagReporter__Element(elementId) {
        return document.getElementById(elementId);
    }

    function Na__SelectedHierarchyTagReporter__EscapeHtml(rawValue) {
        return String(rawValue || '')
            .replace(/&/g, '&amp;')
            .replace(/</g, '&lt;')
            .replace(/>/g, '&gt;')
            .replace(/"/g, '&quot;')
            .replace(/'/g, '&#39;');
    }

    function Na__SelectedHierarchyTagReporter__SetText(elementId, textValue) {
        var element = Na__SelectedHierarchyTagReporter__Element(elementId);
        if (!element) {
            return;
        }

        element.textContent = String(textValue || '');
    }

    function Na__SelectedHierarchyTagReporter__SetStatus(statusText, statusVariant) {
        var statusElement = Na__SelectedHierarchyTagReporter__Element('naEntityTreeStatus');
        if (!statusElement) {
            return;
        }

        statusElement.textContent = String(statusText || '');
        statusElement.className = 'naEntityTree__Status naEntityTree__Status--' + String(statusVariant || 'info');
    }

    function Na__SelectedHierarchyTagReporter__SetReportData(reportData) {
        Na__SelectedHierarchyTagReporter__State.reportData = reportData || {};
        Na__SelectedHierarchyTagReporter__State.includeSiblings = !!Na__SelectedHierarchyTagReporter__State.reportData.include_siblings;

        Na__SelectedHierarchyTagReporter__SyncControls();
        Na__SelectedHierarchyTagReporter__RenderMeta();
        Na__SelectedHierarchyTagReporter__RenderTree();
        Na__SelectedHierarchyTagReporter__SetStatus('Hierarchy report ready.', 'success');
    }

    function Na__SelectedHierarchyTagReporter__SyncControls() {
        var includeSiblingsCheckbox = Na__SelectedHierarchyTagReporter__Element('naEntityTreeIncludeSiblings');
        if (includeSiblingsCheckbox) {
            includeSiblingsCheckbox.checked = Na__SelectedHierarchyTagReporter__State.includeSiblings;
        }
    }

    function Na__SelectedHierarchyTagReporter__RenderMeta() {
        var reportData = Na__SelectedHierarchyTagReporter__State.reportData || {};
        var selectionCount = Number(reportData.selection_count || 0);

        Na__SelectedHierarchyTagReporter__SetText('naEntityTreeSelectionCount', selectionCount + ' item(s)');
        Na__SelectedHierarchyTagReporter__SetText(
            'naEntityTreeMode',
            reportData.include_siblings ? 'Selected level with siblings' : 'Selected only'
        );
        Na__SelectedHierarchyTagReporter__SetText('naEntityTreeGeneratedAt', reportData.generated_at || 'n/a');
        Na__SelectedHierarchyTagReporter__SetText('naEntityTreeSummary', reportData.summary || '');
    }

    function Na__SelectedHierarchyTagReporter__RenderTree() {
        var hostElement = Na__SelectedHierarchyTagReporter__Element('naEntityTreeHost');
        var reportData = Na__SelectedHierarchyTagReporter__State.reportData || {};
        var nodes = Array.isArray(reportData.nodes) ? reportData.nodes : [];

        if (!hostElement) {
            return;
        }

        if (!nodes.length) {
            hostElement.innerHTML = '<p class="naEntityTree__Summary">No hierarchy data available.</p>';
            return;
        }

        hostElement.innerHTML = nodes
            .map(function(node) {
                return Na__SelectedHierarchyTagReporter__RenderNode(node);
            })
            .join('');
    }

    function Na__SelectedHierarchyTagReporter__RenderNode(node) {
        if (node.node_type === 'grouped_instances') {
            return Na__SelectedHierarchyTagReporter__RenderGroupedInstancesNode(node);
        }

        var levelNumber = Number(node.level || 0);
        var nodeClasses = ['naEntityTree__Node'];
        var childNodes  = Array.isArray(node.children) ? node.children : [];
        var topBadges   = [];

        if (node.selected) {
            nodeClasses.push('naEntityTree__Node--selected');
        }

        if (node.node_type === 'message') {
            nodeClasses.push('naEntityTree__Node--message');
        }

        topBadges.push('<span class="naEntityTree__Badge">Level ' + levelNumber + '</span>');
        topBadges.push('<span class="naEntityTree__Badge">' + Na__SelectedHierarchyTagReporter__EscapeHtml(node.role || 'Entity') + '</span>');
        topBadges.push('<span class="naEntityTree__Badge">Tag: ' + Na__SelectedHierarchyTagReporter__EscapeHtml(node.tag_name || 'n/a') + '</span>');

        var typeLabel = node.entity_type_label;
        if (typeLabel) {
            var typeMod = typeLabel === 'Group' ? 'group' : 'component';
            topBadges.push('<span class="naEntityTree__Badge naEntityTree__Badge--' + typeMod + '">' + Na__SelectedHierarchyTagReporter__EscapeHtml(typeLabel) + '</span>');
        }

        var isSolid = node.is_solid;
        if (isSolid === true || isSolid === false) {
            var solidLabel = isSolid ? 'Solid' : 'Non-Solid';
            var solidMod   = isSolid ? 'solid' : 'non-solid';
            topBadges.push('<span class="naEntityTree__Badge naEntityTree__Badge--' + solidMod + '">' + solidLabel + '</span>');
        }

        if (node.selected) {
            topBadges.push('<span class="naEntityTree__Badge naEntityTree__Badge--selected">Selected</span>');
        }

        return [
            '<section class="' + nodeClasses.join(' ') + '" style="--naEntityTree__Level:' + levelNumber + '">',
                '<header class="naEntityTree__NodeHeader">',
                    '<div class="naEntityTree__NodeTopLine">',
                        topBadges.join(''),
                    '</div>',
                    '<p class="naEntityTree__NodeText">' + Na__SelectedHierarchyTagReporter__EscapeHtml(node.display_text || node.title || '') + '</p>',
                '</header>',
                Na__SelectedHierarchyTagReporter__RenderLooseSummary(node.loose_geometry_summary),
                childNodes.length ? '<div class="naEntityTree__Children">' + childNodes.map(Na__SelectedHierarchyTagReporter__RenderNode).join('') + '</div>' : '',
            '</section>'
        ].join('');
    }

    function Na__SelectedHierarchyTagReporter__RenderGroupedInstancesNode(node) {
        var levelNumber  = Number(node.level || 0);
        var childNodes   = Array.isArray(node.children) ? node.children : [];
        var count        = Number(node.instance_count || 0);
        var summaryBadges = [];

        summaryBadges.push('<span class="naEntityTree__Badge">Level ' + levelNumber + '</span>');
        summaryBadges.push('<span class="naEntityTree__Badge naEntityTree__Badge--grouped">' + count.toLocaleString() + ' Identical Instances</span>');

        var typeLabel = node.entity_type_label;
        if (typeLabel) {
            var typeMod = typeLabel === 'Group' ? 'group' : 'component';
            summaryBadges.push('<span class="naEntityTree__Badge naEntityTree__Badge--' + typeMod + '">' + Na__SelectedHierarchyTagReporter__EscapeHtml(typeLabel) + '</span>');
        }

        var isSolid = node.is_solid;
        if (isSolid === true || isSolid === false) {
            var solidLabel = isSolid ? 'Solid' : 'Non-Solid';
            var solidMod   = isSolid ? 'solid' : 'non-solid';
            summaryBadges.push('<span class="naEntityTree__Badge naEntityTree__Badge--' + solidMod + '">' + solidLabel + '</span>');
        }

        if (node.selected) {
            summaryBadges.push('<span class="naEntityTree__Badge naEntityTree__Badge--selected">Contains Selected</span>');
        }

        var defName = Na__SelectedHierarchyTagReporter__EscapeHtml(node.definition_name || '(unnamed)');

        return [
            '<details class="naEntityTree__GroupedInstances" style="--naEntityTree__Level:' + levelNumber + '">',
                '<summary class="naEntityTree__GroupedSummary">',
                    '<div class="naEntityTree__NodeTopLine">',
                        summaryBadges.join(''),
                    '</div>',
                    '<p class="naEntityTree__NodeText">Definition: &ldquo;' + defName + '&rdquo; &mdash; expand to view all ' + count.toLocaleString() + ' instances</p>',
                '</summary>',
                childNodes.length ? '<div class="naEntityTree__Children naEntityTree__Children--grouped">' + childNodes.map(Na__SelectedHierarchyTagReporter__RenderNode).join('') + '</div>' : '',
            '</details>'
        ].join('');
    }

    function Na__SelectedHierarchyTagReporter__RenderLooseSummary(summary) {
        if (!summary) {
            return '';
        }

        return [
            '<p class="naEntityTree__LooseSummary">',
                '<strong>Lowest Level Loose Geometry</strong>',
                ' | Items: ' + Na__SelectedHierarchyTagReporter__EscapeHtml(summary.item_count),
                ' | Types: ' + Na__SelectedHierarchyTagReporter__EscapeHtml(summary.type_summary),
                ' | Tags: ' + Na__SelectedHierarchyTagReporter__EscapeHtml(summary.tag_summary),
            '</p>'
        ].join('');
    }

    function Na__SelectedHierarchyTagReporter__CurrentIncludeSiblingsValue() {
        var includeSiblingsCheckbox = Na__SelectedHierarchyTagReporter__Element('naEntityTreeIncludeSiblings');
        return !!(includeSiblingsCheckbox && includeSiblingsCheckbox.checked);
    }

    function Na__SelectedHierarchyTagReporter__RefreshFromRuby() {
        var includeSiblings = Na__SelectedHierarchyTagReporter__CurrentIncludeSiblingsValue();

        if (!window.sketchup || !window.sketchup.refresh_report) {
            Na__SelectedHierarchyTagReporter__SetStatus('SketchUp refresh bridge unavailable.', 'error');
            return;
        }

        Na__SelectedHierarchyTagReporter__SetStatus('Refreshing hierarchy report...', 'info');
        window.sketchup.refresh_report(includeSiblings);
    }

    function Na__SelectedHierarchyTagReporter__PrintConsoleReport() {
        var includeSiblings = Na__SelectedHierarchyTagReporter__CurrentIncludeSiblingsValue();

        if (!window.sketchup || !window.sketchup.print_console_report) {
            Na__SelectedHierarchyTagReporter__SetStatus('SketchUp print bridge unavailable.', 'error');
            return;
        }

        Na__SelectedHierarchyTagReporter__SetStatus('Printing hierarchy report...', 'info');
        window.sketchup.print_console_report(includeSiblings);
    }

    function Na__SelectedHierarchyTagReporter__CopyMarkdownReport() {
        var treeText = Na__SelectedHierarchyTagReporter__BuildMarkdownReport(
            Na__SelectedHierarchyTagReporter__State.reportData || {}
        );

        Na__SelectedHierarchyTagReporter__CopyTextToClipboard(treeText)
            .then(function() {
                Na__SelectedHierarchyTagReporter__SetStatus('Copied tree to clipboard as plain text.', 'success');
            })
            .catch(function(error) {
                Na__SelectedHierarchyTagReporter__SetStatus('Clipboard copy failed: ' + error.message, 'error');
            });
    }

    function Na__SelectedHierarchyTagReporter__DownloadTreeText() {
        var treeText = Na__SelectedHierarchyTagReporter__BuildMarkdownReport(
            Na__SelectedHierarchyTagReporter__State.reportData || {}
        );

        var reportData = Na__SelectedHierarchyTagReporter__State.reportData || {};
        var timestamp  = String(reportData.generated_at || 'report').replace(/[^a-zA-Z0-9_-]/g, '_');
        var filename   = 'EntityTree_' + timestamp + '.txt';

        try {
            var blob = new Blob([treeText], { type: 'text/plain;charset=utf-8' });
            var url  = URL.createObjectURL(blob);
            var link = document.createElement('a');
            link.href     = url;
            link.download = filename;
            link.style.display = 'none';
            document.body.appendChild(link);
            link.click();
            document.body.removeChild(link);
            URL.revokeObjectURL(url);
            Na__SelectedHierarchyTagReporter__SetStatus('Downloaded: ' + filename, 'success');
        } catch (error) {
            Na__SelectedHierarchyTagReporter__SetStatus('Download failed: ' + error.message, 'error');
        }
    }

    function Na__SelectedHierarchyTagReporter__BuildMarkdownReport(reportData) {
        var RULE = '--------------------------------------------------------------------------------';
        var lines = [
            'Entity Tree Reporter',
            RULE,
            'Generated : ' + String(reportData.generated_at || 'n/a'),
            'Selection : ' + String(reportData.selection_count || 0) + ' item(s)',
            'Mode      : ' + (reportData.include_siblings ? 'Selected level with siblings' : 'Selected only'),
            '',
            String(reportData.summary || ''),
            RULE,
            ''
        ];

        var nodes = Array.isArray(reportData.nodes) ? reportData.nodes : [];
        nodes.forEach(function(node, idx) {
            Na__SelectedHierarchyTagReporter__AppendTreeNode(lines, node, '', idx === nodes.length - 1);
        });

        return lines.join('\n');
    }

    // Returns the plain-text label for one tree node — no markdown syntax whatsoever.
    function Na__SelectedHierarchyTagReporter__PlainNodeText(node) {
        var nodeType  = String(node.node_type || '');
        var typeLabel = node.entity_type_label ? String(node.entity_type_label) : null;
        var rawTag    = String(node.tag_name || '');
        var tagPart   = (rawTag && rawTag !== 'n/a' && rawTag.toLowerCase() !== 'untagged')
            ? '  [Tag: ' + rawTag + ']' : '';
        var solidPart = node.is_solid === true  ? '  [Solid]'
                      : node.is_solid === false ? '  [Non-Solid]' : '';
        var selPart   = node.selected ? '  [SELECTED]' : '';

        if (nodeType === 'model') {
            return 'Model Root';
        }

        if (nodeType === 'message') {
            return '(' + String(node.display_text || node.title || '') + ')';
        }

        if (nodeType === 'grouped_instances') {
            var count   = Number(node.instance_count || 0);
            var defName = String(node.definition_name || '(unnamed)');
            var label   = typeLabel || 'Container';
            var selG    = node.selected ? '  [CONTAINS SELECTED]' : '';
            return 'x' + count.toLocaleString() + ' ' + label + ': ' + defName + solidPart + selG;
        }

        if (typeLabel === 'Group') {
            var name = String(node.entity_name || '(unnamed)');
            var role = String(node.role || '');
            var rp   = (role && role !== 'Child Object' && role !== 'Instance' && role !== 'Sibling Object')
                ? '[' + role + ']  ' : '';
            return rp + 'Group: ' + name + tagPart + solidPart + selPart;
        }

        if (typeLabel === 'Component') {
            var defN  = String(node.definition_name || '(unnamed)');
            var roleC = String(node.role || '');
            var rpC   = (roleC && roleC !== 'Child Object' && roleC !== 'Instance' && roleC !== 'Sibling Object')
                ? '[' + roleC + ']  ' : '';
            return rpC + 'Component: ' + defN + tagPart + solidPart + selPart;
        }

        return String(node.display_text || node.title || '');
    }

    // Recursive plain-text tree renderer using ASCII box-drawing connectors.
    // prefix    : continuation string from all ancestors (pipes and spaces)
    // isLast    : whether this node is the last sibling at its level
    // isRoot    : true only for the top-level model root node (no connector drawn)
    function Na__SelectedHierarchyTagReporter__AppendTreeNode(lines, node, prefix, isLast, isRoot) {
        var connector;
        var childPrefix;

        if (isRoot) {
            connector   = '';            // root prints its own label flush-left
            childPrefix = '';            // its children start with no ancestor pipe
        } else {
            connector   = isLast ? '\u2514\u2500\u2500 ' : '\u251c\u2500\u2500 ';
            childPrefix = prefix + (isLast ? '    ' : '\u2502   ');
        }

        lines.push(prefix + connector + Na__SelectedHierarchyTagReporter__PlainNodeText(node));

        if (node.node_type === 'grouped_instances') {
            return; // summary line only — do not recurse into individual instances
        }

        var children    = Array.isArray(node.children) ? node.children : [];
        var hasGeometry = !!node.loose_geometry_summary;

        children.forEach(function(child, idx) {
            var childIsLast = !hasGeometry && (idx === children.length - 1);
            Na__SelectedHierarchyTagReporter__AppendTreeNode(lines, child, childPrefix, childIsLast, false);
        });

        if (hasGeometry) {
            var s = node.loose_geometry_summary;
            var geoLine = 'Geometry: ' + Number(s.item_count || 0).toLocaleString() +
                ' items (' + String(s.type_summary || '') + ')';
            lines.push(childPrefix + '\u2514\u2500\u2500 ' + geoLine);
        }
    }

    function Na__SelectedHierarchyTagReporter__CopyTextToClipboard(textValue) {
        if (navigator.clipboard && navigator.clipboard.writeText) {
            return navigator.clipboard.writeText(textValue);
        }

        return new Promise(function(resolve, reject) {
            var textArea = document.createElement('textarea');
            textArea.value = textValue;
            textArea.setAttribute('readonly', 'readonly');
            textArea.style.position = 'fixed';
            textArea.style.left = '-9999px';
            document.body.appendChild(textArea);
            textArea.select();

            try {
                if (!document.execCommand('copy')) {
                    throw new Error('document.execCommand copy returned false');
                }
                resolve();
            } catch (error) {
                reject(error);
            } finally {
                document.body.removeChild(textArea);
            }
        });
    }

    function Na__SelectedHierarchyTagReporter__RegisterEvents() {
        var includeSiblingsCheckbox = Na__SelectedHierarchyTagReporter__Element('naEntityTreeIncludeSiblings');
        var refreshButton           = Na__SelectedHierarchyTagReporter__Element('naEntityTreeRefresh');
        var printButton             = Na__SelectedHierarchyTagReporter__Element('naEntityTreePrint');
        var copyMarkdownButton      = Na__SelectedHierarchyTagReporter__Element('naEntityTreeCopyMarkdown');
        var downloadButton          = Na__SelectedHierarchyTagReporter__Element('naEntityTreeDownload');

        if (includeSiblingsCheckbox) {
            includeSiblingsCheckbox.addEventListener('change', Na__SelectedHierarchyTagReporter__RefreshFromRuby);
        }

        if (refreshButton) {
            refreshButton.addEventListener('click', Na__SelectedHierarchyTagReporter__RefreshFromRuby);
        }

        if (printButton) {
            printButton.addEventListener('click', Na__SelectedHierarchyTagReporter__PrintConsoleReport);
        }

        if (copyMarkdownButton) {
            copyMarkdownButton.addEventListener('click', Na__SelectedHierarchyTagReporter__CopyMarkdownReport);
        }

        if (downloadButton) {
            downloadButton.addEventListener('click', Na__SelectedHierarchyTagReporter__DownloadTreeText);
        }
    }

    document.addEventListener('DOMContentLoaded', function() {
        Na__SelectedHierarchyTagReporter__RegisterEvents();
        Na__SelectedHierarchyTagReporter__SetReportData(window.Na__SelectedHierarchyTagReporter__InitialData || {});
    });

    window.Na__SelectedHierarchyTagReporter__SetReportData = Na__SelectedHierarchyTagReporter__SetReportData;
    window.Na__SelectedHierarchyTagReporter__SetStatus = Na__SelectedHierarchyTagReporter__SetStatus;

    // =============================================================================
    // END OF FILE
    // =============================================================================
})();
