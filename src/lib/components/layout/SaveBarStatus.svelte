<script lang="ts">
	let { dirty, error = '' }: { dirty: boolean; error?: string } = $props();
</script>

<div
	class="save-bar-status"
	class:save-bar-status--dirty={dirty && !error}
	class:save-bar-status--error={Boolean(error)}
	role="status"
	aria-live="polite"
>
	<span class="save-bar-status__indicator" aria-hidden="true">
		<span class="save-bar-status__dot"></span>
	</span>
	<div class="save-bar-status__copy">
		<p class="save-bar-status__title">
			{#if error}
				{error}
			{:else if dirty}
				You have unsaved changes
			{:else}
				No unsaved changes
			{/if}
		</p>
		{#if !error}
			<p class="save-bar-status__hint">
				{dirty ? 'Nothing is saved until you press Save.' : 'Change any field, then press Save.'}
			</p>
		{/if}
	</div>
</div>

<style lang="scss">
	.save-bar-status {
		display: none;
		align-items: center;
		gap: var(--classic2-space-2);
		min-width: 0;
		flex: 1 1 auto;
		color: var(--classic2-white);
		font-family: var(--classic2-font);

		&__indicator {
			display: flex;
			flex: 0 0 auto;
			align-items: center;
			justify-content: center;
			width: var(--classic2-savebar-indicator-size);
			height: var(--classic2-savebar-indicator-size);
			border-radius: 50%;
			background: var(--classic2-feature-chip);
		}

		&__dot {
			flex: 0 0 auto;
			width: var(--classic2-space-1);
			height: var(--classic2-space-1);
			border-radius: 50%;
			background: var(--classic2-savebar-resting-dot);
		}

		&__copy {
			display: flex;
			flex-direction: column;
			gap: var(--space-smallest);
			min-width: 0;
		}

		&__title {
			overflow-wrap: anywhere;
			font-size: var(--classic2-font-body);
			font-weight: 600;
			line-height: 1.3;
		}

		&__hint {
			color: var(--classic2-savebar-muted);
			font-size: var(--classic2-font-small);
			line-height: 1.3;
		}
	}

	:global(:root:has(.app-shell[data-presentation='classic'])) .save-bar-status {
		display: flex;
	}

	:global(:root:has(.app-shell[data-presentation='classic'])) .save-bar-status__title {
		color: var(--classic2-savebar-text);
	}

	:global(:root:has(.app-shell[data-presentation='classic']))
		.save-bar-status--dirty
		.save-bar-status__indicator {
		background: var(--classic2-savebar-unsaved-surface);
	}

	:global(:root:has(.app-shell[data-presentation='classic']))
		.save-bar-status--dirty
		.save-bar-status__dot {
		background: var(--classic2-savebar-unsaved-dot);
	}

	:global(:root:has(.app-shell[data-presentation='classic']))
		.save-bar-status--error
		.save-bar-status__title {
		color: var(--classic2-savebar-error);
	}

	:global(:root:has(.app-shell[data-presentation='classic']))
		.save-bar-status--error
		.save-bar-status__dot {
		background: var(--classic2-savebar-error);
	}

	:global(:root:has(.app-shell[data-presentation='classic']))
		.save-bar-status--error
		.save-bar-status__indicator {
		background: var(--classic2-rose-soft);
	}
</style>
