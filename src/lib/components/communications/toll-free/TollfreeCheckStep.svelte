<script lang="ts">
	import Button from '$lib/components/ui/Button.svelte';
	import IconTile from '$lib/components/ui/IconTile.svelte';
	import Banner from '$lib/components/ui/Banner.svelte';
	import type { TollfreeBusiness, TollfreePicture } from '$lib/communications/sms-tollfree';
	import { countryName } from '$lib/components/communications/paperwork/paperwork-ui';
	import buildingIcon from '@tabler/icons/outline/building.svg?raw';
	import userIcon from '@tabler/icons/outline/user.svg?raw';
	import messageIcon from '@tabler/icons/outline/message.svg?raw';
	import photoIcon from '@tabler/icons/outline/photo.svg?raw';
	import pencilIcon from '@tabler/icons/outline/pencil.svg?raw';
	import sendIcon from '@tabler/icons/outline/send.svg?raw';
	import floppyIcon from '@tabler/icons/outline/device-floppy.svg?raw';
	import arrowLeftIcon from '@tabler/icons/outline/arrow-left.svg?raw';

	// Step 4 of the toll-free check (`concept.pen` board `SCpaW`, "Check and send"): a read-back of each step,
	// then Send for review. Without `onSend` it is the read-only copy of what was sent.
	let {
		business,
		pictures,
		problems = [],
		sendError = '',
		saving = false,
		sending = false,
		blocked = false,
		onChange,
		onBack,
		onSave,
		onSend
	}: {
		business: TollfreeBusiness;
		pictures: TollfreePicture[];
		/** What the server found missing, in plain words. */
		problems?: string[];
		sendError?: string;
		saving?: boolean;
		sending?: boolean;
		/** A picture is still uploading, or another tab changed the check. */
		blocked?: boolean;
		onChange?: (step: number) => void;
		onBack?: () => void;
		onSave?: () => void;
		onSend?: () => void;
	} = $props();

	const CONSENT: Record<string, string> = {
		website_form: 'Website form',
		paper_form: 'Paper form',
		verbal: 'In person or on a call',
		text_initiated: 'Customer texted us first'
	};
	const address = $derived(business.business_address);
	const person = $derived(business.authorized_representative);
	const rows = $derived([
		{
			step: 1,
			icon: buildingIcon,
			title: business.business_type === 'sole_proprietorship' ? 'Your business' : 'Business',
			lines: [
				business.legal_business_name,
				[
					business.business_registration_id,
					countryName(business.business_registration_country ?? address.country_code)
				]
					.filter(Boolean)
					.join(' · '),
				[address.line1, address.line2, address.city, address.region, address.postal_code]
					.filter(Boolean)
					.join(', ')
			]
		},
		{
			step: 1,
			icon: userIcon,
			title: 'Person in charge',
			lines: [
				[person.first_name, person.last_name].filter(Boolean).join(' '),
				[person.email, person.phone_number].filter(Boolean).join(' · ')
			]
		},
		{
			step: 2,
			icon: messageIcon,
			title: 'Texting',
			lines: [
				business.messaging.description,
				CONSENT[business.messaging.consent_method] ?? '',
				`${business.messaging.sample_messages.filter((text) => text.trim()).length} example texts`
			]
		},
		{
			step: 3,
			icon: photoIcon,
			title: 'Proof of consent',
			lines: [
				pictures.length
					? `${pictures.length} ${pictures.length === 1 ? 'picture' : 'pictures'} added`
					: 'No picture yet'
			]
		}
	]);
</script>

<!-- The inline SVG strings are trusted build-time Tabler icon imports. -->
<!-- eslint-disable svelte/no-at-html-tags -->
<div class="tollfree-check">
	<ul class="tollfree-check__rows">
		{#each rows as row (row.title)}
			<li>
				<IconTile icon={row.icon} tone="conversation" size={32} />
				<div class="tollfree-check__copy">
					<strong>{row.title}</strong>
					{#each row.lines.filter(Boolean) as line, index (index)}<span>{line}</span>{/each}
				</div>
				{#if onChange}
					<Button variant="quiet" size="small" onclick={() => onChange(row.step)}>
						<span aria-hidden="true">{@html pencilIcon}</span>
						Change
					</Button>
				{/if}
			</li>
		{/each}
	</ul>

	{#if problems.length}
		<Banner type="error">
			Finish these before sending:
			<ul class="tollfree-check__problems">
				{#each problems as problem (problem)}<li>{problem}</li>{/each}
			</ul>
		</Banner>
	{:else if sendError}
		<Banner type="error">{sendError}</Banner>
	{/if}

	{#if onSend}
		<section class="tollfree-check__send" aria-labelledby="tollfree-send-title">
			<div class="tollfree-check__send-copy">
				<h2 id="tollfree-send-title">Ready to send for review?</h2>
				<p>
					Check your answers. Texting turns on only after the phone company approves this number.
				</p>
			</div>
			<div class="tollfree-check__actions">
				{#if onBack}
					<Button variant="quiet" onclick={onBack}>
						<span aria-hidden="true">{@html arrowLeftIcon}</span>
						Back
					</Button>
				{/if}
				<Button variant="secondary" loading={saving} disabled={blocked || sending} onclick={onSave}>
					{#if !saving}<span aria-hidden="true">{@html floppyIcon}</span>{/if}
					Save draft
				</Button>
				<Button loading={sending} disabled={blocked || saving} onclick={onSend}>
					{#if !sending}<span aria-hidden="true">{@html sendIcon}</span>{/if}
					{sending ? 'Sending…' : 'Send for review'}
				</Button>
			</div>
		</section>
	{/if}
</div>

<!-- eslint-enable svelte/no-at-html-tags -->

<style lang="scss">
	.tollfree-check {
		display: flex;
		flex-direction: column;
		gap: var(--space-base);

		&__rows {
			display: grid;
			margin: 0;
			padding: 0;
			border: var(--border-base) solid var(--color-border);
			border-radius: var(--radius-large);
			background: var(--color-surface);
			list-style: none;

			li {
				display: flex;
				align-items: flex-start;
				gap: var(--space-slim);
				padding: var(--space-base) var(--space-medium);

				& + li {
					border-top: var(--border-base) solid var(--color-border);
				}
			}
		}

		&__copy {
			display: grid;
			flex: 1;
			gap: 2px;
			min-width: 0;

			strong {
				color: var(--color-heading);
				font-size: var(--typography--fontSize-base);
				font-weight: 600;
			}

			span {
				overflow: hidden;
				color: var(--color-text--secondary);
				font-size: var(--typography--fontSize-smaller);
				text-overflow: ellipsis;
				white-space: nowrap;
			}
		}

		&__problems {
			margin: var(--space-smaller) 0 0;
			padding-left: var(--space-medium);
		}

		&__send {
			display: flex;
			align-items: center;
			gap: var(--space-base);
			padding: var(--space-medium);
			border: var(--border-base) solid var(--color-success--surface);
			border-radius: var(--radius-large);
			background: var(--color-success--surface);
		}

		&__send-copy {
			display: grid;
			flex: 1;
			gap: 2px;
			min-width: 0;

			h2 {
				margin: 0;
				color: var(--color-heading);
				font-size: var(--typography--fontSize-large);
				font-weight: 700;
			}

			p {
				margin: 0;
				color: var(--color-text--secondary);
				font-size: var(--typography--fontSize-smaller);
			}
		}

		&__actions {
			display: flex;
			flex: none;
			align-items: center;
			gap: var(--space-small);
		}
	}
</style>
