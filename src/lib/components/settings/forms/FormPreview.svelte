<script lang="ts">
	import { isChoiceQuestion, type FormContent } from '$lib/forms/types';
	import photoIcon from '@tabler/icons/outline/photo-plus.svg?raw';
	import circleCheckIcon from '@tabler/icons/outline/circle-check.svg?raw';

	// A read-only rendering of the form exactly as a customer would meet it online — the left half of the
	// builder. It never writes; it re-renders live as the rail on the right edits the working copy. Fields are
	// non-interactive on purpose so the preview reads as a picture of the form, not a form to fill in.
	let {
		title,
		description,
		content
	}: {
		title: string;
		description: string;
		content: FormContent;
	} = $props();

	const contact = $derived(content.contact);

	function optionsOf(options: string[] | undefined): string[] {
		return options && options.length > 0 ? options : ['Option one', 'Option two'];
	}
</script>

<div class="form-preview" aria-hidden="true">
	<div class="form-preview__paper">
		<header class="form-preview__head">
			<h3 class="form-preview__title">{title || 'Untitled form'}</h3>
			{#if description.trim()}
				<p class="form-preview__description">{description}</p>
			{/if}
		</header>

		<!-- Contact block — always the first section of a live form and never removable. -->
		<section class="form-preview__section">
			<h4 class="form-preview__section-title">Your details</h4>
			<div class="form-preview__fields">
				<div class="form-preview__field">
					<span class="form-preview__label"
						>Name{#if contact.name.required}<em>*</em>{/if}</span
					>
					<div class="form-preview__control"></div>
				</div>
				{#if contact.email.shown}
					<div class="form-preview__field">
						<span class="form-preview__label"
							>Email{#if contact.email.required}<em>*</em>{/if}</span
						>
						<div class="form-preview__control"></div>
						{#if contact.email.marketing_consent}
							<span class="form-preview__consent">
								<span class="form-preview__box"></span>
								Send me occasional offers and updates by email
							</span>
						{/if}
					</div>
				{/if}
				{#if contact.phone.shown}
					<div class="form-preview__field">
						<span class="form-preview__label"
							>Phone{#if contact.phone.required}<em>*</em>{/if}</span
						>
						<div class="form-preview__control"></div>
						{#if contact.phone.marketing_consent}
							<span class="form-preview__consent">
								<span class="form-preview__box"></span>
								Send me occasional offers and updates by text
							</span>
						{/if}
					</div>
				{/if}
				{#if contact.company.shown}
					<div class="form-preview__field">
						<span class="form-preview__label"
							>Company{#if contact.company.required}<em>*</em>{/if}</span
						>
						<div class="form-preview__control"></div>
					</div>
				{/if}
				{#if contact.address.shown}
					<div class="form-preview__field">
						<span class="form-preview__label"
							>Address{#if contact.address.required}<em>*</em>{/if}</span
						>
						<div class="form-preview__control form-preview__control--tall"></div>
					</div>
				{/if}
			</div>
		</section>

		<!-- Custom sections and their questions. -->
		{#each content.sections as section (section.id)}
			<section class="form-preview__section">
				<h4 class="form-preview__section-title">{section.title || 'Untitled section'}</h4>
				{#if section.questions.length === 0}
					<p class="form-preview__empty">No questions in this section yet.</p>
				{:else}
					<div class="form-preview__fields">
						{#each section.questions as question (question.id)}
							<div class="form-preview__field">
								<span class="form-preview__label"
									>{question.label || 'Untitled question'}{#if question.required}<em>*</em
										>{/if}</span
								>
								{#if question.help}
									<span class="form-preview__help">{question.help}</span>
								{/if}

								{#if question.type === 'short_text' || question.type === 'number'}
									<div class="form-preview__control"></div>
								{:else if question.type === 'long_text'}
									<div class="form-preview__control form-preview__control--tall"></div>
								{:else if question.type === 'dropdown' || question.type === 'dropdown_multi'}
									<div class="form-preview__control form-preview__control--select">
										<span>Choose{question.type === 'dropdown_multi' ? ' one or more' : ''}…</span>
									</div>
								{:else if question.type === 'radio'}
									<div class="form-preview__choices">
										{#each optionsOf(question.options) as option, i (i)}
											<span class="form-preview__choice"
												><span class="form-preview__radio"></span>{option}</span
											>
										{/each}
									</div>
								{:else if question.type === 'checkbox'}
									<div class="form-preview__choices">
										{#each optionsOf(question.options) as option, i (i)}
											<span class="form-preview__choice"
												><span class="form-preview__box"></span>{option}</span
											>
										{/each}
									</div>
								{:else if question.type === 'yes_no'}
									<div class="form-preview__choices form-preview__choices--row">
										<span class="form-preview__choice"
											><span class="form-preview__radio"></span>Yes</span
										>
										<span class="form-preview__choice"
											><span class="form-preview__radio"></span>No</span
										>
									</div>
								{:else if question.type === 'image_upload'}
									<div class="form-preview__upload">
										<!-- eslint-disable-next-line svelte/no-at-html-tags -->
										{@html photoIcon}
										<span>Add a photo</span>
									</div>
								{/if}

								{#if isChoiceQuestion(question.type) && (!question.options || question.options.length === 0)}
									<span class="form-preview__note">Add options in the panel on the right.</span>
								{/if}
							</div>
						{/each}
					</div>
				{/if}
			</section>
		{/each}

		{#if content.photos.enabled}
			<section class="form-preview__section">
				<h4 class="form-preview__section-title">Photos</h4>
				<div class="form-preview__upload">
					<!-- eslint-disable-next-line svelte/no-at-html-tags -->
					{@html photoIcon}
					<span>Add up to {content.photos.max} photo{content.photos.max === 1 ? '' : 's'}</span>
				</div>
			</section>
		{/if}

		<div class="form-preview__submit">Submit</div>

		<div class="form-preview__confirm">
			<span class="form-preview__confirm-icon">
				<!-- eslint-disable-next-line svelte/no-at-html-tags -->
				{@html circleCheckIcon}
			</span>
			<div>
				<strong>{content.confirmation.title || 'Thank you!'}</strong>
				<p>
					{content.confirmation.message || 'We’ve received your request and will be in touch soon.'}
				</p>
				{#if content.confirmation.redirect_url}
					<span class="form-preview__redirect"
						>Then sends the customer to {content.confirmation.redirect_url}</span
					>
				{/if}
			</div>
		</div>
	</div>
</div>

<style lang="scss">
	.form-preview {
		display: flex;
		justify-content: center;

		&__paper {
			display: flex;
			width: 100%;
			max-width: 560px;
			flex-direction: column;
			gap: var(--space-large);
			padding: var(--space-large);
			border: var(--border-base) solid var(--color-border);
			border-radius: var(--radius-large);
			background: var(--color-surface);
			box-shadow: var(--shadow-base);
		}

		&__head {
			display: flex;
			flex-direction: column;
			gap: var(--space-small);
		}

		&__title {
			margin: 0;
			color: var(--color-heading);
			font-size: var(--typography--fontSize-larger);
			font-weight: 700;
			line-height: var(--typography--lineHeight-tight);
		}

		&__description {
			margin: 0;
			color: var(--color-text--secondary);
			font-size: var(--typography--fontSize-base);
			white-space: pre-wrap;
		}

		&__section {
			display: flex;
			flex-direction: column;
			gap: var(--space-slim);
			padding-top: var(--space-large);
			border-top: var(--border-base) solid var(--color-border);

			&:first-of-type {
				padding-top: 0;
				border-top: none;
			}
		}

		&__section-title {
			margin: 0;
			color: var(--color-heading);
			font-size: var(--typography--fontSize-base);
			font-weight: 700;
			text-transform: uppercase;
			letter-spacing: 0.4px;
		}

		&__fields {
			display: flex;
			flex-direction: column;
			gap: var(--space-base);
		}

		&__field {
			display: flex;
			flex-direction: column;
			gap: var(--space-smaller);
		}

		&__label {
			color: var(--color-heading);
			font-size: var(--typography--fontSize-small);
			font-weight: 600;

			em {
				margin-left: var(--space-smallest);
				color: var(--color-critical);
				font-style: normal;
			}
		}

		&__help {
			color: var(--color-text--secondary);
			font-size: var(--typography--fontSize-small);
		}

		&__note {
			color: var(--color-warning--onSurface);
			font-size: var(--typography--fontSize-small);
		}

		&__control {
			height: 40px;
			border: var(--border-base) solid var(--color-border--interactive);
			border-radius: var(--radius-base);
			background: var(--color-surface--background--subtle);

			&--tall {
				height: 72px;
			}

			&--select {
				display: flex;
				align-items: center;
				justify-content: space-between;
				padding: 0 var(--space-base);
				color: var(--color-text--secondary);
				font-size: var(--typography--fontSize-small);

				&::after {
					content: '▾';
					color: var(--color-icon--secondary);
				}
			}
		}

		&__choices {
			display: flex;
			flex-direction: column;
			gap: var(--space-small);

			&--row {
				flex-direction: row;
				gap: var(--space-large);
			}
		}

		&__choice {
			display: inline-flex;
			align-items: center;
			gap: var(--space-small);
			color: var(--color-text);
			font-size: var(--typography--fontSize-base);
		}

		&__radio,
		&__box {
			display: inline-block;
			width: 18px;
			height: 18px;
			flex: 0 0 auto;
			border: var(--border-thick) solid var(--color-border--interactive);
			background: var(--color-surface);
		}

		&__radio {
			border-radius: var(--radius-circle);
		}

		&__box {
			border-radius: var(--radius-small);
		}

		&__consent {
			display: inline-flex;
			align-items: center;
			gap: var(--space-small);
			margin-top: var(--space-smaller);
			color: var(--color-text--secondary);
			font-size: var(--typography--fontSize-small);
		}

		&__upload {
			display: flex;
			flex-direction: column;
			align-items: center;
			justify-content: center;
			gap: var(--space-small);
			padding: var(--space-large);
			border: var(--border-base) dashed var(--color-border--interactive);
			border-radius: var(--radius-base);
			color: var(--color-text--secondary);
			font-size: var(--typography--fontSize-small);

			:global(svg) {
				width: 28px;
				height: 28px;
				color: var(--color-icon--secondary);
			}
		}

		&__submit {
			padding: var(--space-slim) var(--space-large);
			border-radius: var(--radius-base);
			background: var(--color-interactive);
			color: var(--color-surface);
			font-weight: 600;
			text-align: center;
		}

		&__confirm {
			display: flex;
			gap: var(--space-small);
			padding: var(--space-base);
			border-radius: var(--radius-base);
			background: var(--color-success--surface);
			color: var(--color-success--onSurface);

			strong {
				display: block;
				margin-bottom: var(--space-smallest);
			}

			p {
				margin: 0;
				font-size: var(--typography--fontSize-small);
			}
		}

		&__confirm-icon :global(svg) {
			width: 20px;
			height: 20px;
			color: var(--color-success);
		}

		&__redirect {
			display: block;
			margin-top: var(--space-small);
			color: var(--color-success--onSurface);
			font-size: var(--typography--fontSize-small);
			opacity: 0.8;
		}
	}
</style>
