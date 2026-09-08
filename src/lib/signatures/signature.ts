// What the pad hands back, on either side of the quote. `method` is what the customer chose; the staff
// pad records a drawing as `in_person`, which the route maps on its way out.
export type SignatureValue = {
	name: string;
	method: 'typed' | 'drawn';
	image: string | null;
};

export function emptySignature(): SignatureValue {
	return { name: '', method: 'typed', image: null };
}

// A signature is offered, never demanded - Jobber's own default. So "nothing signed" is a valid answer,
// and the only invalid one is half of a signature: a drawing with nobody's name, or a name promised as a
// drawing that was never drawn.
export function signatureIsWhole(value: SignatureValue) {
	if (!value.name.trim()) return value.image === null;
	return value.method === 'typed' ? value.image === null : value.image !== null;
}

export function signatureIsGiven(value: SignatureValue) {
	return value.name.trim().length > 0;
}
