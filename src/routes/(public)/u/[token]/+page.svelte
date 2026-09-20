<script lang="ts">
	import Button from '$lib/components/ui/Button.svelte';

	// The one screen a customer sees when they want out of a contractor's marketing email. It is deliberately
	// a single decision with a single button: everything about who they are and what they were sent came from
	// the token in the URL, resolved on the server, and there is nothing else on this page to explore.
	//
	// The form posts without JavaScript on purpose. This page opens in whatever browser the customer's mail app
	// hands it, and an unsubscribe that needs a working script is an unsubscribe that sometimes does not happen.
	let { data, form } = $props();

	// `form` is only present after the button was pressed, so it wins over the loaded state.
	const target = $derived(form?.target ?? data.target);
	const finished = $derived(Boolean(form?.done) || Boolean(data.target?.already_unsubscribed));
	const failed = $derived(form ? !form.done : false);
</script>

<svelte:head>
	<title>{target ? 'Marketing emails' : 'Link not available'}</title>
	<meta name="robots" content="noindex, nofollow" />
	<meta name="referrer" content="no-referrer" />
</svelte:head>

<main class="unsubscribe">
	<div class="unsubscribe__card">
		{#if !target}
			<h1 class="unsubscribe__title">This link is not available</h1>
			<p class="unsubscribe__body">
				{#if data.throttled}
					This page has been opened many times in the last minute. Wait a moment and open the link
					again.
				{:else}
					The link may be incomplete, or it may belong to an email address that has since been
					removed. Reply to the email you received and ask the company to stop sending you marketing
					email.
				{/if}
			</p>
		{:else}
			{#if target.business_name}
				<p class="unsubscribe__business">{target.business_name}</p>
			{/if}

			{#if finished}
				<h1 class="unsubscribe__title">You're unsubscribed</h1>
				<p class="unsubscribe__body">
					{target.business_name ?? 'This company'} will not send marketing email to
					<strong class="unsubscribe__email">{target.email}</strong> any more.
				</p>
				<p class="unsubscribe__note">
					You will still receive the emails you need for work you have asked for — quotes, invoices,
					receipts and job updates. To stop those as well, reply to any email from them and say so.
				</p>
			{:else}
				<h1 class="unsubscribe__title">Stop marketing emails?</h1>
				<p class="unsubscribe__body">
					Marketing email to <strong class="unsubscribe__email">{target.email}</strong> will stop. You
					will still receive quotes, invoices, receipts and job updates.
				</p>

				{#if failed}
					<p class="unsubscribe__error" role="alert">
						That did not go through. Press the button once more.
					</p>
				{/if}

				<form method="POST" class="unsubscribe__form">
					<Button type="submit" variant="primary" size="large" fullWidth>Unsubscribe</Button>
				</form>
			{/if}
		{/if}
	</div>
</main>

<style lang="scss">
	.unsubscribe {
		display: flex;
		align-items: center;
		justify-content: center;
		min-height: 100vh;
		padding: var(--space-large);
		background: var(--color-surface--background);
		color: var(--color-text);

		&__card {
			display: flex;
			flex-direction: column;
			gap: var(--space-base);
			width: 100%;
			max-width: 32rem;
			padding: var(--space-largest);
			background: var(--color-surface);
			border: 1px solid var(--color-border);
			border-radius: var(--radius-base);
			text-align: center;

			@media (max-width: 480px) {
				padding: var(--space-larger);
			}
		}

		&__business {
			margin: 0;
			color: var(--color-text--secondary);
			font-size: var(--typography--fontSize-small);
			font-weight: 600;
			letter-spacing: 0.04em;
			text-transform: uppercase;
		}

		&__title {
			margin: 0;
			color: var(--color-heading);
			font-size: var(--typography--fontSize-larger);
			line-height: var(--typography--lineHeight-tightest);
			font-weight: 700;
		}

		&__body {
			margin: 0;
			color: var(--color-text);
		}

		&__email {
			overflow-wrap: anywhere;
			font-weight: 600;
		}

		&__note {
			margin: 0;
			padding-top: var(--space-small);
			border-top: 1px solid var(--color-border);
			color: var(--color-text--secondary);
			font-size: var(--typography--fontSize-small);
		}

		&__error {
			margin: 0;
			padding: var(--space-small) var(--space-base);
			background: var(--color-critical--surface);
			border-radius: var(--radius-base);
			color: var(--color-critical--onSurface);
			font-size: var(--typography--fontSize-small);
		}

		&__form {
			margin-top: var(--space-small);
		}
	}
</style>
