# Housecall Pro Pipeline model

Research date: 2026-08-24  
Scope: current first-party Housecall Pro help documentation only

## Answer

Housecall Pro Pipeline is **three separate boards**, not one all-purpose sales pipeline: **Leads**, **Estimates**, and **Jobs**. Pipeline is a view and management layer over existing records; it does not create the Lead, Estimate, or Job record itself. The board stays in sync with actions made on the underlying record. [Getting Started with Pipeline](https://help.housecallpro.com/en/articles/6185127-getting-started-with-pipeline) · [Pipeline FAQs](https://help.housecallpro.com/en/articles/6185346-pipeline-faqs)

| Board | Default columns/stages | Count | Meaning |
| --- | --- | ---: | --- |
| **Leads** | New Lead → First Contact → Second Contact → Third Contact → Won / Lost | 6 | A lead is **Won** only when converted to an Estimate or Job; it is **Lost** when it does not convert. |
| **Estimates** | Unscheduled → Scheduled → In Progress → Completed → Created on Job* → Sent → On Hold → Approved / Rejected | 9* | Tracks an Estimate's scheduling, delivery, response, and approval state. *`Created on Job` is available only when “Estimates on Job” is enabled. |
| **Jobs** | Unscheduled → Scheduled → In Progress → Completed → Invoice Sent → Invoice Paid | 6 | Tracks job execution through invoicing and payment. |

All default definitions and the conditional Estimate column are from [Getting Started with Pipeline](https://help.housecallpro.com/en/articles/6185127-getting-started-with-pipeline).

## Important distinctions

- **Lead pipeline is pre-conversion follow-up.** A Lead card is tied to a customer and may be converted into an Estimate or Job. Its three contact columns represent manual follow-up attempts, while Won/Lost represent conversion outcome.
- **Estimate pipeline is not the Lead pipeline continued.** Its cards are existing Estimates (including their options), with its own status set. A sent Sales Proposal appears here as an Estimate, because sending the proposal creates an Estimate independently of Pipeline. [Pipeline FAQs](https://help.housecallpro.com/en/articles/6185346-pipeline-faqs)
- **Job pipeline is operational and financial.** It continues through scheduling, in-progress work, completion, invoice sent, and invoice paid. It is not merely a post-sale “Won” column.
- **The boards are record-owned, not independent deal cards.** Updating the underlying Lead, Estimate, or Job updates Pipeline; dragging or choosing a status can require the corresponding action, such as entering scheduling information. A multi-segment Job appears as one independently movable card per segment. [Getting Started with Pipeline](https://help.housecallpro.com/en/articles/6185127-getting-started-with-pipeline) · [Pipeline FAQs](https://help.housecallpro.com/en/articles/6185346-pipeline-faqs)

## Customization and closure

- Housecall Pro currently permits custom columns and renamed existing columns. Its customization UI also supports adding custom statuses within a column; required statuses/columns cannot be hidden. Therefore the counts above are the documented **default visible structure**, not a tenant-wide maximum stage limit. [Pipeline FAQs](https://help.housecallpro.com/en/articles/6185346-pipeline-faqs)
- Approved Estimates archive once copied to a Job, or after seven days by default; declined Estimates archive after seven days by default. Fully paid Jobs archive after seven days by default. [Pipeline FAQs](https://help.housecallpro.com/en/articles/6185346-pipeline-faqs)

## Design signal for UCRM

Housecall Pro's model favors separate domain-record boards over a single editable opportunity stage shared from initial lead through payment. Lead conversion marks the sales outcome, while Estimate and Job each retain their own workflow and operational truth. This is useful evidence for keeping UCRM's Request, Quote, and Job states owned by their respective records—even if UCRM later adds a combined reporting or lifecycle view.

## Sources

1. [Housecall Pro Help Center — Getting Started with Pipeline](https://help.housecallpro.com/en/articles/6185127-getting-started-with-pipeline) (accessed 2026-08-24)
2. [Housecall Pro Help Center — Pipeline FAQs](https://help.housecallpro.com/en/articles/6185346-pipeline-faqs) (accessed 2026-08-24)
