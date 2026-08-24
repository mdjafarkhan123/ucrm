<script lang="ts">
	import Input from '$lib/components/ui/Input.svelte';

	// Same shape as MoneyInput: free typing behind a plain text field, committed to the numeric value on
	// blur. A get/set bind straight to a number round-trips every keystroke through Number(), which strips
	// a trailing "." mid-type and resets the cursor — this is what avoids that.
	let {
		value = $bindable(1),
		id,
		label,
		size = 'base',
		disabled = false,
		placeholder = '0'
	}: {
		value?: number;
		id: string;
		label?: string;
		size?: 'small' | 'base' | 'large';
		disabled?: boolean;
		placeholder?: string;
	} = $props();

	function fromValue(quantity: number) {
		return String(quantity);
	}

	let draft = $state(fromValue(value));
	let focused = $state(false);

	// The external value only overwrites what is being typed once the field is not the one changing it —
	// otherwise a save elsewhere on the page would yank the cursor mid-keystroke.
	$effect(() => {
		if (!focused) draft = fromValue(value);
	});

	function commit() {
		focused = false;
		const parsed = Number(draft);
		if (!Number.isFinite(parsed) || parsed <= 0) {
			draft = fromValue(value);
			return;
		}
		// The column is numeric(12,3); round to what the database will actually store so the field never
		// shows a number it is about to silently change on save.
		value = Math.round(parsed * 1000) / 1000;
		draft = fromValue(value);
	}
</script>

<Input
	{id}
	{label}
	{size}
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
