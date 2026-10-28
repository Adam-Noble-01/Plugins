// overlay_entity.js

document.addEventListener('DOMContentLoaded', () => {
  // Cache DOM elements
  const toggleLabelOverlay   = document.getElementById('toggleLabelOverlay');
  const toggleLeaderLines    = document.getElementById('toggleLeaderLines');
  const toggleZoomFade       = document.getElementById('toggleZoomFade');
  const toggleEntityInfo     = document.getElementById('toggleEntityInfo');
  const toggleTagColors      = document.getElementById("toggleTagColors");

  const fontSizeInput        = document.getElementById("fontSizeInput");
  const fontColorInput       = document.getElementById("fontColorInput");
  const overlayPositionSelect= document.getElementById("overlayPosition");
  const applyOverlayPositionButton = document.getElementById("applyOverlayPosition");

  const angleSlider          = document.getElementById('leaderAngleSlider');
  const angleLabel           = document.getElementById('leaderAngleValue');

  const lengthSlider         = document.getElementById('leaderLengthSlider');   // inches
  const lengthLabel          = document.getElementById('leaderLengthValue');

  const minFadeSlider        = document.getElementById('minFadeSlider');       // feet
  const minFadeValue         = document.getElementById('minFadeValue');

  const fadeDistanceSlider   = document.getElementById('fadeDistanceSlider');  // feet
  const fadeDistanceValue    = document.getElementById('fadeDistanceValue');

  const toggleBackground = document.getElementById("toggleBackground");
  const backgroundColorInput = document.getElementById("backgroundColorInput");

  // Receive settings from Ruby and update form controls
  window.updateSettingsFromSketchUp = (settings) => {
    if (settings.font_size && fontSizeInput) {
      fontSizeInput.value = settings.font_size;
      localStorage.setItem("overlayFontSize", settings.font_size);
    }
    if (settings.font_color && fontColorInput) {
      fontColorInput.value = settings.font_color;
      localStorage.setItem("overlayFontColor", settings.font_color);
    }
    if (typeof settings.show_tag_colors !== "undefined" && toggleTagColors) {
      toggleTagColors.checked = settings.show_tag_colors;
      localStorage.setItem("showTagColors", settings.show_tag_colors);
    }
    if (typeof settings.zoom_aware_fading !== "undefined" && toggleZoomFade) {
      toggleZoomFade.checked = settings.zoom_aware_fading;
      localStorage.setItem("zoomAwareFading", settings.zoom_aware_fading);
    }
    if (typeof settings.show_leader_lines !== "undefined" && toggleLeaderLines) {
      toggleLeaderLines.checked = settings.show_leader_lines;
      localStorage.setItem("showLeaderLines", settings.show_leader_lines);
    }
    if (typeof settings.show_entity_info !== "undefined" && toggleEntityInfo) {
      toggleEntityInfo.checked = settings.show_entity_info;
      localStorage.setItem("showEntityInfo", settings.show_entity_info);
    }
    if (settings.overlay_position && overlayPositionSelect) {
      overlayPositionSelect.value = settings.overlay_position;
    }
    if (settings.draw_mode) {
      const radio = document.querySelector(`input[name="drawMode"][value="${settings.draw_mode}"]`);
      if (radio) {
        radio.checked = true;
        localStorage.setItem("drawMode", settings.draw_mode);
      }
    }
    if (settings.leader_line_angle !== undefined && angleSlider && angleLabel) {
      angleSlider.value = settings.leader_line_angle;
      angleLabel.textContent = `${settings.leader_line_angle}°`;
      localStorage.setItem("leaderLineAngle", settings.leader_line_angle);
    }
    if (settings.leader_line_length !== undefined && lengthSlider && lengthLabel) {
      lengthSlider.value = settings.leader_line_length; // inches
      lengthLabel.textContent = `${settings.leader_line_length}″`;
      localStorage.setItem("leaderLineLength", settings.leader_line_length);
    }
    if (settings.fade_start_distance !== undefined && minFadeSlider && minFadeValue) {
      minFadeSlider.value = settings.fade_start_distance; // feet
      minFadeValue.textContent = `${settings.fade_start_distance}′`;
      localStorage.setItem("minFadeDistanceFeet", settings.fade_start_distance);
    }
    if (settings.fade_end_distance !== undefined && fadeDistanceSlider && fadeDistanceValue) {
      fadeDistanceSlider.value = settings.fade_end_distance; // feet
      fadeDistanceValue.textContent = `${settings.fade_end_distance}′`;
      localStorage.setItem("fadeDistanceFeet", settings.fade_end_distance);
    }
    if (typeof settings.show_area !== "undefined") {
      document.getElementById("showArea").checked = settings.show_area;
    }
    if (typeof settings.show_length !== "undefined") {
      document.getElementById("showLength").checked = settings.show_length;
    }
    if (typeof settings.show_radius !== "undefined") {
      document.getElementById("showRadius").checked = settings.show_radius;
    }
    if (typeof settings.show_segments !== "undefined") {
      document.getElementById("showSegments").checked = settings.show_segments;
    }
    if (typeof settings.show_background !== "undefined" && toggleBackground) {
      toggleBackground.checked = settings.show_background;
      localStorage.setItem("showBackground", settings.show_background);
    }
    if (settings.background_color && backgroundColorInput) {
      backgroundColorInput.value = settings.background_color;
      localStorage.setItem("backgroundColor", settings.background_color);
    } else if (backgroundColorInput) {
      backgroundColorInput.value = localStorage.getItem("backgroundColor") || "#f0f0f0";
    }
  };

  // Optional: request overlay settings from Ruby
  if (window.sketchup?.get_overlay_settings) {
    window.sketchup.get_overlay_settings();
  }

  if (toggleLabelOverlay) {
    const saved = localStorage.getItem('showLabelOverlay');
    toggleLabelOverlay.checked = saved === 'true';

    toggleLabelOverlay.addEventListener('change', () => {
      const isEnabled = toggleLabelOverlay.checked;
      localStorage.setItem('showLabelOverlay', isEnabled);
      if (window.sketchup?.toggle_label_overlay) {
        window.sketchup.toggle_label_overlay(isEnabled);
      }
    });

    // Send initial state to Ruby
    if (window.sketchup?.toggle_label_overlay) {
      window.sketchup.toggle_label_overlay(toggleLabelOverlay.checked);
    }
  }

  // Leader Lines
  if (toggleLeaderLines) {
    const saved = localStorage.getItem('showLeaderLines');
    toggleLeaderLines.checked = saved === null ? true : saved === 'true';

    toggleLeaderLines.addEventListener('change', () => {
      localStorage.setItem('showLeaderLines', toggleLeaderLines.checked);
      sendLabelOverlaySettings();
    });
  }

  // Zoom-Aware Fading
  if (toggleZoomFade) {
    const saved = localStorage.getItem('zoomAwareFading');
    toggleZoomFade.checked = saved === null ? true : saved === 'true';

    toggleZoomFade.addEventListener('change', () => {
      localStorage.setItem('zoomAwareFading', toggleZoomFade.checked);
      sendLabelOverlaySettings();
    });
  }

  // Send all label overlay settings to Ruby
  if (toggleEntityInfo) {
    const saved = localStorage.getItem('showEntityInfo');
    toggleEntityInfo.checked = saved === null ? true : saved === 'true';

    toggleEntityInfo.addEventListener('change', () => {
      const isEnabled = toggleEntityInfo.checked;
      localStorage.setItem('showEntityInfo', isEnabled);
      if (window.sketchup?.update_label_overlay_settings) {
        sendLabelOverlaySettings();
      }
    });
  }

  // Optional component detail visibility toggles
  ["showComponentDefinition", "showComponentInstance", "showComponentVolume"].forEach((id) => {
    const checkbox = document.getElementById(id);
    if (checkbox) {
      // Load from localStorage on startup
      const saved = localStorage.getItem(id);
      checkbox.checked = saved === null ? true : saved === 'true';

      // Save state + send to Ruby when toggled
      checkbox.addEventListener("change", () => {
        localStorage.setItem(id, checkbox.checked);
        sendLabelOverlaySettings();
      });
    }
  });

  ["showComponentDescription"].forEach((id) => {
    const checkbox = document.getElementById(id);
    if (checkbox) {
      const saved = localStorage.getItem(id);
      checkbox.checked = saved === null ? true : saved === 'true';

      checkbox.addEventListener("change", () => {
        localStorage.setItem(id, checkbox.checked);
        sendLabelOverlaySettings();
      });
    }
  });

  ["showTagLabel"].forEach((id) => {
    const checkbox = document.getElementById(id);
    if (checkbox) {
      const saved = localStorage.getItem(id);
      checkbox.checked = saved === null ? true : saved === 'true';

      checkbox.addEventListener("change", () => {
        localStorage.setItem(id, checkbox.checked);
        sendLabelOverlaySettings();
      });
    }
  });

  ["showArea", "showLength", "showRadius", "showSegments"].forEach((id) => {
    const checkbox = document.getElementById(id);
    if (checkbox) {
      const saved = localStorage.getItem(id);
      checkbox.checked = saved === null ? true : saved === 'true';

      checkbox.addEventListener("change", () => {
        localStorage.setItem(id, checkbox.checked);
        sendLabelOverlaySettings();
      });
    }
  });

  // Send all label overlay settings to Ruby
  function sendLabelOverlaySettings() {
    if (window.sketchup?.update_label_overlay_settings) {
      const settings = {
        draw_mode: getDrawMode(),
        show_leader_lines: toggleLeaderLines?.checked ?? false,
        zoom_aware_fading: toggleZoomFade?.checked ?? false,
        show_entity_info: toggleEntityInfo?.checked ?? false,
        leader_line_angle: parseInt(angleSlider?.value ?? "90", 10),
        leader_line_length: parseFloat(lengthSlider?.value ?? "12"),
        fade_start_distance: parseFloat(minFadeSlider?.value ?? "10"),
        fade_end_distance: parseFloat(fadeDistanceSlider?.value ?? "100"),
        font_size: parseInt(fontSizeInput?.value ?? "14", 10),
        font_color: fontColorInput?.value ?? "#000000",
        show_tag_colors: toggleTagColors?.checked ?? false,
        overlay_position: overlayPositionSelect?.value ?? "upper_left",

        // Entity info overlay options
        show_definition_name: document.getElementById("showComponentDefinition")?.checked ?? true,
        show_instance_name: document.getElementById("showComponentInstance")?.checked ?? true,
        show_volume: document.getElementById("showComponentVolume")?.checked ?? true,
        show_description: document.getElementById("showComponentDescription")?.checked ?? true,
        show_tag_label: document.getElementById("showTagLabel")?.checked ?? true,

        // Measurement toggles
        show_area: document.getElementById("showArea")?.checked ?? true,
        show_length: document.getElementById("showLength")?.checked ?? true,
        show_radius: document.getElementById("showRadius")?.checked ?? true,
        show_segments: document.getElementById("showSegments")?.checked ?? true,

        // Background options
        show_background: toggleBackground?.checked ?? false,
        background_color: backgroundColorInput?.value ?? "#f0f0f0",

      };
      window.sketchup.update_label_overlay_settings(JSON.stringify(settings));
    }
  }

  const drawModeRadios = document.querySelectorAll('input[name="drawMode"]');
  drawModeRadios.forEach((radio) => {
    radio.addEventListener('change', () => {
      localStorage.setItem('drawMode', getDrawMode());
      sendLabelOverlaySettings();
    });
  });

  if (angleSlider && angleLabel) {
    const saved = localStorage.getItem('leaderLineAngle');
    angleSlider.value = saved ?? "90";
    angleLabel.textContent = `${angleSlider.value}°`;

    angleSlider.addEventListener('input', () => {
      angleLabel.textContent = `${angleSlider.value}°`;
      localStorage.setItem('leaderLineAngle', angleSlider.value);
      sendLabelOverlaySettings();
    });
  }

  // Leader Line Length (Label Offset) — inches
  if (lengthSlider && lengthLabel) {
    const saved = localStorage.getItem('leaderLineLength'); // stored in inches
    lengthSlider.value = saved ?? "12";

    const val = parseFloat(lengthSlider.value);
    lengthLabel.textContent = `${val}″`;

    lengthSlider.addEventListener('input', () => {
      const val = parseFloat(lengthSlider.value);
      lengthLabel.textContent = `${val}″`;
      localStorage.setItem('leaderLineLength', lengthSlider.value);
      sendLabelOverlaySettings();
    });
  }

  // For min fade distance (start) — feet
  if (minFadeSlider && minFadeValue) {
    const savedMin = localStorage.getItem('minFadeDistanceFeet'); // stored in feet
    minFadeSlider.value = savedMin ?? "10";
    minFadeValue.textContent = `${minFadeSlider.value}′`;

    minFadeSlider.addEventListener('input', () => {
      minFadeValue.textContent = `${minFadeSlider.value}′`;
      localStorage.setItem('minFadeDistanceFeet', minFadeSlider.value);
      sendLabelOverlaySettings();
    });
  }

  // For full fade distance (end) — feet
  if (fadeDistanceSlider && fadeDistanceValue) {
    const savedFade = localStorage.getItem('fadeDistanceFeet'); // stored in feet
    fadeDistanceSlider.value = savedFade ?? "100";
    fadeDistanceValue.textContent = `${fadeDistanceSlider.value}′`;

    fadeDistanceSlider.addEventListener('input', () => {
      fadeDistanceValue.textContent = `${fadeDistanceSlider.value}′`;
      localStorage.setItem('fadeDistanceFeet', fadeDistanceSlider.value);
      sendLabelOverlaySettings();
    });
  }

  if (fontSizeInput) {
    const savedSize = localStorage.getItem("overlayFontSize") || "14";
    fontSizeInput.value = savedSize;

    fontSizeInput.addEventListener("input", () => {
      localStorage.setItem("overlayFontSize", fontSizeInput.value);
      sendLabelOverlaySettings();
    });
  }

  if (fontColorInput) {
    const savedColor = localStorage.getItem("overlayFontColor") || "#000000";
    fontColorInput.value = savedColor;

    fontColorInput.addEventListener("input", () => {
      localStorage.setItem("overlayFontColor", fontColorInput.value);
      sendLabelOverlaySettings();
    });
  }

  if (toggleTagColors) {
    const saved = localStorage.getItem("showTagColors");
    toggleTagColors.checked = saved === "true";

    toggleTagColors.addEventListener("change", () => {
      localStorage.setItem("showTagColors", toggleTagColors.checked);
      sendLabelOverlaySettings();
    });
  }

  if (applyOverlayPositionButton) {
    applyOverlayPositionButton.addEventListener("click", (event) => {
      event.preventDefault();
      const position = overlayPositionSelect.value;
      window.sketchup.update_overlay_position(position);
    });
  }

  // Restore saved draw mode on load
  const savedDrawMode = localStorage.getItem('drawMode');
  if (savedDrawMode) {
    const radioToCheck = document.querySelector(`input[name="drawMode"][value="${savedDrawMode}"]`);
    if (radioToCheck) radioToCheck.checked = true;
    sendLabelOverlaySettings();
  }

  // Load saved state
  if (toggleBackground) {
    const saved = localStorage.getItem("showBackground");
    toggleBackground.checked = saved === "true";

    toggleBackground.addEventListener("change", () => {
      localStorage.setItem("showBackground", toggleBackground.checked);
      sendLabelOverlaySettings();
    });

    // Force-sync once at startup
    sendLabelOverlaySettings();
  }

  if (backgroundColorInput) {
    const savedColor = localStorage.getItem("backgroundColor") || "#f0f0f0";
    backgroundColorInput.value = savedColor;

    backgroundColorInput.addEventListener("input", () => {
      localStorage.setItem("backgroundColor", backgroundColorInput.value);
      sendLabelOverlaySettings();
    });

    // Sync to Ruby immediately
    sendLabelOverlaySettings();
  }

});

// Example: refresh overlay from JS
function refreshOverlay() {
  if (window.sketchup?.refresh_overlay) {
    window.sketchup.refresh_overlay();
  }
}

function getDrawMode() {
  const selected = document.querySelector('input[name="drawMode"]:checked');
  return selected ? selected.value : "label_3d";
}