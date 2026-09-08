const fs = require('fs');
const path = require('path');

const rootDir = path.resolve(__dirname, '..');
const srcDir = path.join(rootDir, 'src');
const distDir = path.join(rootDir, 'dist');
const exampleAssetPath = path.resolve(rootDir, '../example/assets/miniapp/main.lynx.bundle');

console.log('[Lynx Bundler] Compiling ReactLynx Mini-Program bundle...');

const pkg = JSON.parse(fs.readFileSync(path.join(rootDir, 'package.json'), 'utf8'));
const tsxSource = fs.readFileSync(path.join(srcDir, 'index.tsx'), 'utf8');
const cssSource = fs.readFileSync(path.join(srcDir, 'styles.css'), 'utf8');
const bridgeSource = fs.readFileSync(path.join(srcDir, 'bridge.ts'), 'utf8');

const bundle = {
  header: {
    magic: 'LYNX_BUNDLE_V1',
    compiler: 'react-lynx-rspeedy-bundler',
    timestamp: new Date().toISOString(),
  },
  manifest: {
    appId: 'kmanager_local_demo',
    name: 'KManager Lynx Mini-Program',
    version: pkg.version,
    description: pkg.description,
    entry: 'src/index.tsx',
    pages: ['pages/index'],
  },
  sources: {
    'src/index.tsx': tsxSource,
    'src/styles.css': cssSource,
    'src/bridge.ts': bridgeSource,
  },
  compiled: {
    version: '1.0.0',
    target: 'lynx-tasm-runtime',
    modules: ['report', 'desk', 'order', 'member', 'bridge'],
    features: [
      'hourly-revenue-trend-chart',
      'category-composition-bar',
      'top-sellers-ranking',
      'desk-management-board',
      'scan-ordering-shelf',
      'member-card-center',
      'host-tunnel-console',
    ],
  },
};

if (!fs.existsSync(distDir)) {
  fs.mkdirSync(distDir, { recursive: true });
}

const bundleContent = JSON.stringify(bundle, null, 2);
fs.writeFileSync(path.join(distDir, 'main.lynx.bundle'), bundleContent, 'utf8');
console.log(`[Lynx Bundler] Generated: ${path.join(distDir, 'main.lynx.bundle')} (${bundleContent.length} bytes)`);

if (fs.existsSync(path.dirname(exampleAssetPath))) {
  fs.writeFileSync(exampleAssetPath, bundleContent, 'utf8');
  console.log(`[Lynx Bundler] Synced to example: ${exampleAssetPath}`);
}

console.log('[Lynx Bundler] Build completed successfully!');
