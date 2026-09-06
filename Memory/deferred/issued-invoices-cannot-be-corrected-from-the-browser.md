# Issued invoices cannot be corrected from the browser

The D3 correction chain is complete and tested in the database — `prepare_invoice_correction`,
`activate_invoice_replacement` and `rebill_voided_invoice` — but nothing in `src/` calls any of the three.
There is no API route and no button, so a contractor who issued a wrong bill has no way to fix it in the app.

This became visible in 5c-4, which made it the *only* way out for a progress invoice: `void_invoice` refuses
one outright ("A progress invoice is corrected rather than voided"), and the Invoice screen now leaves Void
off the menu for those bills rather than offering a button that can only fail.

**Reactivates when** Jafar asks for a correction flow, or a contractor hits a wrong issued bill in real use.

**Already known:** the shape is prepare → edit the replacement draft → activate with the difference the user
was shown (`activate_invoice_replacement` refuses a difference that no longer matches). The original stays
the live receivable until activation, and money never moves on its own.
