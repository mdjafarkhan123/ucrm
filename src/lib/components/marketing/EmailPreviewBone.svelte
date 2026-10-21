<script lang="ts">
	// The email-shaped loading bone (bar, image block, heading, lines, button) shown on the white paper while a
	// preview renders -- the email preview pop-up, the Review step and the Email step's live preview all use it.
	let { label = 'Rendering preview' }: { label?: string } = $props();
</script>

<div class="email-preview-bone" role="status" aria-label={label} aria-busy="true">
	<span class="skeleton email-preview-bone__bar"></span>
	<span class="skeleton email-preview-bone__image"></span>
	<span class="skeleton skeleton--heading"></span>
	<span class="skeleton skeleton--text"></span>
	<span class="skeleton skeleton--text"></span>
	<span class="skeleton skeleton--text skeleton--text-short"></span>
	<span class="skeleton email-preview-bone__button"></span>
</div>

<style lang="scss">
	.email-preview-bone {
		display: grid;
		gap: var(--space-slim);
		padding: var(--space-medium);

		&__bar {
			width: 45%;
			height: var(--space-large);
		}

		&__image {
			height: 160px;
			border-radius: var(--radius-base);
		}

		&__button {
			width: 140px;
			height: 36px;
			margin-top: var(--space-small);
			border-radius: var(--radius-base);
		}
	}
</style>
