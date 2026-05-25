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
        var levelNumber = Number(node.level || 0);
        var nodeClasses = ['naEntityTree__Node'];
        var childNodes = Array.isArray(node.children) ? node.children : [];
        var selectedBadge = '';

        if (node.selected) {
            nodeClasses.push('naEntityTree__Node--selected');
            selectedBadge = '<span class="naEntityTree__Badge naEntityTree__Badge--selected">Selected</span>';
        }

        if (node.node_type === 'message') {
            nodeClasses.push('naEntityTree__Node--message');
        }

        return [
            '<section class="' + nodeClasses.join(' ') + '" style="--naEntityTree__Level:' + levelNumber + '">',
                '<header class="naEntityTree__NodeHeader">',
                    '<div class="naEntityTree__NodeTopLine">',
                        '<span class="naEntityTree__Badge">Level ' + levelNumber + '</span>',
                        '<span class="naEntityTree__Badge">' + Na__SelectedHierarchyTagReporter__EscapeHtml(node.role || 'Entity') + '</span>',
                        '<span class="naEntityTree__Badge">Tag: ' + Na__SelectedHierarchyTagReporter__EscapeHtml(node.tag_name || 'n/a') + '</span>',
                        selectedBadge,
                    '</div>',
                    '<p class="naEntityTree__NodeText">' + Na__SelectedHierarchyTagReporter__EscapeHtml(node.display_text || node.title || '') + '</p>',
                '</header>',
                Na__SelectedHierarchyTagReporter__RenderLooseSummary(node.loose_geometry_summary),
                childNodes.length ? '<div class="naEntityTree__Children">' + childNodes.map(Na__SelectedHierarchyTagReporter__RenderNode).join('') + '</div>' : '',
            '</section>'
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
        var markdownText = Na__SelectedHierarchyTagReporter__BuildMarkdownReport(
            Na__SelectedHierarchyTagReporter__State.reportData || {}
        );

        Na__SelectedHierarchyTagReporter__CopyTextToClipboard(markdownText)
            .then(function() {
                Na__SelectedHierarchyTagReporter__SetStatus('Copied current tree to clipboard as Markdown.', 'success');
            })
            .catch(function(error) {
                Na__SelectedHierarchyTagReporter__SetStatus('Clipboard copy failed: ' + error.message, 'error');
            });
    }

    function Na__SelectedHierarchyTagReporter__BuildMarkdownReport(reportData) {
        var markdownLines = [
            '# Entity Tree Reporter',
            '',
            '- Generated: ' + String(reportData.generated_at || 'n/a'),
            '- Selection: ' + String(reportData.selection_count || 0) + ' item(s)',
            '- Mode: ' + (reportData.include_siblings ? 'Selected level with siblings' : 'Selected only'),
            '',
            String(reportData.summary || ''),
            '',
            '## Tree'
        ];

        var nodes = Array.isArray(reportData.nodes) ? reportData.nodes : [];
        nodes.forEach(function(node) {
            Na__SelectedHierarchyTagReporter__AppendMarkdownNode(markdownLines, node);
        });

        return markdownLines.join('\n');
    }

    function Na__SelectedHierarchyTagReporter__AppendMarkdownNode(markdownLines, node) {
        var levelNumber = Number(node.level || 0);
        var indentText = new Array(levelNumber + 1).join('  ');
        var selectedText = node.selected ? ' **[Selected]**' : '';
        var nodeText = String(node.display_text || node.title || '').replace(/\s+/g, ' ').trim();

        markdownLines.push(indentText + '- Level ' + levelNumber + ' | ' + String(node.role || 'Entity') + ' | ' + nodeText + selectedText);

        if (node.loose_geometry_summary) {
            markdownLines.push(
                indentText +
                '  - Lowest Level Loose Geometry | Items: ' +
                String(node.loose_geometry_summary.item_count || 0) +
                ' | Types: ' +
                String(node.loose_geometry_summary.type_summary || '') +
                ' | Tags: ' +
                String(node.loose_geometry_summary.tag_summary || '')
            );
        }

        (Array.isArray(node.children) ? node.children : []).forEach(function(childNode) {
            Na__SelectedHierarchyTagReporter__AppendMarkdownNode(markdownLines, childNode);
        });
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
        var refreshButton = Na__SelectedHierarchyTagReporter__Element('naEntityTreeRefresh');
        var printButton = Na__SelectedHierarchyTagReporter__Element('naEntityTreePrint');
        var copyMarkdownButton = Na__SelectedHierarchyTagReporter__Element('naEntityTreeCopyMarkdown');

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
