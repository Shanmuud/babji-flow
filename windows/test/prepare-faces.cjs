const fs = require('node:fs/promises');
const path = require('node:path');

// Public upstream fixtures only; downloaded files stay in ignored test-artifacts.
const fixtures = [
  ['portrait.jpg', 'https://storage.googleapis.com/mediapipe-assets/portrait.jpg'],
  ['astronaut.png', 'https://raw.githubusercontent.com/scikit-image/scikit-image/v0.25.2/skimage/data/astronaut.png'],
];

(async () => {
  const folder = path.join(__dirname, '../test-artifacts');
  await fs.mkdir(folder, { recursive: true });
  for (const [name, url] of fixtures) {
    const response = await fetch(url);
    if (!response.ok) throw new Error(`${name}: HTTP ${response.status}`);
    await fs.writeFile(path.join(folder, name), Buffer.from(await response.arrayBuffer()));
    console.log(`Prepared ${name}`);
  }
})().catch(error => { console.error(error.message); process.exitCode = 1; });
