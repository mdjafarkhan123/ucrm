<script lang="ts">
	import type { Snippet } from 'svelte';

	// One labelled control inside a `FilterBar`. The label sits above the control and points at it by id,
	// so the control passed in has to carry that same id.
	let {
		children,
		label,
		id
	}: {
		children: Snippet;
		label: string;
		/** The id of the control inside, so the label reads out with it. */
		id: string;
	} = $props();
</script>

<div class="filter-field">
	<label for={id}>{label}</label>
	{@render children()}
</div>

<style lang="scss">
	.filter-field {
		display: grid;
		gap: var(--space-smaller);
		width: 200px;

		label {
			color: var(--color-text--secondary);
			font-size: var(--typography--fontSize-small);
			font-weight: 600;
		}
	}

	// On a phone the fields stack, one to a row, rather than squeezing side by side.
	@media (max-width: 767px) {
		.filter-field {
			width: 100%;
		}
	}
</style>
