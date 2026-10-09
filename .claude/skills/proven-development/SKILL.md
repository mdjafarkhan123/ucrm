---
name: proven-development
description: Research proven product behavior before building features, workflows, or components; choose maintainable engineering patterns before database design or substantial implementation. Use also when a product decision emerges midway through work or an existing feature appears to need improvement. Keep routine fixes proportional.
---

# Proven development

Jafar owns product decisions. The agent owns technical planning and implementation within approved scope. Explain choices to Jafar through what business owners, their staff, and their clients will experience, in everyday English. Keep technical plans in working notes; present implementation detail only when requested or needed to explain a material consequence.

## Establish the product before designing its implementation

1. Inspect the relevant existing behavior, approved decisions, and product blueprint. Identify the user's problem and the smallest complete workflow that solves it. Reuse settled decisions unless requirements or evidence have changed.
2. Research unresolved behavior using the relevant mature product: start with [Jobber](../jobber/SKILL.md) for contractor workflows, Boulevard for Medspa, Beauty & Spa, and other appointment-based workflows (`docs/boulevard-product-behavior-contract.md` records what is approved), and HighLevel for applicable communications/marketing behavior. Use official help articles, documentation, and direct product observation. Consult another mature product when the first leaves a material gap or offers a poor fit; a fixed competitor count adds no evidence.
3. Separate verified behavior, inference, and our proposed adaptation. Cite sources for the behavior that drives the decision. A competitor's screens and public API do not establish its internal database or architecture. If evidence is unavailable or contradictory, state the gap and research further; ask Jafar only for the remaining product choice, with a recommendation.
4. Before dependent database design or implementation, resolve any unapproved product choice with Jafar. Use this short format, scaled to the decision:
   - **What happens today / what is missing.**
   - **What the reference product does**, with a source.
   - **What I recommend for our app**, why it fits, and any meaningful downside or edge case.
   - **The decision needed from you**, in everyday English.

Proceed when the requested behavior is clear and authorized. Approval already given in the task or recorded decisions counts; do not ask for it again. Preserve essential states and failure paths when simplifying. A competitor difference alone is not a defect, and competitor feature parity is not automatic scope.

For non-trivial product work, keep a short evidence record in working notes. It is complete when it identifies:

- The user's problem and the relevant current behavior.
- The verified reference behavior and its source.
- What we will adopt, adapt, or reject, with the reason.
- The important user-visible states, permissions, failure cases, and expected result.
- Whether the product decision was already approved or still needs Jafar's decision.

Every research claim must support a decision. Phrases such as "best practice" or "industry standard" are not evidence by themselves.

## Re-enter the decision process whenever needed

These rules apply throughout planning, coding, and verification. If a new product question appears midway, research it before asking Jafar. Pause only work that depends on the unresolved choice; continue independent authorized work. Bring a supported recommendation rather than asking him to invent the answer.

If an existing feature would benefit from a different workflow or behavior, present the current problem, evidence, proposed change, and consequences for existing users or records before changing it. Keep unrelated improvements as proposals. Restoring already approved behavior is a bug fix, not a new product decision.

Use [grilling](../grilling/SKILL.md) only when product choices remain unresolved after investigation; keep its questions about user experience and business needs. Record accepted decisions in the existing product document or active campaign record, as applicable, so later work resumes from agreement.

## Engineer the approved behavior

Before database design or substantial coding, inspect existing modules and establish the appropriate standard mechanism from official stack documentation, standards, maintained library APIs, or published engineering evidence. Reuse verified project references when applicable; verify uncertain or changing facts. Compare real alternatives internally and choose the simplest correct fit. Claims that a named company uses an approach require evidence.

Make a technical plan for the affected path: data ownership and invariants, module boundaries, failure behavior, and meaningful verification. Load the applicable specialist skills through the project's subject and work-stage gates. For maintainability, keep business rules in one authoritative place, use explicit domain names and clear responsibilities, reuse suitable existing components, and prefer established primitives over custom frameworks. Add abstractions or dependencies only when the current requirement justifies them.

Apply the performance-review gate before scale-sensitive design and after implementation. Base scaling choices on the actual workload and measured evidence; the customer-count target alone does not justify extra infrastructure.

Choose routine technical details autonomously. Preserve explicit approval boundaries for auth, schema, permissions, RLS, and infrastructure; explain the concrete impact on access, stored data, cost, availability, or recovery in plain English when approval is required. A technical choice that changes promised product behavior returns to the product decision process above.

For UI work, follow the approved product blueprint and the [design skill](../design/SKILL.md), reusing existing components. Adapt the proven interaction to our design system and verify the relevant responsive, loading, empty, error, and accessibility behavior.

## Finish with evidence proportional to the change

Check the implemented behavior against the approved workflow, including relevant failure cases, and run the applicable project checks. Report what users can now do, what was verified, and any material limitation. When research affected the product choice, include the key reference used. Small corrections that preserve behavior need focused inspection and verification; they do not need a new competitor study or product approval.
