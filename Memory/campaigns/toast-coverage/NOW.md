# Toast Coverage: Current Checkpoint

## Goal

Every save, delete, and archive action gives clear success feedback and appropriate failure feedback through the shared toast system.

## Current state

Paused. Clients is the only confirmed missing area: ClientForm, the inline client save, and PropertyDialog mutations lack toast coverage. Other areas remain unsurveyed.

## Exact next action

When resumed, fix the three confirmed Client locations first. Then survey one domain at a time: Requests, Quotes/Pipeline/Jafar, shared Collaboration components, then Team.

## Constraints

Reuse ToastManager. Fix shared components once. Preserve unrelated dirty Quotes work.

## Completion gate

Each surveyed mutation has honest success/failure feedback without duplicated page-level handling.
