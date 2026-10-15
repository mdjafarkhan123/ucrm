<script lang="ts">
	import { Tooltip as Primitive } from 'bits-ui';
	import type { Snippet } from 'svelte';

	let {
		text,
		description,
		children
	}: {
		text: string;
		description?: string;
		children: Snippet<[{ props: Record<string, unknown> }]>;
	} = $props();
	const contentId = $props.id();
	let open = $state(false);
</script>

<Primitive.Provider delayDuration={300}>
	<Primitive.Root bind:open>
		<Primitive.Trigger>
			{#snippet child({ props })}
				{@render children({
					props: { ...props, 'aria-describedby': open ? contentId : undefined }
				})}
			{/snippet}
		</Primitive.Trigger>
		<Primitive.Portal>
			<Primitive.Content
				id={contentId}
				class="tooltip"
				role="tooltip"
				sideOffset={8}
				collisionPadding={16}
			>
				{#snippet child({ props, wrapperProps })}
					<div {...wrapperProps}>
						<div {...props} id={contentId} role="tooltip" class="tooltip">
							<strong>{text}</strong>
							{#if description}<span>{description}</span>{/if}
						</div>
					</div>
				{/snippet}
			</Primitive.Content>
		</Primitive.Portal>
	</Primitive.Root>
</Primitive.Provider>

<style lang="scss">
	:global(.tooltip) {
		z-index: var(--elevation-tooltip);
		display: grid;
		gap: 2px;
		max-width: min(300px, calc(100vw - 32px));
		padding: 8px 10px;
		border: 1px solid var(--color-border);
		border-radius: 10px;
		color: var(--color-heading);
		background: var(--color-surface);
		font-family: inherit;
		font-size: 12px;
		line-height: 1.5;
	}
	:global(:root:has(.app-shell[data-presentation='classic']) .tooltip) {
		border-color: var(--classic2-feature-line);
		color: var(--classic2-white);
		background: var(--classic2-sidebar);
		font-family: var(--classic2-font);
	}
	:global(.tooltip strong) {
		font-weight: 700;
	}
	:global(:root:has(.app-shell[data-presentation='classic']) .tooltip span) {
		color: var(--classic2-feature-muted);
	}
</style>
