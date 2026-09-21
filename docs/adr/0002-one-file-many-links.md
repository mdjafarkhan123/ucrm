# Store one file and link it to every use

The contractor File Manager is the single catalog for manageable CRM files. One File owns one immutable private
Cloudflare R2 original, while separate links describe every Client, Request, Quote, Job, Visit, Invoice, message,
or other record using it. This avoids copied blobs and makes “Used in” truthful; replacing content creates a new
File rather than silently changing every existing use or rewriting an issued customer document.
