<script lang="ts">
	import Button from '$lib/components/ui/Button.svelte';
	import Dialog from '$lib/components/ui/Dialog.svelte';
	import Input from '$lib/components/ui/Input.svelte';
	import {
		createPackage,
		PackageApiError,
		slugify,
		type PackageSummary
	} from '$lib/jafar/packages';

	// Starts a package: a blank draft, or a copy of another package's latest terms under a new name and
	// web address. A double click on Create still makes one package.
	let {
		open,
		copyFrom = null,
		onClose,
		onCreated
	}: {
		open: boolean;
		copyFrom?: PackageSummary | null;
		onClose: () => void;
		onCreated: (packageId: string) => void;
	} = $props();

	// The parent mounts this dialog fresh each time it opens, so the fields start from copyFrom and the
	// idempotency key belongs to this one attempt.
	function initialName() {
		const source = copyFrom ? (copyFrom.draft ?? copyFrom.published)?.name : null;
		return source ? `${source} copy` : '';
	}

	let name = $state(initialName());
	let slug = $state(slugify(initialName()));
	let slugEdited = $state(false);
	const idempotencyKey = crypto.randomUUID();
	let pending = $state(false);
	let formError = $state('');
	let fieldErrors = $state<Record<string, string>>({});

	function updateName(value: string) {
		name = value;
		if (!slugEdited) slug = slugify(value);
	}

	async function submit(event: SubmitEvent) {
		event.preventDefault();
		pending = true;
		formError = '';
		fieldErrors = {};
		try {
			const { result } = await createPackage({
				name,
				slug,
				idempotency_key: idempotencyKey,
				copy_from_package_id: copyFrom?.id ?? null
			});
			onCreated(result.package_id);
		} catch (error) {
			if (error instanceof PackageApiError && error.body.field_errors) {
				fieldErrors = error.body.field_errors;
			} else {
				formError = error instanceof Error ? error.message : 'The package could not be created.';
			}
		} finally {
			pending = false;
		}
	}
</script>

<Dialog
	{open}
	title={copyFrom ? 'Copy package' : 'New package'}
	initialFocusId="package-create-name"
	{onClose}
>
	<form class="package-create" onsubmit={submit}>
		<p class="package-create__intro">
			{copyFrom
				? 'The copy starts as a draft with the same terms. Customers on the original are not affected.'
				: 'The package starts as a private draft. Nobody can see or buy it until you publish it.'}
		</p>
		<Input
			id="package-create-name"
			label="Package name"
			required
			value={name}
			oninput={(event: Event) => updateName((event.currentTarget as HTMLInputElement).value)}
			invalid={Boolean(fieldErrors.name)}
			errorMessage={fieldErrors.name}
		/>
		<div class="package-create__slug">
			<Input
				id="package-create-slug"
				label="Web address"
				required
				bind:value={slug}
				oninput={() => (slugEdited = true)}
				invalid={Boolean(fieldErrors.slug)}
				errorMessage={fieldErrors.slug}
			/>
			{#if !fieldErrors.slug}
				<p class="package-create__hint">
					Used in links from your marketing site. It can change until the package is published.
				</p>
			{/if}
		</div>
		{#if formError}<p class="package-create__error" role="alert">{formError}</p>{/if}
		<div class="package-create__actions">
			<Button type="button" variant="secondary" variation="subtle" onclick={onClose}>Cancel</Button>
			<Button type="submit" loading={pending}>{copyFrom ? 'Create copy' : 'Create draft'}</Button>
		</div>
	</form>
</Dialog>

<style lang="scss">
	.package-create {
		display: grid;
		gap: var(--space-base);

		&__intro {
			margin: 0;
			color: var(--color-text--secondary);
			line-height: var(--typography--lineHeight-base);
		}

		&__slug {
			display: grid;
			gap: var(--space-small);
		}

		&__hint {
			margin: 0;
			color: var(--color-text--secondary);
			font-size: var(--typography--fontSize-small);
		}

		&__error {
			margin: 0;
			color: var(--color-critical);
			font-size: var(--typography--fontSize-small);
		}

		&__actions {
			display: flex;
			flex-wrap: wrap;
			justify-content: flex-end;
			gap: var(--space-small);
		}
	}
</style>
