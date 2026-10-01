<script lang="ts">
	import SectionBlock from '$lib/components/layout/SectionBlock.svelte';
	import Input from '$lib/components/ui/Input.svelte';
	import InfoTip from '$lib/components/ui/InfoTip.svelte';
	import SegmentedControl from '$lib/components/ui/SegmentedControl.svelte';
	import { ALLOWANCE_HELP } from '$lib/jafar/allowance-help';
	import {
		allowanceApplies,
		type AllowanceReference,
		type CapabilityReference,
		type EditionAllowance
	} from '$lib/jafar/packages';

	// How much of each feature the package includes. An allowance shows only when the package includes
	// the feature it belongs to; each is a number or unlimited. Safety limits that apply to every package
	// (automation steps, delays) are not set here.
	let {
		allowances,
		capabilities,
		selected,
		values = $bindable(),
		errors = {}
	}: {
		allowances: AllowanceReference[];
		capabilities: CapabilityReference[];
		selected: string[];
		values: EditionAllowance[];
		/** Field errors keyed by allowance key. */
		errors?: Record<string, string>;
	} = $props();

	const applying = $derived(
		allowances.filter((allowance) => allowanceApplies(allowance, selected))
	);
	const notApplying = $derived(
		allowances.filter((allowance) => !allowanceApplies(allowance, selected))
	);

	const unitWords: Record<AllowanceReference['unit'], string> = {
		seats: 'people',
		recipients: 'emails',
		widgets: 'widgets',
		conversations: 'chats',
		recipes: 'automations'
	};

	function valueOf(key: string) {
		return values.find((value) => value.key === key);
	}

	function update(key: string, change: Partial<EditionAllowance>) {
		values = values.map((value) => (value.key === key ? { ...value, ...change } : value));
	}

	function capabilityLabel(key: string | null) {
		return capabilities.find((capability) => capability.key === key)?.label ?? '';
	}

	function counting(allowance: AllowanceReference) {
		if (allowance.unit === 'seats')
			return 'Owner, staff, and pending invitations, counted at one time.';
		return allowance.resets_monthly
			? `Starts again every monthly service period, also on yearly billing.`
			: 'Counted at one time.';
	}
</script>

<SectionBlock
	title="Allowances"
	form
	id="package-allowances"
	hint="Reaching a limit blocks new use with a clear explanation. Nothing already made is removed."
