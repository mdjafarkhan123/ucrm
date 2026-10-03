<script lang="ts">
	import Badge from '$lib/components/ui/Badge.svelte';
	import Button from '$lib/components/ui/Button.svelte';
	import Dialog from '$lib/components/ui/Dialog.svelte';
	import Input from '$lib/components/ui/Input.svelte';
	import Textarea from '$lib/components/ui/Textarea.svelte';
	import {
		changePackageService,
		createPackageService,
		PackageApiError,
		type PackageService,
		type PackageServiceChange
	} from '$lib/jafar/packages';

	// Client onboarding A2 (plan §2.1): Jafar's list of the services Uplift sells. Renaming changes the list
	// only; a published package keeps the wording it promised. A service is archived rather than deleted,
	// because a customer's package may still include it.
	let {
		open,
		services,
		onClose,
		onChanged
	}: {
		open: boolean;
		services: PackageService[];
		onClose: () => void;
		onChanged: (services: PackageService[]) => void;
	} = $props();

	// The service being renamed, or 'new' for the add form.
	let editing = $state<string | null>(null);
	let name = $state('');
	let description = $state('');
	let pending = $state<string | null>(null);
	let formError = $state('');
	let fieldErrors = $state<Record<string, string>>({});

	function startEdit(service: PackageService | null) {
		editing = service?.key ?? 'new';
		name = service?.name ?? '';
		description = service?.description ?? '';
		formError = '';
		fieldErrors = {};
	}

	async function run(key: string, command: () => Promise<PackageService[]>) {
		pending = key;
		formError = '';
		fieldErrors = {};
		try {
			onChanged(await command());
			editing = null;
		} catch (error) {
			if (error instanceof PackageApiError && error.body.field_errors) {
				fieldErrors = error.body.field_errors;
			} else {
				formError = error instanceof Error ? error.message : 'The service could not be saved.';
			}
		} finally {
			pending = null;
		}
	}

	function submit(event: SubmitEvent) {
		event.preventDefault();
		const key = editing;
		if (!key) return;
		void run(key, () =>
			key === 'new'
				? createPackageService({ name, description })
				: changePackageService({ action: 'update', key, name, description })
		);
	}

	function setArchived(service: PackageService, archived: boolean) {
		const command: PackageServiceChange = {
			action: archived ? 'archive' : 'restore',
			key: service.key
		};
		void run(service.key, () => changePackageService(command));
	}
</script>

{#snippet serviceForm(key: string)}
	<form class="service-list__form" onsubmit={submit}>
		<Input
			id={`service-list-name-${key}`}
			size="small"
			label="Service name"
			maxlength={80}
			bind:value={name}
			invalid={Boolean(fieldErrors.name)}
			errorMessage={fieldErrors.name}
		/>
		<Textarea
			id={`service-list-description-${key}`}
			label="Starting wording for packages"
			rows={2}
			maxlength={300}
			bind:value={description}
			invalid={Boolean(fieldErrors.description)}
			errorMessage={fieldErrors.description}
		/>
		{#if formError}<p class="service-list__error" role="alert">{formError}</p>{/if}
		<div class="service-list__form-actions">
			<Button size="small" variant="secondary" onclick={() => (editing = null)}>Cancel</Button>
			<Button size="small" type="submit" loading={pending === key}
				>{key === 'new' ? 'Add service' : 'Save'}</Button
			>
		</div>
	</form>
{/snippet}

<Dialog {open} title="Your service list" size="large" {onClose}>
	<div class="service-list">
		<p class="service-list__intro">
			The services Uplift sells. Tick them in each package. A client is asked a service's setup
			questions only when their package includes it. Renaming one here does not change what a
			published package promised.
		</p>

		<ul class="service-list__items">
			{#each services as service (service.key)}
				<li class="service-list__item" class:service-list__item--archived={service.archived_at}>
					{#if editing === service.key}
						{@render serviceForm(service.key)}
					{:else}
						<div class="service-list__text">
							<p class="service-list__name">
								{service.name}
								{#if service.archived_at}<Badge status="inactive" size="small">Archived</Badge>{/if}
							</p>
							{#if service.description}
								<p class="service-list__description">{service.description}</p>
							{/if}
							<p class="service-list__usage">
								{service.package_count === 0
									? 'In no package yet'
									: `In ${service.package_count} package${service.package_count === 1 ? '' : 's'}`}
							</p>
						</div>
						<div class="service-list__actions">
							{#if !service.archived_at}
								<Button
									size="small"
									variant="tertiary"
									disabled={pending !== null}
									onclick={() => startEdit(service)}>Edit</Button
								>
							{/if}
							<Button
								size="small"
								variant="tertiary"
								variation={service.archived_at ? 'work' : 'subtle'}
								disabled={pending !== null}
								loading={pending === service.key && editing !== service.key}
								onclick={() => setArchived(service, !service.archived_at)}
								>{service.archived_at ? 'Restore' : 'Archive'}</Button
							>
						</div>
					{/if}
				</li>
			{/each}
		</ul>

		{#if editing === 'new'}
			{@render serviceForm('new')}
		{:else}
			<div>
				<Button
					size="small"
					variant="secondary"
					disabled={pending !== null}
					onclick={() => startEdit(null)}>Add a service</Button
				>
			</div>
		{/if}
		{#if formError && editing === null}
			<p class="service-list__error" role="alert">{formError}</p>
		{/if}
	</div>
</Dialog>

<style lang="scss">
	.service-list {
		display: grid;
		gap: var(--space-base);

		&__intro {
			margin: 0;
			color: var(--color-text--secondary);
			line-height: var(--typography--lineHeight-base);
		}

		&__items {
			display: grid;
			margin: 0;
			padding: 0;
			list-style: none;
		}

		&__item {
			display: flex;
			align-items: flex-start;
			justify-content: space-between;
			gap: var(--space-base);
			padding: var(--space-base) 0;
			border-top: var(--border-base) solid var(--color-border);

			&:first-child {
				border-top: 0;
			}

			&--archived .service-list__name,
			&--archived .service-list__description {
				color: var(--color-text--secondary);
			}
		}

		&__text {
			display: grid;
			gap: var(--space-smallest);
			min-width: 0;
		}

		&__name {
			display: flex;
			flex-wrap: wrap;
			align-items: center;
			gap: var(--space-small);
			margin: 0;
			font-weight: 600;
		}

		&__description,
		&__usage {
			margin: 0;
			line-height: var(--typography--lineHeight-base);
		}

		&__usage {
			color: var(--color-text--secondary);
			font-size: var(--typography--fontSize-small);
		}

		&__actions {
			display: flex;
			flex-shrink: 0;
			gap: var(--space-smaller);
		}

		&__form {
			display: grid;
			flex: 1;
			gap: var(--space-slim);
			padding: var(--space-base);
			border-radius: var(--radius-base);
			background: var(--color-surface--background);
		}

		&__form-actions {
			display: flex;
			justify-content: flex-end;
			gap: var(--space-small);
		}

		&__error {
			margin: 0;
			color: var(--color-critical);
			font-size: var(--typography--fontSize-small);
		}
	}

	@media (max-width: 640px) {
		.service-list__item {
			flex-direction: column;
		}
	}
</style>
