<script lang="ts">
	let { surface }: { surface: string } = $props();
</script>

<section class="proof-surface" data-proof-surface="classic">
	<h2>{surface === 'details' ? 'Job details' : 'Work overview'}</h2>
	<p>Garden maintenance · Upcoming</p>
	<p>Shared record example, independent presentation module.</p>
</section>

<style lang="scss">
	.proof-surface {
		min-height: 180px;
		padding: 24px;
		margin-top: 24px;
		background: white;
		border: 1px solid #2563eb;
		border-radius: 12px;
	}
</style>
