<script lang="ts">
	import SetupStepCard from '$lib/components/layout/SetupStepCard.svelte';
	import Button from '$lib/components/ui/Button.svelte';
	import Banner from '$lib/components/ui/Banner.svelte';
	import {
		chosenDocumentKinds,
		resolveDocumentChoices,
		type PaperworkFix
	} from '$lib/communications/number-paperwork';
	import PaperworkDocumentBox from './PaperworkDocumentBox.svelte';
	import type { PaperworkDraft } from './paperwork-draft.svelte';
	import { countryName } from './paperwork-ui';
	import filesIcon from '@tabler/icons/outline/files.svg?raw';
	import lockIcon from '@tabler/icons/outline/lock.svg?raw';
	import arrowLeftIcon from '@tabler/icons/outline/arrow-left.svg?raw';
	import arrowRightIcon from '@tabler/icons/outline/arrow-right.svg?raw';

	// Step 3 of New paperwork (`concept.pen` board `A0URqF`, Documents): one box per document the country asks
	// for. One document can prove two things (an Australian register extract covers three), so a box whose kind
	// is already chosen above says it is covered instead of asking twice.
	let {
		draft,
		problems,
		continuing,
		uploaded,
		onBack,
		onContinue
	}: {
		draft: PaperworkDraft;
		problems: PaperworkFix[];
		continuing: boolean;
		uploaded: () => Promise<unknown>;
		onBack: () => void;
		onContinue: () => void;
	} = $props();

	const form = $derived(draft.detail.form);
	const choices = $derived(resolveDocumentChoices(form.requirements, draft.documentChoices));
	const boxes = $derived.by(() => {
		const firstFor = new Map<string, string>();
		return form.requirements.map((requirement) => {
			const type = choices[requirement.requirementName] ?? requirement.kinds[0]?.documentType ?? '';
			const coveredBy = firstFor.get(type) ?? null;
			if (!coveredBy) firstFor.set(type, requirement.label);
			return { requirement, type, coveredBy };
		});
	});
	// One document can be asked about in several places; its typed facts are asked once, in its first box.
	const kindFields = $derived(
		new Map(
			chosenDocumentKinds(form.requirements, choices).map((kind) => [
				kind.documentType,
				kind.fields
			])
		)
	);
	const owner = $derived(draft.endUserType === 'business' ? 'a business' : 'a person');

	/** The document's own problem (no file, still checking) and each typed fact's, by field name. */
	function errorsFor(type: string): { file: string | null; fields: Record<string, string> } {
		const mine = problems.filter(
			(fix) => fix.step === 'documents' && fix.target.startsWith(`document:${type}`)
		);
		return {
			file: mine.find((fix) => fix.target === `document:${type}`)?.reason ?? null,
			fields: Object.fromEntries(
				mine
					.filter((fix) => fix.target !== `document:${type}`)
					.map((fix) => [fix.target.split(':')[2], fix.reason])
			)
		};
	}
</script>

<!-- The inline SVG strings are trusted build-time Tabler icon imports. -->
<!-- eslint-disable svelte/no-at-html-tags -->
<SetupStepCard
	title="Documents"
	hint={`What the ${countryName(form.countryCode)} phone company asks ${owner} for`}
	icon={filesIcon}
	tone="conversation"
>
	{#if boxes.length === 0}
		<p class="paperwork-documents__none">
			{countryName(form.countryCode)} asks for no documents for these numbers. Your details are enough.
		</p>
	{/if}
	{#each boxes as box (box.requirement.requirementName)}
		<PaperworkDocumentBox
			{draft}
			requirement={box.requirement}
			chosenType={box.type}
			coveredBy={box.coveredBy}
			fields={kindFields.get(box.type) ?? []}
			document={draft.detail.documents.find((document) => document.document_type === box.type) ??
				null}
			errors={box.coveredBy ? { file: null, fields: {} } : errorsFor(box.type)}
			{uploaded}
		/>
	{/each}
	<Banner type="notice" icon={lockIcon}>
		Your files are kept private. They are only shared with the phone company for this check.
	</Banner>

	{#snippet footer()}
		<Button variant="secondary" onclick={onBack}>
			<span aria-hidden="true">{@html arrowLeftIcon}</span>
			Back
		</Button>
		<span class="paperwork-documents__foot">Step 3 of 4</span>
		<Button loading={continuing} onclick={onContinue}>
			{#if !continuing}<span aria-hidden="true">{@html arrowRightIcon}</span>{/if}
			Continue
		</Button>
	{/snippet}
</SetupStepCard>

<!-- eslint-enable svelte/no-at-html-tags -->

<style lang="scss">
	.paperwork-documents {
		&__none {
			margin: 0;
			color: var(--color-text--secondary);
			font-size: var(--typography--fontSize-base);
		}

		&__foot {
			flex: 1;
			color: var(--color-text--secondary);
			font-size: var(--typography--fontSize-smaller);
			text-align: center;
		}
	}
</style>
