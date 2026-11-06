document.addEventListener('DOMContentLoaded', () => {
  if (window.lucide) {
    window.lucide.createIcons();
  }

  const commandCode = document.querySelector('#install-command');
  const commandRow = document.querySelector('.command-row');
  const runtimeLabel = document.querySelector('#runtime-label');
  const downloadLink = document.querySelector('#download-link');
  const downloadLabel = document.querySelector('#download-label');
  const button = document.querySelector('#copy-button');
  const toast = document.querySelector('#toast');
  const tabs = Array.from(document.querySelectorAll('.client-tab'));
  let toastTimer;

  const selectClient = (tab) => {
    tabs.forEach((candidate) => {
      const active = candidate === tab;
      candidate.classList.toggle('is-active', active);
      candidate.setAttribute('aria-selected', String(active));
    });

    commandCode.textContent = tab.dataset.command;
    runtimeLabel.textContent = tab.dataset.runtime;
    downloadLink.href = tab.dataset.script;
    downloadLabel.textContent = `下载 ${tab.dataset.script}`;
  };

  tabs.forEach((tab) => {
    tab.addEventListener('click', () => selectClient(tab));
  });

  button.addEventListener('click', async () => {
    const command = commandCode.textContent.trim();
    try {
      await navigator.clipboard.writeText(command);
    } catch {
      const range = document.createRange();
      range.selectNodeContents(commandRow);
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
