<script lang="ts">
	import CardHeader from '$lib/components/ui/CardHeader.svelte';
	import IconTile from '$lib/components/ui/IconTile.svelte';
	import SegmentedControl from '$lib/components/ui/SegmentedControl.svelte';
	import eyeIcon from '@tabler/icons/outline/eye.svg?raw';
	import fileTextIcon from '@tabler/icons/outline/file-text.svg?raw';
	import folderIcon from '@tabler/icons/outline/folder.svg?raw';
	import messageIcon from '@tabler/icons/outline/message-circle.svg?raw';
	import lockIcon from '@tabler/icons/outline/lock.svg?raw';
	import leafIcon from '@tabler/icons/outline/leaf.svg?raw';
	import photoIcon from '@tabler/icons/outline/photo.svg?raw';
	import minusIcon from '@tabler/icons/outline/minus.svg?raw';
	import sparklesIcon from '@tabler/icons/outline/click.svg?raw';
	import checkIcon from '@tabler/icons/outline/check.svg?raw';
	import downloadIcon from '@tabler/icons/outline/download.svg?raw';
	import sendIcon from '@tabler/icons/outline/send.svg?raw';
	import fileIcon from '@tabler/icons/outline/file.svg?raw';
	import panelLeftIcon from '@tabler/icons/outline/layout-sidebar.svg?raw';

	// "What customers see" on the Branding page (Pencil: "Batch 65 · Branding", Brand studio): the logo and
	// colour on a picture of the customer page they reach — the quote, shared files or the website chat — so
	// the owner sees the result before saving. The customer page keeps its own light colours in dark mode.
	let {
		logoUrl,
		colour,
		name,
		place,
		businessName
	}: {
		/** The logo as it will be once saved: a picked file, the saved one, or null. */
		logoUrl: string | null;
		colour: string;
		name: string;
		/** The small line under the name (trade and place), or null. */
		place: string | null;
		/** Used in the team note ("…at the top of the sidebar for everyone in …"). */
		businessName: string;
	} = $props();

	let view = $state('quote');
	const views = [
		{ value: 'quote', label: 'Quote page', icon: fileTextIcon },
		{ value: 'files', label: 'Shared files', icon: folderIcon },
		{ value: 'chat', label: 'Website chat', icon: messageIcon }
	];

	const uses = $derived(
		{
			quote: [
				{ icon: photoIcon, tone: 'inactive', text: 'Logo at the top' },
				{ icon: minusIcon, tone: 'informative', text: 'Colour line' },
				{ icon: sparklesIcon, tone: 'success', text: 'Colour on the main button' }
			],
			files: [
				{ icon: photoIcon, tone: 'inactive', text: 'Logo at the top' },
				{ icon: minusIcon, tone: 'informative', text: 'Colour line' },
				{ icon: sparklesIcon, tone: 'success', text: 'Colour on the download button' }
			],
			chat: [
				{ icon: photoIcon, tone: 'inactive', text: 'Logo in the chat header' },
				{ icon: minusIcon, tone: 'informative', text: 'Header colour' },
				{ icon: sparklesIcon, tone: 'success', text: 'Colour on the Send button' }
			]
		}[view as 'quote' | 'files' | 'chat']
	);

	const title = $derived(
		({ quote: 'Quote from', files: 'Files from', chat: 'Chat with' } as Record<string, string>)[
			view
		] ?? ''
	);
</script>

