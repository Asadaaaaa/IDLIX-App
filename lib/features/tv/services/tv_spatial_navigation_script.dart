class TvSpatialNavigationScript {
  static String get script => '''
(function() {
  if (window.__idlixTvNavInitialized) {
    if (window.__idlixTvNav && typeof window.__idlixTvNav.init === 'function') {
      window.__idlixTvNav.init();
    }
    return;
  }
  window.__idlixTvNavInitialized = true;

  // 1. Inject Netflix-style Focus CSS
  var existingStyle = document.getElementById('idlix-tv-nav-styles');
  if (!existingStyle) {
    var style = document.createElement('style');
    style.id = 'idlix-tv-nav-styles';
    style.textContent = `
      .idlix-tv-focused {
        outline: 4px solid #E50914 !important;
        outline-offset: 3px !important;
        border-radius: 6px !important;
        box-shadow: 0 0 22px rgba(229, 9, 20, 0.95), 0 0 8px rgba(255, 255, 255, 0.8) !important;
        transform: scale(1.05) !important;
        transition: transform 0.15s cubic-bezier(0.2, 0, 0, 1), outline 0.15s ease, box-shadow 0.15s ease !important;
        z-index: 999999 !important;
        position: relative !important;
      }
      .idlix-tv-pressed {
        transform: scale(0.95) !important;
        transition: transform 0.08s ease !important;
      }
      #idlix-tv-focus-glow {
        position: fixed;
        pointer-events: none;
        border: 3.5px solid #E50914;
        border-radius: 8px;
        box-shadow: 0 0 20px rgba(229, 9, 20, 0.9), inset 0 0 10px rgba(229, 9, 20, 0.3);
        z-index: 2147483647;
        transition: all 0.15s cubic-bezier(0.2, 0, 0, 1);
        display: none;
      }
    `;
    document.head.appendChild(style);
  }

  // 2. Floating Netflix focus ring (tracks elements across any stacking context)
  var glowRing = document.getElementById('idlix-tv-focus-glow');
  if (!glowRing) {
    glowRing = document.createElement('div');
    glowRing.id = 'idlix-tv-focus-glow';
    document.body.appendChild(glowRing);
  }

  var currentEl = null;

  function isVisible(el) {
    if (!el || !el.getBoundingClientRect) return false;
    var rect = el.getBoundingClientRect();
    if (rect.width < 10 || rect.height < 10) return false;
    var style = window.getComputedStyle(el);
    if (style.display === 'none' || style.visibility === 'hidden' || style.opacity === '0') return false;
    return true;
  }

  function getFocusables() {
    var selector = 'a, button, input:not([type="hidden"]), select, textarea, [tabindex]:not([tabindex="-1"]), [role="button"], video, iframe, .ml-item, .item, .film-poster, .btn, .nav-item, .nav-link, .episode-item, .server-item';
    var all = Array.from(document.querySelectorAll(selector));
    var results = [];
    var vpH = window.innerHeight || document.documentElement.clientHeight;
    var vpW = window.innerWidth || document.documentElement.clientWidth;

    for (var i = 0; i < all.length; i++) {
      var el = all[i];

      // Avoid focusing large container wrappers if they contain clickable children
      if (el.tagName !== 'A' && el.tagName !== 'BUTTON' && el.tagName !== 'INPUT') {
        if (el.querySelector('a, button, input')) {
          continue;
        }
      }

      if (!isVisible(el)) continue;

      var rect = el.getBoundingClientRect();
      // Filter out elements too far from current viewport
      if (rect.bottom < -400 || rect.top > vpH + 400 || rect.right < -150 || rect.left > vpW + 150) {
        continue;
      }
      results.push({ el: el, rect: rect });
    }
    return results;
  }

  function updateGlow(rect) {
    if (!glowRing) return;
    if (!rect) {
      glowRing.style.display = 'none';
      return;
    }
    glowRing.style.left = (rect.left - 4) + 'px';
    glowRing.style.top = (rect.top - 4) + 'px';
    glowRing.style.width = (rect.width + 8) + 'px';
    glowRing.style.height = (rect.height + 8) + 'px';
    glowRing.style.display = 'block';
  }

  function setFocus(el, scroll) {
    if (currentEl) {
      currentEl.classList.remove('idlix-tv-focused');
    }
    currentEl = el;
    if (!el) {
      updateGlow(null);
      return;
    }

    el.classList.add('idlix-tv-focused');
    if (el.focus) {
      try { el.focus({ preventScroll: true }); } catch(_) {}
    }

    if (scroll !== false) {
      try {
        el.scrollIntoView({ behavior: 'smooth', block: 'center', inline: 'nearest' });
      } catch(_) {
        try { el.scrollIntoView(true); } catch(_) {}
      }
    }

    setTimeout(function() {
      if (currentEl === el && isVisible(el)) {
        updateGlow(el.getBoundingClientRect());
      }
    }, 60);
  }

  // Synchronize glow ring when scrolling or resizing
  window.addEventListener('scroll', function() {
    if (currentEl && isVisible(currentEl)) {
      updateGlow(currentEl.getBoundingClientRect());
    }
  }, { passive: true });

  window.addEventListener('resize', function() {
    if (currentEl && isVisible(currentEl)) {
      updateGlow(currentEl.getBoundingClientRect());
    }
  }, { passive: true });

  function findInitialFocus() {
    var list = getFocusables();
    if (list.length === 0) return null;
    var vpH = window.innerHeight || document.documentElement.clientHeight;
    var inView = list.filter(function(item) {
      return item.rect.top >= 0 && item.rect.bottom <= vpH;
    });
    if (inView.length > 0) {
      inView.sort(function(a, b) {
        if (Math.abs(a.rect.top - b.rect.top) > 30) {
          return a.rect.top - b.rect.top;
        }
        return a.rect.left - b.rect.left;
      });
      return inView[0].el;
    }
    return list[0].el;
  }

  window.__idlixTvNav = {
    init: function() {
      if (!currentEl || !isVisible(currentEl) || !document.contains(currentEl)) {
        var initial = findInitialFocus();
        if (initial) setFocus(initial, false);
      }
    },

    navigate: function(dir) {
      if (!currentEl || !isVisible(currentEl) || !document.contains(currentEl)) {
        var initial = findInitialFocus();
        if (initial) {
          setFocus(initial, true);
          return true;
        }
      }

      var currRect = currentEl.getBoundingClientRect();
      var cx = currRect.left + currRect.width / 2;
      var cy = currRect.top + currRect.height / 2;

      var list = getFocusables();
      var bestEl = null;
      var bestScore = Infinity;

      for (var i = 0; i < list.length; i++) {
        var item = list[i];
        if (item.el === currentEl) continue;
        var r = item.rect;
        var targetCx = r.left + r.width / 2;
        var targetCy = r.top + r.height / 2;

        var primaryDist = 0;
        var crossDist = 0;
        var isValidDir = false;
        var hasOverlap = false;

        if (dir === 'right') {
          if (targetCx > cx + 8 && r.right > currRect.left + 15) {
            isValidDir = true;
            primaryDist = Math.max(0, r.left - currRect.right);
            crossDist = Math.abs(targetCy - cy);
            var overlapY = Math.min(currRect.bottom, r.bottom) - Math.max(currRect.top, r.top);
            hasOverlap = overlapY > 10;
          }
        } else if (dir === 'left') {
          if (targetCx < cx - 8 && r.left < currRect.right - 15) {
            isValidDir = true;
            primaryDist = Math.max(0, currRect.left - r.right);
            crossDist = Math.abs(targetCy - cy);
            var overlapY = Math.min(currRect.bottom, r.bottom) - Math.max(currRect.top, r.top);
            hasOverlap = overlapY > 10;
          }
        } else if (dir === 'down') {
          if (targetCy > cy + 8 && r.bottom > currRect.top + 15) {
            isValidDir = true;
            primaryDist = Math.max(0, r.top - currRect.bottom);
            crossDist = Math.abs(targetCx - cx);
            var overlapX = Math.min(currRect.right, r.right) - Math.max(currRect.left, r.left);
            hasOverlap = overlapX > 10;
          }
        } else if (dir === 'up') {
          if (targetCy < cy - 8 && r.top < currRect.bottom - 15) {
            isValidDir = true;
            primaryDist = Math.max(0, currRect.top - r.bottom);
            crossDist = Math.abs(targetCx - cx);
            var overlapX = Math.min(currRect.right, r.right) - Math.max(currRect.left, r.left);
            hasOverlap = overlapX > 10;
          }
        }

        if (isValidDir) {
          var score = hasOverlap
            ? primaryDist + (crossDist * 0.3)
            : primaryDist + (crossDist * 2.0) + 120;

          if (score < bestScore) {
            bestScore = score;
            bestEl = item.el;
          }
        }
      }

      if (bestEl) {
        setFocus(bestEl, true);
        return true;
      }

      // If at boundary, scroll page smoothly and re-evaluate
      if (dir === 'down') {
        window.scrollBy({ top: 320, behavior: 'smooth' });
        setTimeout(function() {
          var nextList = getFocusables().filter(function(it) {
            return it.rect.top > currRect.bottom - 20;
          });
          if (nextList.length > 0) {
            nextList.sort(function(a, b) {
              var da = Math.abs((a.rect.left + a.rect.width / 2) - cx);
              var db = Math.abs((b.rect.left + b.rect.width / 2) - cx);
              return da - db;
            });
            setFocus(nextList[0].el, true);
          }
        }, 220);
        return true;
      } else if (dir === 'up') {
        window.scrollBy({ top: -320, behavior: 'smooth' });
        setTimeout(function() {
          var prevList = getFocusables().filter(function(it) {
            return it.rect.bottom < currRect.top + 20;
          });
          if (prevList.length > 0) {
            prevList.sort(function(a, b) {
              var da = Math.abs((a.rect.left + a.rect.width / 2) - cx);
              var db = Math.abs((b.rect.left + b.rect.width / 2) - cx);
              return da - db;
            });
            setFocus(prevList[prevList.length - 1].el, true);
          }
        }, 220);
        return true;
      }

      return false;
    },

    click: function() {
      if (!currentEl || !isVisible(currentEl) || !document.contains(currentEl)) {
        var initEl = findInitialFocus();
        if (initEl) {
          setFocus(initEl, true);
          return true;
        }
        return false;
      }

      currentEl.classList.add('idlix-tv-pressed');
      setTimeout(function() {
        if (currentEl) currentEl.classList.remove('idlix-tv-pressed');
      }, 150);

      var rect = currentEl.getBoundingClientRect();
      var x = rect.left + rect.width / 2;
      var y = rect.top + rect.height / 2;

      var opts = { bubbles: true, cancelable: true, view: window, clientX: x, clientY: y };
      currentEl.dispatchEvent(new MouseEvent('mousedown', opts));
      currentEl.dispatchEvent(new MouseEvent('mouseup', opts));
      currentEl.dispatchEvent(new MouseEvent('click', opts));

      if (typeof currentEl.click === 'function') {
        currentEl.click();
      } else {
        var parentLink = currentEl.closest('a, button');
        if (parentLink && typeof parentLink.click === 'function') {
          parentLink.click();
        }
      }

      return true;
    },

    scroll: function(dy) {
      window.scrollBy({ top: dy, behavior: 'smooth' });
    }
  };

  // Auto-init after page render
  setTimeout(function() {
    window.__idlixTvNav.init();
  }, 600);

  // Periodic health-check to restore focus if element is removed
  setInterval(function() {
    if (currentEl && (!document.contains(currentEl) || !isVisible(currentEl))) {
      currentEl = null;
      var next = findInitialFocus();
      if (next) setFocus(next, false);
    }
  }, 1200);
})();
''';
}
