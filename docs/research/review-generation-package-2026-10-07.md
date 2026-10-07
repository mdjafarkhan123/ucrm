# Review generation package — research

**Researched:** 2026-10-07
**Scope:** How standalone review-generation products and Jobber sell review asking, how configurators handle an
item that needs another item, and what UCRM already has. Public product pages and help articles only; no paid
account was opened, so behavior behind a login is unconfirmed.

## Short answer

- Review Harvest and NiceJob sell review asking as its own product to businesses that run their work in another
  app. They learn that a service is done from manual entry, a spreadsheet upload, a direct connection to the
  business's field-service app, or Zapier.
- Jobber sells reviews as a $39-a-month add-on to a Jobber plan and asks automatically after a visit, a job
  close, or a paid invoice.
- Configurators and installers add what a chosen item needs and show the list; removing an item that others
  need lists what else goes before anything is removed.
- UCRM already has the review asking itself. It lacks a slim package, a "service done" signal without its own
  Jobs, a one-time ask to past customers, and the Google Business Profile connection.

## Review Harvest — the model Jafar chose

Read from [reviewharvest.com](https://reviewharvest.com/) and its [product page](https://reviewharvest.com/product).

- **Customers in:** manual entry, CSV upload, native integrations with "Jobber, Quickbooks Online, Housecall Pro,
  Workiz, Sweep & Go, Square", Zapier, and a custom CRM integration.
- **Asking:** "1 initial review request post service then 2 gentle reminders", adjustable; a "30 day cool down
  period" for recurring customers; reminders do not count toward the monthly request limit.
- **Review Reactivation:** one initial campaign to the uploaded list of past customers. They claim about 10% of
  past customers leave a review; unverified.
- **Channels:** SMS, email, and "Personalized Image Requests" with the customer's name on a photo.
- **Sites:** Google only; Facebook and Yelp "in development"; US, Canada, and Mexico.
- **Honesty:** "we can't block or filter reviews. That's against Google's policy."
- **Extras:** AI replies to positive reviews, automatic Facebook and Instagram posts of 5-star reviews, a website
  review widget, and tracking of who already reviewed.
- **Price:** Starter $99 a month (up to 50 requests), Growth $179 (50–100), Pro $279 (100–300); yearly is ten
  months' price; unlimited users; 10-day free trial; no contract; a 1-to-1 setup call.
- **Not documented publicly:** which event in each connected app triggers an ask, the batch size and spacing of
  Review Reactivation, and how a posted review is matched to a customer.

## NiceJob

- A standalone review and marketing tool from $75 a month, Pro $125. [Capterra](https://capterra.com/p/142037/NiceJob)
- Connects to Jobber, ServiceTitan, Housecall Pro, QuickBooks, and others. With Housecall Pro, when a job is
  marked "Finished", NiceJob enrolls that customer in its Get Reviews campaign.
  [Housecall Pro partner page](https://www.housecallpro.com/partner/nicejob)

## Jobber Reviews

- An add-on on all plans for $39 USD a month in the US, Canada, and Great Britain.
  [Jobber Help](https://help.getjobber.com/hc/en-us/articles/20621046897559)
- Asks automatically when a job closes, a visit is completed, or the final invoice is paid; needs a verified
  Google Business Profile. [Jobber Reviews](https://getjobber.com/features/marketing-tools/reviews)

## An item that needs another item

- **Salesforce CPQ:** an option constraint lets one option be checked only when another is; a selection product
  rule with an "Add" action adds the required product automatically.
  [Trailhead: selection rules](https://trailhead.salesforce.com/content/learn/modules/product-rules-in-salesforce-cpq/discover-other-ways-to-use-selection-rules)
- **Software installers (apt):** installing lists "The following additional packages will be installed" and asks
  before continuing; removing a package other packages depend on lists what else would be removed.
  [apt dependencies](https://linuxhint.com/install-dependencies-apt/)
- **For UCRM:** one-way "needs" links, automatic adding with a visible note, and a question before removing
  anything that another ticked feature needs.

## What UCRM has today (code read 2026-10-07)

- **Basics are locked.** Nine basics are forced into every package in three places: the builder screen, the
  draft save, and package exceptions. Extras: Sales pipeline, Shared inbox, Website chat (needs Shared inbox),
  Marketing email, Review requests, Custom automations. Planned: Advanced reports, Missed-call text-back,
  Advanced dispatch, API and integrations.
- **Access is ready in principle.** Every permission already belongs to a feature, basics included, so a basic
  switched off already loses its permissions. Whether every screen copes has not been checked.
- **Review asking exists.** SMS or email, three message styles, a reminder plan, the feedback page with optional
  routing, private-feedback recovery, and the Reviews page. A manual ask starts from a client, with a job
  optional. The automatic ask is an Automations recipe, "When a job's work is completed → Send a review request",
  so it needs Jobs and Custom automations; switching it on never asks past customers.
- **Customers in:** a client spreadsheet (CSV) import exists.
- **Texting:** texts are charged to the business's prepaid Communication Balance, and texting waits until the
  business's registration is approved.
- **Not built:** asking a whole list at once, Zapier or other inbound connections, the Google Business Profile
  connection (a later phase in the Google review plan), a review widget, social posting, and AI replies.
- **Links between basics** (from the quote, job, and invoice plans): a Job can exist without a Quote; an Invoice
  can exist without a Job; an approved Quote converts to a Job; a Request converts to a Quote or a Job.
