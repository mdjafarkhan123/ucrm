// A failed API call as the browser sees it: the server's message plus the HTTP status it refused with.
// The status is what lets the query client stop retrying a 4xx (the answer never changes) and lets a page
// say "no access" or "not found" instead of spinning on its skeleton or blaming the connection.
export type HttpError = Error & { status: number };

export function httpError(response: Response, message: string): HttpError {
	const error = new Error(message) as HttpError;
	error.status = response.status;
	return error;
}
