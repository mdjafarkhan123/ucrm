<script lang="ts">
	import { resolve } from '$app/paths';
</script>

<svelte:head>
	<title>Table demo</title>
</svelte:head>

<h1>Table</h1>
<p class="demo-intro">
	Responsive scroll wrapper, hoverable rows, and row-header semantics. Design follows
	.agents/skills/design/tables.md.
</p>

<section class="demo-section">
	<h2>Jobs overview</h2>
	<div class="table-wrap">
		<table class="crm-table">
			<thead>
				<tr>
					<th scope="col">Job</th>
					<th scope="col">Client</th>
					<th scope="col">Status</th>
					<th scope="col">Scheduled</th>
					<th scope="col">Technician</th>
					<th scope="col">Amount</th>
				</tr>
			</thead>
			<tbody>
				<tr>
					<th scope="row">Furnace replacement</th>
					<td>Sarah Mitchell</td>
					<td>In Progress</td>
					<td>Aug 12, 2026</td>
					<td>Derek Tan</td>
					<td>$4,850.00</td>
				</tr>
				<tr>
					<th scope="row">Water heater install</th>
					<td>James O'Brien</td>
					<td>Pending</td>
					<td>Aug 14, 2026</td>
					<td>Unassigned</td>
					<td>$2,150.00</td>
				</tr>
				<tr>
					<th scope="row">AC tune-up</th>
					<td>Priya Sharma</td>
					<td>Completed</td>
					<td>Aug 5, 2026</td>
					<td>Marcus Lee</td>
					<td>$189.00</td>
				</tr>
				<tr>
					<th scope="row">Roof leak repair</th>
					<td>Tom Gallagher</td>
					<td>Quoted</td>
					<td>Aug 18, 2026</td>
					<td>Unassigned</td>
					<td>$1,275.00</td>
				</tr>
				<tr>
					<th scope="row">Gutter cleaning</th>
					<td>Emily Nguyen</td>
					<td>Completed</td>
					<td>Jul 28, 2026</td>
					<td>Derek Tan</td>
					<td>$320.00</td>
				</tr>
			</tbody>
		</table>
	</div>
</section>

<section class="demo-section">
	<h2>Condensed example</h2>
	<div class="table-wrap">
		<table class="crm-table crm-table--condensed">
			<thead>
				<tr>
					<th scope="col">Item</th>
					<th scope="col">Qty</th>
					<th scope="col">Unit price</th>
					<th scope="col">Total</th>
				</tr>
			</thead>
			<tbody>
				<tr>
					<th scope="row">Furnace — 92% efficiency</th>
					<td>1</td>
					<td>$3,900.00</td>
					<td>$3,900.00</td>
				</tr>
				<tr>
					<th scope="row">Thermostat — smart</th>
					<td>1</td>
					<td>$250.00</td>
					<td>$250.00</td>
				</tr>
				<tr>
					<th scope="row">Old unit removal</th>
					<td>1</td>
					<td>$150.00</td>
					<td>$150.00</td>
				</tr>
				<tr>
					<th scope="row">Permit and disposal</th>
					<td>1</td>
					<td>$550.00</td>
					<td>$550.00</td>
				</tr>
			</tbody>
		</table>
	</div>
</section>

<a href={resolve('/demo')} class="demo-back">Back to demo</a>

<style lang="scss">
	// =============================================================================
	// TABLE — design system component demo (mirrors .agents/skills/design/tables.md)
	// =============================================================================

	.table-wrap {
		overflow-x: auto;
		background: var(--color-surface);
		border: var(--border-base) solid var(--color-border);
		border-radius: var(--radius-base);
	}

	.crm-table {
		width: 100%;
		border-collapse: collapse;
		font-family: var(--typography--fontFamily-normal);
		font-size: var(--typography--fontSize-base);
		color: var(--color-text);
		text-align: left;

		th,
		td {
			padding: var(--space-slim);
			vertical-align: middle;
		}

		thead {
			th {
				background: var(--color-surface--background--subtle);
				border-bottom: var(--border-base) solid var(--color-border);
				font-weight: 700;
				color: var(--color-text);
				white-space: nowrap;
			}
		}

		tbody {
			tr {
				background: var(--color-surface);
				border-bottom: var(--border-base) solid var(--color-border);
				transition: background var(--timing-quick) ease;

				&:hover:not(:has(th)) {
					background: var(--color-surface--hover);
				}

				&:last-child {
					border-bottom: none;
				}
			}

			th {
				font-weight: 700;
				color: var(--color-text);
				white-space: nowrap;
				text-align: left;
			}

			td {
				color: var(--color-text--secondary);
			}
		}
	}

	.crm-table--condensed {
		th,
		td {
			padding: var(--space-small) var(--space-large);
		}
	}

	// =============================================================================
	// Demo page chrome (not part of the table styles)
	// =============================================================================

	h1 {
		font-family: var(--typography--fontFamily-normal);
		font-size: var(--typography--fontSize-jumbo);
		color: var(--color-heading);
	}

	h2 {
		font-family: var(--typography--fontFamily-normal);
		font-size: var(--typography--fontSize-largest);
		color: var(--color-heading);
	}

	.demo-intro {
		margin-block: var(--space-small) var(--space-largest);
		color: var(--color-text--secondary);
	}

	.demo-section {
		margin-block-end: var(--space-large);
	}

	.demo-back {
		display: inline-block;
		margin-block-start: var(--space-large);
	}
</style>
