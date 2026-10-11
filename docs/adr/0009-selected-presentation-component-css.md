# Selected presentations carry their component CSS

For presentation-exclusive components, use Svelte's per-component `css="injected"` option with explicit
selected dynamic imports. The installed SvelteKit release links extracted CSS across dynamic server
imports, so separate chunks alone downloaded the inactive presentation's styles. Svelte's supported
injection emits only the rendered shell's styles in the SSR head and delivers CSR surface styles with
its selected JavaScript, retaining ordinary Svelte hydration and component-local SCSS.

The [release-build proof](../research/selectable-design-injected-css-2026-10-11.md) passes for the private
synthetic fixture. This is the mechanism to carry into the real-shell experiment, not proof of complete
workspace isolation. Shared/global styles, nested extracted dependencies, assets, CSP and route warming
must be checked again with the real shell. Inline SSR styles repeat in HTML and component CSS also travels
in cached JavaScript; measure that cost before broad adoption. Keep shared foundations extracted where
appropriate. No framework patch, custom HTML filtering, duplicated routes or second hydration root is needed.
