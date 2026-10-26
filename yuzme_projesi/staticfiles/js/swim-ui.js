/**
 * SwimUI - Lightweight Vanilla Component Controller
 * Supports Mobile-first interaction, Dynamic Themes, PWA, Modals, Accordions, Tabs, and HTMX.
 */
(function () {
  'use strict';

  // 0. Theme Manager (Sis Mavisi, Okyanus Gece, Klasik Lacivert, Zümrüt Su)
  const META_COLORS = {
    'sis-mavisi': '#f8fafc',
    'okyanus-gece': '#0b1120',
    'klasik-lacivert': '#f1f5f9',
    'zumrut': '#f4f9f6',
    'pine-teal': '#f2f6f5',
    'lavanta-sisi': '#f4f5fa',
    'kizil-gumus': '#f6f7f9'
  };

  const THEME_NAMES = {
    'sis-mavisi': 'Sis Mavisi',
    'okyanus-gece': 'Okyanus Gece',
    'klasik-lacivert': 'Klasik Lacivert',
    'zumrut': 'Zümrüt Su',
    'pine-teal': 'Pine Teal',
    'lavanta-sisi': 'Lavanta Sisi',
    'kizil-gumus': 'Kızıl & Gümüş'
  };

  function getActiveTheme() {
    let t = document.documentElement.getAttribute('data-theme');
    if (!t) {
      try {
        t = localStorage.getItem('swim_theme');
      } catch (e) {}
    }
    return (t && THEME_NAMES[t]) ? t : 'sis-mavisi';
  }

  function applyTheme(themeId, save = true) {
    if (!THEME_NAMES[themeId]) {
      themeId = 'sis-mavisi';
    }
    document.documentElement.setAttribute('data-theme', themeId);
    if (save) {
      try {
        localStorage.setItem('swim_theme', themeId);
      } catch (e) {}
    }

    // Update meta theme-color for mobile browser address bars
    const metaThemeColor = document.querySelector('meta[name="theme-color"]');
    if (metaThemeColor && META_COLORS[themeId]) {
      metaThemeColor.setAttribute('content', META_COLORS[themeId]);
    }

    // Update theme labels in navbar/controls
    document.querySelectorAll('[data-swim-theme-label]').forEach(function (el) {
      el.textContent = THEME_NAMES[themeId];
    });

    // Update active highlight & checkmark on dropdown and mobile options
    document.querySelectorAll('[data-swim-theme-set]').forEach(function (btn) {
      const targetTheme = btn.getAttribute('data-swim-theme-set');
      const isActive = targetTheme === themeId;
      btn.classList.toggle('swim-theme-option-active', isActive);
      const checkIcon = btn.querySelector('.swim-theme-check');
      if (checkIcon) {
        checkIcon.classList.toggle('hidden', !isActive);
      }
    });

    window.dispatchEvent(new CustomEvent('swim:theme-changed', { detail: { theme: themeId } }));
  }

  window.SwimTheme = {
    get: getActiveTheme,
    set: applyTheme,
    themes: THEME_NAMES
  };

  // Sync initial theme UI
  if (document.readyState === 'loading') {
    document.addEventListener('DOMContentLoaded', function () {
      applyTheme(getActiveTheme(), false);
    });
  } else {
    applyTheme(getActiveTheme(), false);
  }

  // 1. PWA Service Worker Registration
  if ('serviceWorker' in navigator && window.location.protocol.startsWith('http')) {
    window.addEventListener('load', () => {
      navigator.serviceWorker.register('/static/sw.js').catch((err) => {
        console.debug('SW reg failed (normal in dev):', err);
      });
    });
  }

  // 2. Modal Helper Functions
  function openModal(modalEl) {
    if (!modalEl) return;
    modalEl.classList.remove('hidden');
    modalEl.classList.add('flex', 'swim-modal-open');
    document.body.classList.add('overflow-hidden');

    modalEl.dispatchEvent(new CustomEvent('shown.bs.modal', { bubbles: true }));
    modalEl.dispatchEvent(new CustomEvent('swim:modal-shown', { bubbles: true }));
  }

  function closeModal(modalEl) {
    if (!modalEl) return;
    modalEl.classList.add('hidden');
    modalEl.classList.remove('flex', 'swim-modal-open');
    if (!document.querySelector('.swim-modal-open')) {
      document.body.classList.remove('overflow-hidden');
    }

    modalEl.dispatchEvent(new CustomEvent('hidden.bs.modal', { bubbles: true }));
    modalEl.dispatchEvent(new CustomEvent('swim:modal-hidden', { bubbles: true }));
  }

  window.SwimModal = {
    show: function (target) {
      const el = typeof target === 'string' ? document.querySelector(target) : target;
      openModal(el);
    },
    hide: function (target) {
      const el = typeof target === 'string' ? document.querySelector(target) : target;
      closeModal(el);
    }
  };

  // 3. Tab Helper Functions
  function switchTab(targetSelector) {
    if (!targetSelector || !targetSelector.startsWith('#')) return;
    const targetPanel = document.querySelector(targetSelector);
    if (!targetPanel) return;

    const tabBtn = document.querySelector(`[data-swim-target="${targetSelector}"], [data-bs-target="${targetSelector}"], [href="${targetSelector}"]`);
    if (tabBtn) {
      const parentNav = tabBtn.closest('.swim-tabs, .swim-tabs-pills, .nav, .nav-pills, ul, div');
      if (parentNav) {
        parentNav.querySelectorAll('.swim-tab, .swim-tab-pill, [data-bs-toggle="tab"]').forEach((t) => {
          t.classList.remove('swim-tab-pill-active', 'swim-tab-active', 'active');
          t.setAttribute('aria-selected', 'false');
        });
      }
      tabBtn.classList.add('swim-tab-pill-active', 'active');
      tabBtn.setAttribute('aria-selected', 'true');
    }

    const tabContent = targetPanel.closest('.tab-content, .swim-tab-content') || targetPanel.parentElement;
    if (tabContent) {
      tabContent.querySelectorAll('.tab-pane, .swim-tab-pane').forEach((p) => {
        p.classList.add('hidden');
        p.classList.remove('show', 'active');
      });
    }
    targetPanel.classList.remove('hidden');
    targetPanel.classList.add('show', 'active');
  }

  window.SwimTabs = {
    show: switchTab
  };

  // 4. Event Delegation for Clicks (Modals, Tabs, Accordions, Themes, Mobile Nav)
  document.addEventListener('click', function (e) {
    // A. Theme Dropdown Toggle
    const themeToggle = e.target.closest('#swimThemeToggle, [data-swim-theme-toggle]');
    if (themeToggle) {
      e.preventDefault();
      e.stopPropagation();
      const dropdown = document.getElementById('swimThemeDropdown');
      if (dropdown) {
        dropdown.classList.toggle('hidden');
      }
      return;
    }

    // B. Theme Set Button (Desktop dropdown or mobile strip)
    const themeSetBtn = e.target.closest('[data-swim-theme-set]');
    if (themeSetBtn) {
      e.preventDefault();
      const chosen = themeSetBtn.getAttribute('data-swim-theme-set');
      applyTheme(chosen, true);
      const dropdown = document.getElementById('swimThemeDropdown');
      if (dropdown) {
        dropdown.classList.add('hidden');
      }
      return;
    }

    // Outside click to close theme dropdown
    const themeDropdown = document.getElementById('swimThemeDropdown');
    if (themeDropdown && !themeDropdown.classList.contains('hidden')) {
      if (!e.target.closest('#swimThemeDropdown') && !e.target.closest('#swimThemeToggle')) {
        themeDropdown.classList.add('hidden');
      }
    }

    // C. Open Modal Trigger
    const modalTrigger = e.target.closest('[data-swim-modal], [data-bs-toggle="modal"]');
    if (modalTrigger) {
      const targetSelector = modalTrigger.getAttribute('data-swim-modal') ||
                             modalTrigger.getAttribute('data-bs-target') ||
                             modalTrigger.getAttribute('href');
      if (targetSelector && targetSelector.startsWith('#')) {
        const modalEl = document.querySelector(targetSelector);
        if (modalEl) {
          if (!modalTrigger.hasAttribute('hx-get') && !modalTrigger.hasAttribute('hx-post') && modalTrigger.tagName === 'A') {
            e.preventDefault();
          }
          openModal(modalEl);
        }
      }
    }

    // D. Close Modal Trigger
    const dismissTrigger = e.target.closest('[data-swim-dismiss], [data-bs-dismiss="modal"], .swim-modal-close');
    if (dismissTrigger) {
      const modalEl = dismissTrigger.closest('.swim-modal, .modal');
      if (modalEl) {
        if (!dismissTrigger.hasAttribute('hx-get') && !dismissTrigger.hasAttribute('hx-post') && dismissTrigger.tagName === 'A') {
          e.preventDefault();
        }
        closeModal(modalEl);
      }
    }

    // E. Click on Modal Backdrop
    if (e.target.classList.contains('swim-modal') || e.target.classList.contains('swim-modal-backdrop') || e.target.classList.contains('modal')) {
      closeModal(e.target);
    }

    // F. Accordion Toggle
    const accordionBtn = e.target.closest('.swim-accordion-header, .swim-accordion-button, [data-bs-toggle="collapse"]');
    if (accordionBtn) {
      const targetSelector = accordionBtn.getAttribute('data-swim-target') ||
                             accordionBtn.getAttribute('data-bs-target') ||
                             accordionBtn.getAttribute('href');
      let targetEl = targetSelector ? document.querySelector(targetSelector) : null;
      if (!targetEl && accordionBtn.nextElementSibling) {
        targetEl = accordionBtn.nextElementSibling;
      }

      if (targetEl) {
        e.preventDefault();
        const isHidden = targetEl.classList.contains('hidden');
        if (isHidden) {
          targetEl.classList.remove('hidden');
          targetEl.classList.add('show');
          accordionBtn.classList.remove('collapsed');
          accordionBtn.setAttribute('aria-expanded', 'true');
        } else {
          targetEl.classList.add('hidden');
          targetEl.classList.remove('show');
          accordionBtn.classList.add('collapsed');
          accordionBtn.setAttribute('aria-expanded', 'false');
        }
      }
    }

    // G. Tab Switch
    const tabBtn = e.target.closest('.swim-tab, .swim-tab-pill, [data-bs-toggle="tab"]');
    if (tabBtn) {
      const targetSelector = tabBtn.getAttribute('data-swim-target') ||
                             tabBtn.getAttribute('data-bs-target') ||
                             tabBtn.getAttribute('href');
      if (targetSelector && targetSelector.startsWith('#')) {
        e.preventDefault();
        switchTab(targetSelector);
      }
    }

    // H. Mobile Navigation Toggle
    const mobileToggle = e.target.closest('#swimMobileToggle, [data-swim-nav-toggle]');
    if (mobileToggle) {
      e.preventDefault();
      const menu = document.getElementById('swimMobileMenu');
      if (menu) {
        menu.classList.toggle('hidden');
      }
    }
  });

  // Close top-most modal or theme dropdown on Escape key
  document.addEventListener('keydown', function (e) {
    if (e.key === 'Escape') {
      const themeDropdown = document.getElementById('swimThemeDropdown');
      if (themeDropdown && !themeDropdown.classList.contains('hidden')) {
        themeDropdown.classList.add('hidden');
        return;
      }

      const openModals = Array.from(document.querySelectorAll('.swim-modal-open:not(.hidden)'));
      if (openModals.length > 0) {
        closeModal(openModals[openModals.length - 1]);
      }
    }
  });

  // 5. HTMX Event Hooks
  document.addEventListener('htmx:afterSwap', function (e) {
    // A. Swapped into modal content -> auto-open modal if closed
    if (e.target && (e.target.id === 'sporcuModalContent' || e.target.id === 'yarisSonuclarModalContent' || e.target.classList.contains('swim-modal-box'))) {
      const modal = e.target.closest('.swim-modal');
      if (modal && modal.classList.contains('hidden')) {
        openModal(modal);
      }
    }

    // B. Swapped into #sonuclarContent -> automatically switch to results tab if currently in program tab
    if (e.target && (e.target.id === 'sonuclarContent' || e.target.querySelector('#sonuclarContent'))) {
      switchTab('#sonuclar');
    }

    // C. Re-bind dynamic select filtering if present
    if (e.target && typeof window.filterAthletesByClub === 'function') {
      window.filterAthletesByClub(false);
    }
  });

})();
