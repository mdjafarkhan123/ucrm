# Industry entry and onboarding patterns

**Question:** Do mature beauty, wellness and medspa products use a reusable onboarding link per niche, or one
entry system that configures a business-specific account?

## Official-source findings

- **Boulevard is sales-assisted.** Its salon and medspa marketing pages lead to a shared demo request. After
  sales, an onboarding specialist helps configure the service menu, staff, business settings, migration,
  training, payments and online booking. Staff receive an invitation naming the business; the link expires
  and can be resent. Sources: [demo](https://www.joinblvd.com/get-a-demo),
  [medspa](https://www.joinblvd.com/medical-spa-software),
  [salon](https://www.joinblvd.com/salon-software),
  [onboarding specialist](https://support.boulevard.io/en/articles/8797012-partnering-with-your-boulevard-onboarding-specialist),
  [login invitation](https://support.boulevard.io/en/articles/16776825-logging-into-boulevard).
- **Vagaro uses one self-service signup.** The business selects the services and business types it offers;
  those choices seed its service menu and marketplace category. Account creation is followed by a resumable
  setup wizard, with optional individual onboarding and data-transfer help. Sources:
  [business account setup](https://support.vagaro.com/hc/en-us/articles/44263218471323-Create-Your-Vagaro-Business-Account),
  [pricing and signup](https://www.vagaro.com/pro/pricing).
- **Fresha separates the person from the business workspace.** One signup creates or verifies the owner, then
  creates a workspace with a primary service type, related types, team size and operating model. People can
  join more than one workspace, and team invitations name the workspace. Sources:
  [getting started](https://www.fresha.com/help-center/academy/launch-your-workspace/getting-started/lessons/100243),
  [create a workspace](https://www.fresha.com/help-center/knowledge-base/workspace-settings/40-create-a-new-workspace),
  [join a workspace](https://www.fresha.com/help-center/knowledge-base/workspace-settings/43-join-a-workspace).
- **Mindbody and Zenoti are also assisted.** Mindbody's current pricing journey offers individual setup,
  training and migration. Zenoti's shared demo form asks for the vertical and follows with configuration,
  migration and role-specific training. Sources: [Mindbody pricing](https://www.mindbodyonline.com/business/pricing),
  [Mindbody onboarding journey](https://www.mindbodyonline.com/sites/default/files/public/education/learning-assets/2021-07-Infographic-NewCustomerOnboarding-V6.pdf),
  [Zenoti demo](https://www.zenoti.com/book-a-demo),
  [Zenoti pricing](https://www.zenoti.com/pricing-zenoti).

## Evidence limit and product conclusion

Public sources show niche marketing followed by either one shared signup with business-type selection or a
sales-assisted journey ending in a business-specific invitation. They do not reveal the vendors' private
architecture, and no source found a reusable public post-sale onboarding URL per niche.

For Uplift, the supported pattern is one application/provisioning system and one secure organization-specific
access path, with independently versioned onboarding programs selected by industry experience and filtered by
purchased capabilities. This is our design conclusion from the public behavior, not a claim that a competitor
stores its programs the same way.
