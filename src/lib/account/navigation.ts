// Which contractor menu items the signed-in member may open, worked out on the server by
// `$lib/server/access/navigation` and handed to the shell with the layout.
export type ContractorNavigation = {
	schedule: boolean;
	inbox: boolean;
	clients: boolean;
	requests: boolean;
	pipeline: boolean;
	jobs: boolean;
	quotes: boolean;
	invoices: boolean;
	files: boolean;
	marketing: boolean;
	reviews: boolean;
};

// When access cannot be resolved the shell still opens: the always-sold work areas stay, the extras sold
// separately stay hidden, and every page still makes its own check.
export const fallbackContractorNavigation: ContractorNavigation = {
	schedule: true,
	inbox: false,
	clients: true,
	requests: true,
	pipeline: false,
	jobs: true,
	quotes: true,
	invoices: true,
	files: true,
	marketing: false,
	reviews: false
};
