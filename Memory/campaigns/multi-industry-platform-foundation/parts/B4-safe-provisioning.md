# B4 Safe provisioning

**Done when:** a paid, approved Application creates one correctly profiled Organization, and a failed
invitation is recoverable without a duplicate (Resend setup email already reuses the same account).

**Steps**
- [ ] Migration `20261127090000_provisioning_experience_profile`: activation refuses without a supported
      decision and fitting package, and copies the decision onto the Organization (source `provisioning`);
      Uplift may decide the kind of business after payment until the account exists.
- [ ] Apply it. Outcome check: `select 1 from supabase_migrations.schema_migrations where version = '20261127090000'`.
- [ ] Uplift screen: "Confirm kind of business" also on paid, not-yet-activated Applications; qualify route
      message; buyer page shows a hold after payment.
- [ ] Unit tests (qualify, provision), journey test, live proof on the two older paid Applications' path.

**Next:** apply the migration.
