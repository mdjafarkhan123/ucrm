import { defineConfig } from 'vite';
import { resolve } from 'node:path';

// The public Website Chat widget is built separately from the app on purpose. It runs inside a
// stranger's website, so it must not share a single byte of the app's bundle, layout, or global
// stylesheet -- the iframe shell it replaces inherited `app.scss` and painted an opaque box behind
// its own transparent launcher. A self-contained bundle plus Shadow DOM removes that whole class of
// bug: nothing of ours leaks out onto the host page, and nothing of theirs leaks in.
//
// `emptyOutDir: false` because `static/` is the app's own checked-in static folder, not a build
// directory -- this build writes its files into it and must leave the rest alone. `npm run build`
// runs this first so SvelteKit copies the fresh files into the deployed output.
//
// The output is an ES module, not an IIFE, so the phone-number metadata can live in its own chunk
// that loads only when a visitor opens the panel -- a classic script cannot code-split, and that
// metadata was 170 kB of the widget's 180 kB. The same split now carries the Realtime client, which
// only a visitor with an open conversation ever downloads. The cost is that the embed snippet must
// say `type="module"`. Chunk names are derived from the module name rather than hashed because
// `emptyOutDir: false` would otherwise leave every previous build's chunk lying in `static/widget/`
// forever -- and a single fixed name would collide once there is more than one chunk.
export default defineConfig({
	build: {
		lib: {
			entry: resolve(import.meta.dirname, 'src/widget/website-chat.ts'),
			formats: ['es'],
			fileName: () => 'website-chat.js'
		},
		rollupOptions: {
			output: {
				chunkFileNames: 'website-chat-[name].js'
			}
		},
		outDir: 'static/widget',
		emptyOutDir: false,
		minify: true
	}
});
