function detectPlatform(agent) {
  if (/Windows/i.test(agent)) return 'windows';
  if (/Macintosh|Mac OS X/i.test(agent) && !/iPhone|iPad/i.test(agent)) return 'mac';
  return null;
}
if (typeof module !== 'undefined') module.exports = { detectPlatform };
if (typeof document !== 'undefined') {
  const platform = detectPlatform(navigator.userAgent);
  if (platform) {
    document.getElementById(platform).classList.add('recommended');
    document.getElementById('recommendation').textContent = 'Recommended for this browser: ' + (platform === 'mac' ? 'macOS (check Apple Silicon compatibility)' : 'Windows (check x64 compatibility)') + '. You can choose either guide below.';
  }
}
