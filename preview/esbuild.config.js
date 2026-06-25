// preview/esbuild.config.js
import esbuild from 'esbuild';

await esbuild.build({
  entryPoints: ['src/entry.js'],
  bundle: true,
  format: 'iife',
  globalName: 'MWPreview',
  outfile: 'dist/preview.js',
  target: ['safari14', 'chrome90'],     // iOS WKWebView / Android Chromium
  minify: true,
  legalComments: 'none',
  define: { 'process.env.NODE_ENV': '"production"' },
});
console.log('built dist/preview.js');
