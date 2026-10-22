// One setting on the Settings home: where it goes and how it is set right now.
export type SettingsHomeRow = {
	key: string;
	title: string;
	/** Raw Tabler SVG for the row's tile. */
	icon: string;
	/** The tile's meaning colour. */
	tone: string;
	href: string;
	/** What this setting is right now, in a few words. */
	value?: string | null;
	/** A status instead of a plain value: something done or something still waiting. */
	pill?: { label: string; tone: 'success' | 'warning' | 'critical' | 'inactive' | 'informative' };
};

/** Whether a row matches what was typed in the settings search (name and current value, any case). */
export function rowMatches(row: SettingsHomeRow, query: string): boolean {
	const needle = query.trim().toLowerCase();
	if (!needle) return true;
	return [row.title, row.value ?? '', row.pill?.label ?? '']
		.join(' ')
		.toLowerCase()
		.includes(needle);
}

export type BusinessFact = {
	key: string;
	label: string;
	value: string | null;
	icon: string;
	tone: string;
};
