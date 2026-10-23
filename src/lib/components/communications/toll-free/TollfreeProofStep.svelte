<script lang="ts">
	import SetupStepCard from '$lib/components/layout/SetupStepCard.svelte';
	import Banner from '$lib/components/ui/Banner.svelte';
	import Button from '$lib/components/ui/Button.svelte';
	import IconTile from '$lib/components/ui/IconTile.svelte';
	import { fileSize } from '$lib/components/communications/paperwork/paperwork-ui';
	import { TOLLFREE_PICTURE_LIMIT, tollfreePictureUrl } from '$lib/communications/sms-tollfree';
	import type { TollfreeDraft } from './tollfree-draft.svelte';
	import photoIcon from '@tabler/icons/outline/photo.svg?raw';
	import photoPlusIcon from '@tabler/icons/outline/photo-plus.svg?raw';
	import uploadIcon from '@tabler/icons/outline/cloud-upload.svg?raw';
	import alertIcon from '@tabler/icons/outline/alert-triangle.svg?raw';
	import refreshIcon from '@tabler/icons/outline/refresh.svg?raw';
	import trashIcon from '@tabler/icons/outline/trash.svg?raw';
	import arrowLeftIcon from '@tabler/icons/outline/arrow-left.svg?raw';
	import arrowRightIcon from '@tabler/icons/outline/arrow-right.svg?raw';

	// Step 3 of the toll-free check (`concept.pen` board `SCpaW`, "Show how customers agree" and "Every state"):
	// one to five pictures of the sign-up, each sent up with its progress; a failed one can be tried again.
	let {
		draft,
		error,
		continuing,
		onBack,
		onContinue
	}: {
		draft: TollfreeDraft;
		/** Why a send was refused over the pictures. */
		error: string;
		continuing: boolean;
		onBack: () => void;
		onContinue: () => void;
	} = $props();

	let dragging = $state(false);
	const upload = $derived(draft.upload);
	const busy = $derived(Boolean(upload && !upload.problem));
	const full = $derived(draft.pictures.length >= TOLLFREE_PICTURE_LIMIT);

	function choose(files: FileList | null | undefined) {
		const file = files?.[0];
		if (file) void draft.addPicture(file);
	}
</script>

<!-- The inline SVG strings are trusted build-time Tabler icon imports. -->
<!-- eslint-disable svelte/no-at-html-tags -->
<SetupStepCard
	title="Show how customers agree"
	hint="A clear screenshot or photo helps the phone company check the sign-up."
	icon={photoIcon}
	tone="conversation"
