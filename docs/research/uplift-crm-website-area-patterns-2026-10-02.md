# CRM-native website management patterns

**Date:** 2026-10-02. Primary product and platform sources; recommendations are Uplift's choices, not claims that another product uses identical rules.

## Website area and several sites

Jobber places Website in its signed-in Marketing area and distinguishes initial publishing from later edits. [Jobber Website](https://help.getjobber.com/en/articles/website-marketing-tools/). Webflow's dashboard presents named sites and limits site-specific access. [Webflow dashboard](https://help.webflow.com/hc/en-us/articles/33961328364691-Dashboard), [site-specific access](https://help.webflow.com/hc/en-us/articles/33961263532435-Site-specific-access). These support an owner-facing Website area that first shows setup progress and later lists all assigned sites by name. Uplift's owner-only edit rule is narrower than these products' role models.

OWASP requires tenant and resource access to be checked against verified identity on every request; a selected site ID is only a selector. [OWASP Multi-Tenant Security](https://cheatsheetseries.owasp.org/cheatsheets/Multi_Tenant_Security_Cheat_Sheet.html). Uplift should scope each selected site's content, media, previews, releases, and writes to the current CRM organization and owner. Site names and guessed addresses cannot grant access.

## First launch and later updates

Housecall Pro describes an agency-built website journey with customer review and revisions before initial publication. [Housecall Pro Websites](https://help.housecallpro.com/en/articles/8058145-websites-by-housecall-pro). Jobber describes publishing a site and subsequently publishing saved edits. [Jobber Website](https://help.getjobber.com/en/articles/website-marketing-tools/). Webflow separates staging from production and shows changes before publication. [Webflow publishing](https://help.webflow.com/hc/en-us/articles/46651740529811-Publishing-workflow).

Uplift's chosen rule is a site-specific first-launch gate: Uplift checks the site and records the contractor's approval before it goes live. The current owner then publishes ordinary content changes directly. A newly assigned second site has its own launch gate.

## Site-designed forms

Astro supports custom HTML forms backed by server actions or API endpoints, with server validation. [Astro actions](https://docs.astro.build/en/guides/actions/), [forms with API endpoints](https://docs.astro.build/en/recipes/build-forms-api/). On-demand endpoints need a server adapter even when public pages remain static. [Astro on-demand rendering](https://docs.astro.build/en/guides/on-demand-rendering/). This supports forms designed for each Uplift-managed site that submit to CRM intake through a trusted server path, without adding a CMS form builder.

Jobber also offers copyable embeds for request and booking forms on outside websites. [Jobber forms on websites](https://help.getjobber.com/en/articles/add-your-request-and-booking-forms-to-your-website-and-social-media/). Uplift keeps its CRM iframe embed for outside sites. A JavaScript module is only a possible later option. The existing CRM intake design still needs a specific mapping for site-designed questions, attribution, retries, duplicates, and abuse controls before implementation.