>
	<ul class="package-allowances">
		{#each applying as allowance (allowance.key)}
			{@const value = valueOf(allowance.key)}
			<li class="package-allowances__row" id={`package-allowance-${allowance.key}`}>
				<div class="package-allowances__copy">
					<span class="package-allowances__label">
						{allowance.label}
						{#if ALLOWANCE_HELP[allowance.key]}
							{@const help = ALLOWANCE_HELP[allowance.key]}
							<InfoTip label={`What ${allowance.label} means`} title={allowance.label}>
								<p>{help.what}</p>
								<dl class="package-allowances__help">
									<div class="package-allowances__help-item package-allowances__help-item--counted">
										<dt>What is counted</dt>
										<dd>{help.counts}</dd>
									</div>
									<div class="package-allowances__help-item package-allowances__help-item--limit">
										<dt>When the limit is reached</dt>
										<dd>{help.atLimit}</dd>
									</div>
									<div class="package-allowances__help-item package-allowances__help-item--example">
										<dt>Example</dt>
										<dd>{help.example}</dd>
									</div>
								</dl>
							</InfoTip>
						{/if}
					</span>
					<span class="package-allowances__hint">{counting(allowance)}</span>
				</div>
				<div class="package-allowances__controls">
					<SegmentedControl
						size="small"
						value={value?.state === 'unlimited' ? 'unlimited' : 'numeric'}
						options={[
							{ value: 'numeric', label: 'Limited' },
							{ value: 'unlimited', label: 'Unlimited' }
						]}
						onchange={(state) =>
							update(allowance.key, {
								state: state as EditionAllowance['state'],
								value: state === 'numeric' ? (value?.value ?? null) : null
							})}
					/>
					{#if value?.state !== 'unlimited'}
						<div class="package-allowances__number">
							<Input
								id={`package-allowance-value-${allowance.key}`}
								type="number"
								size="small"
								min="0"
								step="1"
								inputmode="numeric"
								aria-label={`${allowance.label} limit`}
								value={value?.value ?? null}
								oninput={(event: Event) => {
									const raw = (event.currentTarget as HTMLInputElement).value;
									update(allowance.key, {
										state: 'numeric',
										value: raw === '' ? null : Math.max(0, Math.trunc(Number(raw)))
									});
								}}
								invalid={Boolean(errors[allowance.key])}
								errorMessage={errors[allowance.key]}
							/>
							<span class="package-allowances__unit">{unitWords[allowance.unit]}</span>
						</div>
					{/if}
				</div>
			</li>
		{/each}
	</ul>
	{#if notApplying.length > 0}
		<p class="package-allowances__absent">
			Not in this package: {notApplying
				.map(
					(allowance) =>
						`${allowance.label} (comes with ${capabilityLabel(allowance.capability_key)})`
				)
				.join(', ')}.
		</p>
	{/if}
</SectionBlock>

<style lang="scss">
	.package-allowances {
		display: grid;
		margin: 0;
		padding: 0;
		list-style: none;

		&__row {
			display: flex;
			flex-wrap: wrap;
			align-items: flex-start;
			justify-content: space-between;
			gap: var(--space-slim) var(--space-base);
			padding: var(--space-base) 0;
			border-top: var(--border-base) solid var(--color-border);

			&:first-child {
				padding-top: 0;
				border-top: 0;
			}
		}

		&__copy {
			display: grid;
			flex: 1 1 240px;
			gap: var(--space-smallest);
		}

		&__label {
			display: inline-flex;
			align-items: center;
			gap: var(--space-smaller);
			color: var(--color-heading);
			font-weight: 600;
		}

		&__help {
			display: grid;
			gap: var(--space-small);
			margin: 0;
		}

		// Each part of the explanation has its own colour, so a glance tells them apart.
		&__help-item {
			display: grid;
			gap: var(--space-smallest);
			padding: var(--space-small) var(--space-base);
			border-left: 3px solid var(--help-accent);
			border-radius: var(--radius-small);
			background: var(--help-surface);

			dt {
				color: var(--help-text);
				font-size: var(--typography--fontSize-smaller);
				font-weight: 700;
				letter-spacing: var(--typography--letterSpacing-loose);
				text-transform: uppercase;
			}

			dd {
				color: var(--color-text);
			}

			&--counted {
				--help-accent: var(--color-informative);
				--help-surface: var(--color-informative--surface);
				--help-text: var(--color-informative--onSurface);
			}

			&--limit {
				--help-accent: var(--color-warning);
				--help-surface: var(--color-warning--surface);
				--help-text: var(--color-warning--onSurface);
			}

			&--example {
				--help-accent: var(--color-success);
				--help-surface: var(--color-success--surface);
				--help-text: var(--color-success--onSurface);
			}
		}

		&__hint,
		&__unit {
			color: var(--color-text--secondary);
			font-size: var(--typography--fontSize-small);
		}

		// A fixed-width column, so every row's switch and number line up whatever the unit is.
		&__controls {
			display: grid;
			grid-template-columns: auto 260px;
			align-items: start;
			gap: var(--space-small);

			@media (max-width: 560px) {
				grid-template-columns: minmax(0, 1fr);
				width: 100%;
			}
		}

		&__number {
			display: grid;
			grid-template-columns: minmax(0, 1fr) 8.4rem;
			align-items: start;
			gap: var(--space-small);
		}

		&__unit {
			padding-top: var(--space-small);
		}

		&__absent {
			margin: 0;
			color: var(--color-text--secondary);
			font-size: var(--typography--fontSize-small);
			line-height: var(--typography--lineHeight-base);
		}
	}
</style>