>
	<div class="tollfree-proof">
		<Banner type="notice"
			>Show the phone-number field, the consent words and the button customers press.</Banner
		>

		{#if busy && upload}
			<div class="tollfree-proof__state" role="status">
				<IconTile icon={uploadIcon} tone="informative" size={32} />
				<div class="tollfree-proof__state-copy">
					<strong>Uploading your picture · {Math.round(upload.progress * 100)}%</strong>
					<span>Save and Send stay unavailable until the picture finishes uploading.</span>
					<progress
						value={Math.round(upload.progress * 100)}
						max="100"
						aria-label="Picture upload progress"
					></progress>
				</div>
			</div>
		{:else if upload?.problem}
			<div class="tollfree-proof__state tollfree-proof__state--failed" role="alert">
				<IconTile icon={alertIcon} tone="critical" size={32} />
				<div class="tollfree-proof__state-copy">
					<strong>The picture did not upload</strong>
					<span>{upload.problem}</span>
				</div>
				<Button variant="secondary" size="small" onclick={() => draft.retryPicture()}>
					<span aria-hidden="true">{@html refreshIcon}</span>
					Try again
				</Button>
			</div>
		{/if}

		{#if !full}
			<label
				class={['tollfree-proof__drop', dragging && 'tollfree-proof__drop--over']}
				ondragover={(event) => {
					event.preventDefault();
					dragging = true;
				}}
				ondragleave={() => (dragging = false)}
				ondrop={(event) => {
					event.preventDefault();
					dragging = false;
					if (!busy) choose(event.dataTransfer?.files);
				}}
			>
				<span class="tollfree-proof__drop-icon" aria-hidden="true">{@html photoPlusIcon}</span>
				<strong>Add a picture of the sign-up</strong>
				<span>Add up to {TOLLFREE_PICTURE_LIMIT} clear pictures · JPG or PNG, 5 MB each</span>
				<input
					type="file"
					accept="image/jpeg,image/png"
					disabled={busy || draft.stale}
					onchange={(event) => {
						choose(event.currentTarget.files);
						event.currentTarget.value = '';
					}}
				/>
			</label>
		{/if}

		{#if draft.pictures.length}
			<ul class="tollfree-proof__pictures" aria-label="Pictures added">
				{#each draft.pictures as picture (picture.id)}
					<li>
						<img src={tollfreePictureUrl(picture.public_token)} alt="" loading="lazy" />
						<span class="tollfree-proof__picture-copy">
							<strong>{picture.file_name}</strong>
							<span>{fileSize(picture.size_bytes)}</span>
						</span>
						<Button
							variant="quiet"
							size="small"
							loading={draft.removing === picture.id}
							disabled={busy || (draft.removing !== null && draft.removing !== picture.id)}
							onclick={() => draft.removePicture(picture.id)}
						>
							{#if draft.removing !== picture.id}<span aria-hidden="true">{@html trashIcon}</span
								>{/if}
							Remove
						</Button>
					</li>
				{/each}
			</ul>
		{/if}

		{#if error}<p class="tollfree-proof__error" role="alert">{error}</p>{/if}
		<p class="tollfree-proof__note">
			The picture link is sent to the phone company for this check.
		</p>
	</div>

	{#snippet footer()}
		<Button variant="secondary" onclick={onBack}>
			<span aria-hidden="true">{@html arrowLeftIcon}</span>
			Back
		</Button>
		<span class="tollfree-proof__foot">Step 3 of 4 · saved as you type</span>
		<Button loading={continuing} disabled={busy} onclick={onContinue}>
			{#if !continuing}<span aria-hidden="true">{@html arrowRightIcon}</span>{/if}
			Continue
		</Button>
	{/snippet}
</SetupStepCard>

<!-- eslint-enable svelte/no-at-html-tags -->

<style lang="scss">
	.tollfree-proof {
		display: flex;
		flex-direction: column;
		gap: var(--space-base);

		&__drop {
			position: relative;
			display: flex;
			flex-direction: column;
			align-items: center;
			gap: var(--space-smaller);
			padding: var(--space-large) var(--space-base);
			border: var(--border-base) dashed var(--color-border--interactive);
			border-radius: var(--radius-base);
			background: var(--color-surface--background--subtle);
			color: var(--color-text--secondary);
			font-size: var(--typography--fontSize-smaller);
			text-align: center;
			cursor: pointer;

			strong {
				color: var(--color-heading);
				font-size: var(--typography--fontSize-base);
				font-weight: 600;
			}

			input {
				position: absolute;
				width: 1px;
				height: 1px;
				opacity: 0;
			}

			&:hover,
			&--over {
				border-color: var(--color-interactive);
				background: var(--color-surface--hover);
			}

			&:focus-within {
				outline: 2px solid var(--color-focus);
				outline-offset: 2px;
			}
		}

		&__drop-icon {
			display: inline-flex;
			color: var(--color-conversation);

			:global(svg) {
				width: 24px;
				height: 24px;
			}
		}

		&__state {
			display: flex;
			align-items: flex-start;
			gap: var(--space-slim);
			padding: var(--space-base);
			border: var(--border-base) solid var(--color-border);
			border-radius: var(--radius-base);
			background: var(--color-surface);

			&--failed {
				align-items: center;
				border-color: var(--color-critical--surface);
			}
		}

		&__state-copy {
			display: flex;
			flex: 1;
			flex-direction: column;
			gap: 2px;
			min-width: 0;

			strong {
				color: var(--color-heading);
				font-size: var(--typography--fontSize-base);
				font-weight: 600;
			}

			span {
				color: var(--color-text--secondary);
				font-size: var(--typography--fontSize-smaller);
			}

			progress {
				width: 100%;
				height: 6px;
				margin-top: var(--space-small);
				accent-color: var(--color-interactive);
			}
		}

		&__pictures {
			display: grid;
			gap: var(--space-small);
			margin: 0;
			padding: 0;
			list-style: none;

			li {
				display: flex;
				align-items: center;
				gap: var(--space-slim);
				padding: var(--space-small);
				border: var(--border-base) solid var(--color-border);
				border-radius: var(--radius-base);
				background: var(--color-surface);
			}

			img {
				flex: none;
				width: 48px;
				height: 48px;
				border-radius: var(--radius-small);
				background: var(--color-surface--background--subtle);
				object-fit: cover;
			}
		}

		&__picture-copy {
			display: grid;
			flex: 1;
			gap: 2px;
			min-width: 0;

			strong {
				overflow: hidden;
				color: var(--color-heading);
				font-size: var(--typography--fontSize-base);
				font-weight: 600;
				text-overflow: ellipsis;
				white-space: nowrap;
			}

			span {
				color: var(--color-text--secondary);
				font-size: var(--typography--fontSize-smaller);
			}
		}

		&__error {
			margin: 0;
			color: var(--color-critical);
			font-size: var(--typography--fontSize-smaller);
		}

		&__note {
			margin: 0;
			color: var(--color-text--secondary);
			font-size: var(--typography--fontSize-smaller);
		}

		&__foot {
			flex: 1;
			color: var(--color-text--secondary);
			font-size: var(--typography--fontSize-smaller);
			text-align: center;
		}
	}
</style>
