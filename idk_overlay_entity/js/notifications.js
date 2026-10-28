// notifications.js

function showNotification(message, type = 'info') {
  const notification = document.createElement('div');
  notification.className = `alert alert-${type} alert-dismissible fade show`;
  notification.innerHTML = `
    ${message}
    <button type="button" class="btn-close" data-bs-dismiss="alert" aria-label="Close"></button>
  `;
  notification.style.position = 'fixed';
  notification.style.top = '1rem';
  notification.style.right = '1rem';
  notification.style.zIndex = 9999;

  document.body.appendChild(notification);

  setTimeout(() => {
    notification.classList.remove('show');
    notification.remove();
  }, 4000);
}