{#snippet mark(size: number)}
	{#if logoUrl}
		<img class="brand-preview__logo" style:--logo-size="{size}px" src={logoUrl} alt="" />
	{:else}
		<span class="brand-preview__leaf" style:--logo-size="{size}px">
			<!-- eslint-disable-next-line svelte/no-at-html-tags -- trusted build-time Tabler icon -->
			{@html leafIcon}
		</span>
	{/if}
{/snippet}

<div class="brand-preview" style:--brand={colour}>
	<section class="brand-preview__card" aria-labelledby="brand-preview-title">
		<CardHeader
			id="brand-preview-title"
			level={2}
			title="What customers see"
			hint="Changes show here at once. Nothing is sent until you save."
			icon={eyeIcon}
			tone="informative"
		/>
		<div class="brand-preview__body">
			<div class="brand-preview__switch">
				<SegmentedControl
					ariaLabel="Customer page to preview"
					options={views}
					bind:value={view}
					white
				/>
			</div>

			<div class="brand-preview__stage">
				<div class="brand-preview__page" class:brand-preview__page--chat={view === 'chat'}>
					<div class="brand-preview__bar" aria-hidden="true">
						<span></span><span></span><span></span>
						<p>
							<!-- eslint-disable-next-line svelte/no-at-html-tags -- trusted build-time Tabler icon -->
							<span class="brand-preview__lock">{@html lockIcon}</span>{title}
							{name}
						</p>
					</div>

					{#if view === 'chat'}
						<div class="brand-preview__chat-head">
							{@render mark(28)}
							<div>
								<strong>{name}</strong>
								<span>We usually reply in a few minutes</span>
							</div>
						</div>
						<div class="brand-preview__chat-body">
							<p class="brand-preview__bubble">Hi! How can we help with your project?</p>
							<p class="brand-preview__bubble brand-preview__bubble--mine">
								Can you come and look at my kitchen?
							</p>
							<div class="brand-preview__chat-send">
								<span>Write a message…</span>
								<span class="brand-preview__send">
									<!-- eslint-disable-next-line svelte/no-at-html-tags -- trusted build-time Tabler icon -->
									{@html sendIcon}Send
								</span>
							</div>
						</div>
					{:else}
						<div class="brand-preview__line"></div>
						<div class="brand-preview__head">
							<div class="brand-preview__identity">
								{@render mark(36)}
								<div>
									<strong>{name}</strong>
									{#if place}<span>{place}</span>{/if}
								</div>
							</div>
							<div class="brand-preview__ref">
								{#if view === 'quote'}<span>Quote</span><strong>#1042</strong>{:else}<span
										>Shared</span
									><strong>3 files</strong>{/if}
							</div>
						</div>

						{#if view === 'quote'}
							<div class="brand-preview__doc">
								<h3>Kitchen remodel</h3>
								<p class="brand-preview__for">For Sarah Lee · 18 Cedar Lane · Oct 22</p>
								<dl>
									<div>
										<dt>Cabinets and fitting</dt>
										<dd>$7,200.00</dd>
									</div>
									<div>
										<dt>Quartz worktop</dt>
										<dd>$3,480.00</dd>
									</div>
									<div>
										<dt>Labour · 4 days</dt>
										<dd>$1,800.00</dd>
									</div>
								</dl>
								<p class="brand-preview__total"><span>Total</span><strong>$12,480.00</strong></p>
								<div class="brand-preview__actions">
									<span class="brand-preview__main">
										<!-- eslint-disable-next-line svelte/no-at-html-tags -- trusted build-time Tabler icon -->
										{@html checkIcon}Approve quote
									</span>
									<span class="brand-preview__plain">Ask a question</span>
								</div>
							</div>
						{:else}
							<div class="brand-preview__doc">
								<h3>Your project files</h3>
								<p class="brand-preview__for">Shared with you by {name}</p>
								<ul>
									{#each [['Site plan.pdf', '1.2 MB'], ['Cabinet options.pdf', '860 KB'], ['Kitchen today.jpg', '2.4 MB']] as [file, size] (file)}
										<li>
											<!-- eslint-disable-next-line svelte/no-at-html-tags -- trusted build-time Tabler icon -->
											<span class="brand-preview__file">{@html fileIcon}</span>
											<span>{file}</span><em>{size}</em>
										</li>
									{/each}
								</ul>
								<div class="brand-preview__actions">
									<span class="brand-preview__main">
										<!-- eslint-disable-next-line svelte/no-at-html-tags -- trusted build-time Tabler icon -->
										{@html downloadIcon}Download all
									</span>
								</div>
							</div>
						{/if}
					{/if}
				</div>
			</div>

			<ul class="brand-preview__uses">
				{#each uses as use (use.text)}
					<li><IconTile icon={use.icon} tone={use.tone} size={24} />{use.text}</li>
				{/each}
			</ul>
		</div>
	</section>

	<aside class="brand-preview__team">
		<IconTile icon={panelLeftIcon} tone="inactive" size={32} />
		<div>
			<strong>Your team sees the logo too</strong>
			<p>It replaces the leaf at the top of the sidebar for everyone in {businessName}.</p>
		</div>
	</aside>
</div>

<style lang="scss">
	.brand-preview {
		display: flex;
		flex-direction: column;
		gap: var(--space-base);
		min-width: 0;

		&__card {
			background: var(--color-surface);
			border: var(--border-base) solid var(--color-border);
			border-radius: var(--radius-large);
			overflow: hidden;
		}
		&__body {
			display: flex;
			flex-direction: column;
			gap: var(--space-base);
			padding: var(--space-medium);
		}
		&__switch {
			align-self: flex-start;
		}
		&__stage {
			padding: var(--space-large) var(--space-larger);
			background: var(--color-surface--background--subtle);
			border-radius: var(--radius-large);
		}

		// The customer's page: always light, whatever the staff member's theme is.
		&__page {
			// The mock keeps the light palette's own values: the app's tokens turn dark with the theme.
			--paper-ink: #032b3a;
			--paper-quiet: #5d757e;
			--paper-edge: #dadfe2;
			--paper-line: #eef1f2;
			--paper-soft: #f9fafb;
			overflow: hidden;
			color: var(--paper-ink);
			background: var(--color-white);
			border-radius: var(--radius-tile-large);
			box-shadow:
				0 2px 4px color-mix(in srgb, var(--color-black) 6%, transparent),
				0 12px 28px color-mix(in srgb, var(--color-black) 10%, transparent);
			font-size: var(--typography--fontSize-small);
		}
		&__bar {
			display: flex;
			align-items: center;
			gap: 6px;
			padding: var(--space-small) var(--space-slim);
			background: var(--paper-soft);

			> span {
				width: 8px;
				height: 8px;
				border-radius: var(--radius-circle);
				background: var(--paper-edge);
			}
			p {
				display: flex;
				flex: 1;
				align-items: center;
				gap: var(--space-smaller);
				margin: 0 0 0 var(--space-small);
				padding: 2px var(--space-slim);
				border-radius: var(--radius-circle);
				background: var(--color-white);
				color: var(--paper-quiet);
				font-size: var(--typography--fontSize-smaller);
			}
		}
		&__lock {
			display: inline-flex;
			:global(svg) {
				width: 12px;
				height: 12px;
			}
		}
		&__line {
			height: 4px;
			background: var(--brand);
		}
		&__head {
			display: flex;
			align-items: center;
			justify-content: space-between;
			padding: var(--space-base) var(--space-large);
			border-bottom: var(--border-base) solid var(--paper-line);
		}
		&__identity {
			display: flex;
			align-items: center;
			gap: var(--space-small);

			div {
				display: flex;
				flex-direction: column;
			}
			strong {
				font-size: var(--typography--fontSize-large);
				line-height: 1.1;
			}
			div > span {
				color: var(--paper-quiet);
				font-size: var(--typography--fontSize-smaller);
				font-weight: 600;
				letter-spacing: 0.08em;
				text-transform: uppercase;
			}
		}
		&__logo {
			width: var(--logo-size);
			height: var(--logo-size);
			object-fit: contain;
			border-radius: var(--radius-small);
		}
		&__leaf {
			display: inline-flex;
			flex: 0 0 auto;
			align-items: center;
			justify-content: center;
			width: var(--logo-size);
			height: var(--logo-size);
			color: var(--color-white);
			background: var(--brand);
			border-radius: var(--radius-tile-large);

			:global(svg) {
				width: 60%;
				height: 60%;
			}
		}
		&__ref {
			display: flex;
			flex-direction: column;
			align-items: flex-end;
			color: var(--paper-quiet);
			font-size: var(--typography--fontSize-smaller);
			font-weight: 600;
			letter-spacing: 0.08em;
			text-transform: uppercase;

			strong {
				color: var(--paper-ink);
				font-size: var(--typography--fontSize-base);
			}
		}
		&__doc {
			display: flex;
			flex-direction: column;
			gap: var(--space-small);
			padding: var(--space-large);

			h3 {
				margin: 0;
				font-size: var(--typography--fontSize-larger);
				font-weight: 700;
			}
			dl {
				margin: var(--space-small) 0 0;
			}
			dl div,
			li {
				display: flex;
				align-items: center;
				justify-content: space-between;
				gap: var(--space-small);
				padding: var(--space-small) 0;
				border-bottom: var(--border-base) solid var(--paper-line);
				font-size: var(--typography--fontSize-base);
			}
			dd {
				margin: 0;
				font-weight: 600;
				font-variant-numeric: tabular-nums;
			}
			ul {
				margin: 0;
				padding: 0;
				list-style: none;
			}
			li span:nth-child(2) {
				flex: 1;
			}
			li em {
				color: var(--paper-quiet);
				font-style: normal;
				font-size: var(--typography--fontSize-smaller);
			}
		}
		&__file {
			display: inline-flex;
			color: var(--paper-quiet);
			:global(svg) {
				width: 16px;
				height: 16px;
			}
		}
		&__for {
			margin: 0;
			color: var(--paper-quiet);
			font-size: var(--typography--fontSize-smaller);
		}
		&__total {
			display: flex;
			align-items: baseline;
			justify-content: space-between;
			margin: var(--space-smaller) 0 0;

			strong {
				font-size: var(--typography--fontSize-largest);
				font-variant-numeric: tabular-nums;
			}
		}
		&__actions {
			display: flex;
			gap: var(--space-small);
			margin-top: var(--space-small);
		}
		&__main,
		&__plain,
		&__send {
			display: inline-flex;
			align-items: center;
			justify-content: center;
			gap: var(--space-smaller);
			padding: var(--space-small) var(--space-base);
			border-radius: var(--radius-base);
			font-size: var(--typography--fontSize-base);
			font-weight: 600;

			:global(svg) {
				width: 16px;
				height: 16px;
			}
		}
		&__main,
		&__send {
			flex: 1;
			color: var(--color-white);
			background: var(--brand);
		}
		&__send {
			flex: 0 0 auto;
			padding: var(--space-smaller) var(--space-slim);
		}
		&__plain {
			border: var(--border-base) solid var(--paper-edge);
		}

		&__chat-head {
			display: flex;
			align-items: center;
			gap: var(--space-slim);
			padding: var(--space-base) var(--space-large);
			color: var(--color-white);
			background: var(--brand);

			div {
				display: flex;
				flex-direction: column;
			}
			span {
				font-size: var(--typography--fontSize-smaller);
				opacity: 0.85;
			}
		}
		&__chat-body {
			display: flex;
			flex-direction: column;
			gap: var(--space-small);
			padding: var(--space-large);
			background: var(--paper-soft);
		}
		&__bubble {
			align-self: flex-start;
			max-width: 80%;
			margin: 0;
			padding: var(--space-small) var(--space-slim);
			background: var(--color-white);
			border-radius: var(--radius-large);
			font-size: var(--typography--fontSize-base);

			&--mine {
				align-self: flex-end;
				color: var(--color-white);
				background: var(--brand);
			}
		}
		&__chat-send {
			display: flex;
			align-items: center;
			justify-content: space-between;
			margin-top: var(--space-small);
			padding: var(--space-smaller);
			padding-left: var(--space-slim);
			background: var(--color-white);
			border: var(--border-base) solid var(--paper-edge);
			border-radius: var(--radius-circle);
			color: var(--paper-quiet);
		}

		&__uses {
			display: flex;
			flex-wrap: wrap;
			gap: var(--space-base);
			margin: 0;
			padding: 0;
			list-style: none;

			li {
				display: flex;
				align-items: center;
				gap: var(--space-small);
				color: var(--color-text--secondary);
				font-size: var(--typography--fontSize-smaller);
				font-weight: 600;
			}
		}

		&__team {
			display: flex;
			align-items: center;
			gap: var(--space-slim);
			padding: var(--space-slim) var(--space-base);
			background: var(--color-surface);
			border: var(--border-base) solid var(--color-border);
			border-radius: var(--radius-large);

			strong {
				color: var(--color-heading);
				font-size: var(--typography--fontSize-base);
			}
			p {
				margin: 0;
				color: var(--color-text--secondary);
				font-size: var(--typography--fontSize-smaller);
			}
		}
	}
</style>
