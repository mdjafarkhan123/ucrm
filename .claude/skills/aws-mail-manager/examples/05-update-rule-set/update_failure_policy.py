# Copyright Amazon.com, Inc. or its affiliates. All Rights Reserved.
# SPDX-License-Identifier: Apache-2.0
"""
Safely update ActionFailurePolicy on an existing rule set.

Demonstrates the critical pattern for updating rule sets:
  1. Fetch the current rules first (update_rule_set REPLACES all rules)
  2. Modify what you need
  3. Send the full updated rules array back

ActionFailurePolicy controls what happens when an action fails:
  - DROP (default) — message is silently discarded, no further actions run
  - CONTINUE — skip the failed action, continue to next action/rule

If your rule set has multiple actions per rule (such as S3 + Archive + Send),
CONTINUE is the recommended choice so a transient failure in one action
doesn't prevent the others from running.

Usage:
    python update_failure_policy.py <rule-set-id>

Example:
    python update_failure_policy.py rs-xxxxxxxxxxxx
"""

import sys

import boto3

REGION = "us-east-1"

client = boto3.client("mailmanager", region_name=REGION)


def get_current_rules(rule_set_id):
    """Fetch the current rules from a rule set."""
    response = client.get_rule_set(RuleSetId=rule_set_id)
    rules = response["Rules"]
    print(f"Fetched {len(rules)} rules from {rule_set_id}")
    return rules


def set_failure_policy(rules, policy="CONTINUE"):
    """
    Set ActionFailurePolicy on every action in every rule.

    Actions that support ActionFailurePolicy:
      Archive, Bounce, InvokeLambda, Relay, WriteToS3, DeliverToMailbox, Send, PublishToSns

    Actions that do NOT support it:
      Drop, ReplaceRecipient, AddHeader
    """
    actions_with_policy = {
        "Archive", "Bounce", "InvokeLambda", "Relay", "WriteToS3",
        "DeliverToMailbox", "Send", "PublishToSns",
    }

    updated = 0
    for rule in rules:
        for action in rule.get("Actions", []):
            for action_type, config in action.items():
                if action_type in actions_with_policy:
                    old = config.get("ActionFailurePolicy", "DROP (default)")
                    config["ActionFailurePolicy"] = policy
                    print(f"  {rule.get('Name', '(unnamed)')}/{action_type}: "
                          f"{old} -> {policy}")
                    updated += 1

    print(f"Updated {updated} actions")
    return rules


def update_rule_set(rule_set_id, rules):
    """
    Push the updated rules back.

    WARNING: This replaces ALL rules in the rule set.
    Always fetch current rules first and include them all.
    """
    client.update_rule_set(RuleSetId=rule_set_id, Rules=rules)
    print(f"Rule set {rule_set_id} updated successfully")


def main():
    if len(sys.argv) < 2:
        print("Usage: python update_failure_policy.py <rule-set-id>")
        print("Example: python update_failure_policy.py rs-xxxxxxxxxxxx")
        sys.exit(1)

    rule_set_id = sys.argv[1]

    # Step 1: ALWAYS fetch current rules first
    rules = get_current_rules(rule_set_id)

    # Step 2: Modify in place
    rules = set_failure_policy(rules, policy="CONTINUE")

    # Step 3: Push the FULL rules array back (replaces all)
    update_rule_set(rule_set_id, rules)


if __name__ == "__main__":
    main()
