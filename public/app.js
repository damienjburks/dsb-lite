// Small progressive-enhancement script: fills in the current year and pulls
// live build metadata from the /api/version endpoint so the footer always
// reflects the running container.
(function () {
  'use strict';

  var yearEl = document.getElementById('year');
  if (yearEl) {
    yearEl.textContent = String(new Date().getFullYear());
  }

  var metaEl = document.getElementById('build-meta');
  if (!metaEl) {
    return;
  }

  fetch('/api/version', { headers: { Accept: 'application/json' } })
    .then(function (res) {
      if (!res.ok) {
        throw new Error('HTTP ' + res.status);
      }
      return res.json();
    })
    .then(function (data) {
      var commit = (data.gitCommit || 'unknown').substring(0, 7);
      metaEl.textContent =
        'v' +
        (data.version || '?') +
        ' \u00b7 ' +
        (data.environment || '?') +
        ' \u00b7 ' +
        commit;
      metaEl.title =
        'Build time: ' + (data.buildTime || 'unknown') + '\nCommit: ' + (data.gitCommit || 'unknown');
    })
    .catch(function () {
      metaEl.textContent = 'build info unavailable';
    });
})();
