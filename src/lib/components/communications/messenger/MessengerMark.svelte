<script lang="ts">
	import messengerIcon from '@tabler/icons/outline/brand-messenger.svg?raw';

	// Messenger's own round blue mark: 56 on the hub banner, 72 on the welcome card, 20 in the test chat, 18 as a Page's badge.
	let { size = 56 }: { size?: 18 | 20 | 56 | 72 } = $props();
</script>

<!-- eslint-disable-next-line svelte/no-at-html-tags -- trusted build-time Tabler icon -->
<span class="messenger-mark messenger-mark--{size}" aria-hidden="true">{@html messengerIcon}</span>

<style lang="scss">
	.messenger-mark {
		display: inline-grid;
		flex: 0 0 auto;
		place-items: center;
		border-radius: var(--radius-circle);
		color: var(--color-white);
		background: var(--color-messenger);

		:global(svg) {
			display: block;
		}

		&--72 {
			width: 72px;
			height: 72px;
			:global(svg) {
				width: 38px;
				height: 38px;
			}
		}
		&--56 {
			width: 56px;
			height: 56px;
			border: 1px solid var(--color-feature--border);
			:global(svg) {
				width: 30px;
				height: 30px;
			}
		}
		&--20 {
			width: 20px;
			height: 20px;
			:global(svg) {
				width: 12px;
				height: 12px;
			}
		}
		&--18 {
			width: 18px;
			height: 18px;
			box-shadow: 0 0 0 2px var(--color-surface);
			:global(svg) {
				width: 10px;
				height: 10px;
			}
		}
	}
</style>
