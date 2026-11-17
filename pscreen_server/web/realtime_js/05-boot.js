'use strict';

      function bindEvents() {
        $('login-form').addEventListener('submit', (event) => {
          event.preventDefault();
          connect();
        });

        $('disconnect-btn').addEventListener('click', disconnect);
        $('refresh-btn').addEventListener('click', () => refreshAll());
        searchInput.addEventListener('input', renderAccounts);

        document.querySelectorAll('.filters button').forEach((button) => {
          button.addEventListener('click', () => {
            state.filter = button.dataset.filter || 'all';
            document.querySelectorAll('.filters button').forEach((item) => {
              item.classList.toggle('active', item === button);
            });
            renderTimeline(true);
          });
        });

        window.addEventListener('beforeunload', () => {
          state.manualClose = true;
          disconnectSocket();
        });
      }

      function boot() {
        const savedAccount = localStorage.getItem(STORAGE_ACCOUNT);
        const savedPassword = localStorage.getItem(STORAGE_PASSWORD);
        accountInput.value = savedAccount || DEFAULT_ACCOUNT;
        tokenInput.value = savedPassword || DEFAULT_PASSWORD;
        state.account = accountInput.value.trim();
        state.token = '';
        setWsLabel();
        bindEvents();
        renderAll();

        state.pollTimer = setInterval(() => {
          if (isOpen()) refreshAll();
        }, POLL_MS);

        setTimeout(() => connect(), 250);
      }

      boot();
