window.sketchup = window.sketchup || {};

document.getElementById("editDescriptionBtn")?.addEventListener("click", () => {
  sketchup.getComponentDescription();
});

window.sketchup.receiveComponentDescription = (desc) => {
  const input = document.getElementById("descriptionInput");
  if (input) input.value = desc || "";

  const modal = new bootstrap.Modal(document.getElementById('editDescriptionModal'));
  modal.show();
};

document.getElementById("saveDescriptionBtn")?.addEventListener("click", () => {
  const newDesc = document.getElementById("descriptionInput")?.value ?? "";
  sketchup.setComponentDescription?.(newDesc);

  bootstrap.Modal.getInstance(document.getElementById('editDescriptionModal'))?.hide();
});