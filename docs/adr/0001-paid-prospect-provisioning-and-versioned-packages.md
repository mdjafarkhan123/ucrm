# ADR 0001: Provision paid prospects into versioned packages

## Status

Accepted

## Context

A contractor may submit a public onboarding form and select a package before paying through an
external provider. Creating a contractor organization or user at submission would create tenant
accounts for unpaid prospects. Editing a live package would also silently change the access or
commercial terms of existing organizations.

## Decision

- A submitted form creates a platform-owned onboarding application, never an organization,
  organization membership, or contractor login.
- The Platform Owner manually confirms the offsite payment before provisioning the organization.
- Provisioning creates the initial contractor administrator and sends a secure password-setup email;
  the Platform Owner never handles the administrator's password.
- Packages are defined in `/jafar` as the single source of truth. Published packages have immutable
  historical versions. Each onboarding application and organization uses a specific package version.
- A later package revision applies to new prospects by default. Existing organizations change only
  through a separate, confirmed package-change action.
- The first release uses fixed USD monthly platform prices. Payment-provider fees, if any, are
  separate from that price and are not calculated or collected by UpliftContractor.
- UpliftContractor does not charge, calculate, collect, or add tax in the first release. Public
  package pricing states that the displayed USD platform price has no tax added by UpliftContractor.

## Consequences

- The current direct organization-provisioning flow must be replaced after the implementation
  contract and demo design are approved.
- The future package model cannot rely on fixed package names or live package definitions for
  existing organizations.
- The Platform Owner records offsite payment confirmations and paid-through dates manually.
