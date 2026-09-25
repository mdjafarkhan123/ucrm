# Google review campaign — owner product brief

**Status:** Owner direction recorded 2026-09-25. This is a product-behaviour brief, not an implementation plan.

## Goal

Give contractors an easy, powerful review-request system after successful work. It should help them ask customers for reviews through a natural SMS conversation, direct customers to Google where configured, and collect private feedback when a customer is unhappy.

The product must feel simple to use without removing advanced control. Contractors should get a strong ready-made setup, then adjust the automation when they need to.

## Contractor journey

1. The contractor completes a job.
2. UCRM can enrol the client in a review-request automation.
3. SMS is the first-priority channel. The client receives a polite, human-friendly review request that feels like it comes from the contractor's business, rather than a generic AI message.
4. The SMS contains a link to a branded UCRM feedback page.
5. The client selects a star rating and follows the configured next step.
6. The contractor sees the resulting review activity and private feedback in UCRM as far as the current Google connection allows.

## When a client is enrolled

- For a one-time job, the normal automation begins only after the contractor marks the whole job as completed.
- For a recurring job, the contractor chooses an "after every N completed visits" rule. UCRM does not automatically request a review after every recurring visit by default.
- The normal automatic request goes to the client's main mobile contact.
- For a manual request, the contractor can select a different client contact before sending it.
- UCRM also provides a clear **Request a review** action on a completed job and on the client page. It is for a deliberate one-off request in addition to the normal automation.

## Review routing selected by the owner

- Review routing is **off by default** for every contractor.
- A contractor must actively enable it in UCRM settings.
- Before enabling it, UCRM shows a hard warning explaining the responsibility and consequences of enabling review routing.
- The contractor can configure their routing rule.
- The starting default is:
  - **4 or 5 stars:** continue to the contractor's Google review destination.
  - **1, 2, or 3 stars:** continue to a UCRM private-feedback form.
- The private-feedback form should acknowledge the customer's experience in a kind, human way and invite them to explain what happened so the contractor can address it.
- When a customer selects 4 or 5 stars, UCRM sends them directly to the contractor's Google review destination. No UCRM thank-you screen appears before that redirect.
- When a customer selects 1, 2, or 3 stars, UCRM opens the private-feedback form.

## Request activity, notifications, and stopping reminders

- The contractor can see each request in UCRM: who it was sent to, when it was sent, whether the SMS was delivered where that information is available, and whether the client opened the UCRM feedback link.
- UCRM shows a simple in-app activity notification when the client opens the feedback link. The same activity belongs in the client's and completed job's history.
- UCRM separately records when the client continues from UCRM to the Google review destination.
- Before Google connection is available, UCRM must not claim that a customer submitted a Google review. It can show only that the customer opened the UCRM page or continued to Google.
- The normal SMS reminder sequence stops after the client opens the UCRM feedback link. A contractor may still decide to make a later manual request.
- A submitted private-feedback form creates a private recovery item and immediately alerts the contractor owner/admin team. The recovery item includes the client, job, rating, message, and a direct way to contact the client.
- A contractor cannot activate Google-review automation until their Google review link has been added. UCRM shows a simple setup checklist instead.

## Review-request automation

- Contractors can choose the sequence: message wording, timing, follow-ups, and duration.
- UCRM provides a ready-made default instead of making every contractor design a sequence from zero.
- UCRM provides three editable starting SMS styles: friendly, professional, and short. The contractor chooses one during setup and can make it sound like their own business.
- The agreed starting direction is one initial SMS after completion and one or two gentle reminders over roughly one to two weeks.
- Contractors can make the sequence more flexible in settings.
- If a contractor chooses a pattern that may harm customer goodwill or the contractor's sending reputation, UCRM should show a clear notice before they activate it.
- UCRM must make it easy to stop or change the automation.

## Google setup before one-click connection exists

The Google connection is split into two stages.

### Available now: simple manual setup

- The contractor enters or pastes their Google review link in UCRM.
- UCRM uses that link for the contractor's review-request automation.
- This lets contractors send customers to their real Google review destination without waiting for a Google application approval.
- UCRM should make this setup as easy and guided as possible.

### Paused until Google access is available

The following are intended later, once UCRM can obtain the necessary Google access and the contractor can connect their profile:

- One-click Google profile connection.
- Pulling real Google reviews into UCRM.
- A live Google review/dashboard view inside UCRM.
- AI-assisted review replies and review-management tools.
- Automated matching of Google reviews to UCRM review requests.

## Product principles

- SMS is the primary review-request channel; other channels may support the journey later or in the same automation.
- Messages should be polite, personal, clear, and business-like—not robotic or generic.
- Contractors should have advanced control without facing a confusing setup process.
- The app should make the risk of aggressive follow-up visible before activation.
- UCRM should deliver as much useful Google-review workflow as possible before one-click Google connection is available.

## Details not yet decided

- What job event counts as the exact moment a review automation begins.
- The exact ready-made message templates and reminder timing.
- The maximum number of follow-ups and when the app displays a reputation warning.
- Whether email joins the SMS sequence by default or remains an optional contractor choice.
- Who on the contractor's team can view private feedback and receive alerts.
- What the contractor sees in UCRM for sent requests, opened links, ratings, private feedback, and completed Google reviews before Google syncing is available.
- What a client sees after submitting the private-feedback form.
