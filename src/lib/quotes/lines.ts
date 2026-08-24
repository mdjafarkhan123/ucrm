// The two things a priced row must have before anything is allowed to save it. Both the block that owns
// its own Save and the new-quote form, whose Save lives in the page footer, ask this same question, so
// one bad row reads the same wherever it is caught.
export function firstLineProblem(lines: { name: string; quantity: number }[]): string | null {
	if (lines.some((line) => !line.name.trim())) return 'Give every line a name before saving.';
	if (lines.some((line) => !(line.quantity > 0))) return 'Every line needs a quantity above zero.';
	return null;
}
