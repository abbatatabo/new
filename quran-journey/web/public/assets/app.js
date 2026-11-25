// The Quran Journey — progressive enhancements only; every page works without JS.
(function () {
  'use strict';
  // Remember the browser's time zone so "today" is computed in the user's day.
  try {
    var tz = Intl.DateTimeFormat().resolvedOptions().timeZone;
    if (tz && document.cookie.indexOf('qj_tz=' + encodeURIComponent(tz)) === -1) {
      document.cookie = 'qj_tz=' + encodeURIComponent(tz) + '; path=/; max-age=63072000; samesite=lax' + (location.protocol === 'https:' ? '; secure' : '');
    }
  } catch (e) {}

  // Confirmation for destructive buttons.
  document.addEventListener('click', function (e) {
    var b = e.target.closest('[data-confirm]');
    if (b && !window.confirm(b.getAttribute('data-confirm'))) e.preventDefault();
    var r = e.target.closest('.js-reveal button');
    if (r) {
      var p = r.parentNode;
      var code = document.createElement('code');
      code.textContent = p.getAttribute('data-code');
      code.style.cssText = 'font-size:15px;word-break:break-all;user-select:all';
      p.replaceChildren(code);
    }
  });

  // Verse-by-verse recitation with follow-along highlighting.
  var dataEl = document.getElementById('study-audio');
  if (!dataEl) return;
  var data = JSON.parse(dataEl.textContent);
  var audio = new Audio();
  audio.preload = 'none';
  var idx = -1;
  var pad = function (n) { return String(n).padStart(3, '0'); };
  var url = function (v) { return 'https://everyayah.com/data/' + data.reciter + '/' + pad(v.s) + pad(v.a) + '.mp3'; };
  var icon = document.querySelector('.js-icon');
  function mark() {
    document.querySelectorAll('.verse.playing').forEach(function (el) { el.classList.remove('playing'); });
    if (idx >= 0 && !audio.paused) {
      var el = document.getElementById('v' + data.verses[idx].id);
      if (el) { el.classList.add('playing'); el.scrollIntoView({ block: 'nearest', behavior: 'smooth' }); }
    }
    if (icon) icon.setAttribute('d', audio.paused ? 'M8 5.5v13l11-6.5z' : 'M7 5h4v14H7zM13 5h4v14h-4z');
  }
  function play(i) {
    if (i < 0 || i >= data.verses.length) { audio.pause(); idx = -1; mark(); return; }
    idx = i;
    audio.src = url(data.verses[i]);
    audio.play().catch(function () { mark(); });
  }
  audio.addEventListener('ended', function () { play(idx + 1); });
  audio.addEventListener('play', mark);
  audio.addEventListener('pause', mark);
  audio.addEventListener('error', function () { idx = -1; mark(); });
  var on = function (sel, fn) { var el = document.querySelector(sel); if (el) el.addEventListener('click', fn); };
  on('.js-toggle', function () { if (idx < 0) play(0); else if (audio.paused) audio.play(); else audio.pause(); });
  on('.js-next', function () { play(Math.min(idx + 1, data.verses.length - 1)); });
  on('.js-prev', function () { play(Math.max(idx - 1, 0)); });
  on('.js-replay', function () { if (idx < 0) play(0); else { audio.currentTime = 0; audio.play(); } });
  document.querySelectorAll('.js-play').forEach(function (b) {
    b.addEventListener('click', function () {
      var id = Number(b.closest('.verse').id.slice(1));
      play(data.verses.findIndex(function (v) { return v.id === id; }));
    });
  });
})();
