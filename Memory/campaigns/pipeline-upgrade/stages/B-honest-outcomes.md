# Pipeline upgrade — stage B: honest outcomes

Approved by Jafar 2026-10-01. Plan § Outcomes and
§ Movement and automation; audit items A1, A2, B2, C6, C7. Independent of stage A, so a second session may
build it at the same time. B1 crosses into the Jobs domain and is the least certain part here.

| Part | Delivers | Waits for | Done when | State |
| --- | --- | --- | --- | --- |
| B1 Request straight to a Job is Won | "Convert to job" on the Request page works under the Jobs rules; the Request's Opportunity becomes Won once, with its value frozen from the Job total | — | Converting a Request to a Job creates the Job, the card leaves the board, and the Won tile rises by one with the Job's total; making a Job from an already-Won Quote adds nothing | Done 2026-10-01 |
| B2 Direct job | A Job made with no Request or Quote is recorded as a separately labelled Won result that never appears on the board | B1 | A Job created from scratch shows under "Direct job" in Sales Outcomes; the board and the Request/Quote conversion numbers do not change | Done 2026-10-01 |
| B3 Dropping a Draft really sends | Draft → Awaiting response opens a review window: email the quote, mark it sent outside UCRM (channel and optional note), view the quote, or cancel; the card moves only after the choice succeeds | — | Cancel leaves the card in Draft; Email delivers a real email to a test inbox and then the card moves; "sent outside UCRM" records who, when, and how | Not started |
| B4 A failed delivery stays visible | A later bounce keeps the quote sent but marks the card and Brief as failed, and alerts the responsible teammate | B3 | A quote emailed to a bouncing address shows "Delivery failed" on its card and Brief, and the card's owner gets one in-app alert | Not started |
| B5 Lost and abandoned quotes | Mark as lost on sent quote cards with an optional reason; archiving a never-sent Draft is "Abandoned before sending"; a customer decline keeps their message and lets staff add a reason; lost value is frozen | — | Marking an Awaiting response card Lost archives the quote and shows it under Lost with its value; an archived never-sent Draft adds no Lost; a customer decline shows the customer's message and accepts a staff reason | Not started |
| B6 Lost reasons list and reopening Won | Owner or admin manages the reason list in Settings; a retired reason stays on old records; Won can be reopened only before a Job exists | B5 | The owner adds "Out of service area" and retires "No response", and an old Lost record still reads "No response"; a Won quote with no Job reopens with an explanation, one with a Job cannot | Not started |

Limit found while splitting: quotes can be emailed today, not texted. B3 offers Email and "sent outside UCRM";
Text joins the window when the Quotes area can text a quote — recorded in
`Memory/deferred/send-a-quote-by-text.md`.
