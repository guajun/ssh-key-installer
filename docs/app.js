document.addEventListener('DOMContentLoaded', () => {
  if (window.lucide) {
    window.lucide.createIcons();
  }

  const command = document.querySelector('#install-command').textContent.trim();
  const button = document.querySelector('#copy-button');
  const toast = document.querySelector('#toast');
  let toastTimer;

  button.addEventListener('click', async () => {
    try {
      await navigator.clipboard.writeText(command);
    } catch {
      const range = document.createRange();
      range.selectNodeContents(document.querySelector('#install-command'));
      const selection = window.getSelection();
      selection.removeAllRanges();
      selection.addRange(range);
      document.execCommand('copy');
      selection.removeAllRanges();
    }

    button.querySelector('span').textContent = '已复制';
    toast.classList.add('visible');
    clearTimeout(toastTimer);
    toastTimer = setTimeout(() => {
      toast.classList.remove('visible');
      button.querySelector('span').textContent = '复制';
    }, 1800);
  });
});

