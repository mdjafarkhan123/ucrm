<script lang="ts">
	import Input from '$lib/components/ui/Input.svelte';

	// Binds a whole-cents integer (minor units, the shape every quote/catalog amount crosses the API
	// boundary as) behind a plain decimal-dollar text field — the same inline-edit shape the Pipeline's
	// estimated-value field already uses. Typing is free text; a blur is where a valid amount becomes the
	// committed minor-unit value, and an invalid one snaps back to the last good one rather than saving junk.
	let {
		value = $bindable(0),
		id,
		label,
		size = 'base',
		required = false,
		invalid = false,
		errorMessage = '',
		disabled = false,
		placeholder = '0.00'
	}: {
		value?: number;
		id: string;
		label?: string;
		size?: 'small' | 'base' | 'large';
		required?: boolean;
		invalid?: boolean;
		errorMessage?: string;
		disabled?: boolean;
		placeholder?: string;
	} = $props();

	function fromMinor(minor: number) {
		return (minor / 100).toFixed(2);
	}

	let draft = $state(fromMinor(value));
	let focused = $state(false);

	// The external value only overwrites what is being typed once the field is not the one changing it —
	// otherwise a save elsewhere on the page would yank the cursor mid-keystroke.
	$effect(() => {
		if (!focused) draft = fromMinor(value);
	});

	function commit() {
		focused = false;
		const parsed = Number(draft.replace(/,/g, ''));
		if (!Number.isFinite(parsed) || parsed < 0) {
			draft = fromMinor(value);
			return;
		}
		value = Math.round(parsed * 100);
		draft = fromMinor(value);
	}
</script>

<Input
	{id}
	{label}
	{size}
	{required}
	{invalid}
	{errorMessage}
	{disabled}
	type="text"
	inputmode="decimal"
	{placeholder}
	bind:value={draft}
	onfocus={() => (focused = true)}
	onblur={commit}
	onkeydown={(event: KeyboardEvent) => {
		if (event.key === 'Enter') (event.currentTarget as HTMLInputElement).blur();
	}}
/>
