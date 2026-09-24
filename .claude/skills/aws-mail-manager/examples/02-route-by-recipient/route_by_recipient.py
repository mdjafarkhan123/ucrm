# Copyright Amazon.com, Inc. or its affiliates. All Rights Reserved.
# SPDX-License-Identifier: Apache-2.0
"""
Route inbound email to different destinations based on recipient address.

Demonstrates a rule set with multiple routing rules:
  - support@example.com  → relay to help desk SMTP server
  - legal@example.com    → archive with extended retention
  - @example.com (catch-all) → write to Amazon S3

Assumes you already have:
  - A relay resource (relay_id)
  - An archive resource (archive_id)
  - An Amazon S3 bucket and IAM role for WriteToS3

Usage:
    python route_by_recipient.py

Prerequisites:
    AWS credentials configured (aws configure, env vars, or IAM role).
    Amazon SES Mail Manager enabled in your account/region.
    Existing relay, archive, and S3 bucket resources.

Cleanup:
    Delete the rule set when no longer needed:
      client.delete_rule_set(RuleSetId=rule_set_id)
    Note: remove the rule set from any ingress points first.
    Cost note: The relay, archive, and S3 bucket referenced by this
    rule set incur ongoing charges. Delete those resources separately
    when no longer needed.
"""

import boto3

REGION = "us-east-1"

# Replace these with your actual resource IDs/ARNs
RELAY_ID = "r-xxxxxxxxxx"
ARCHIVE_ID = "a-xxxxxxxxxx"  # use archive ID, NOT ARN (66-char limit)
S3_BUCKET = "amzn-s3-demo-bucket-email"
S3_ROLE_ARN = "arn:aws:iam::123456789012:role/MailManagerS3Role"

client = boto3.client("mailmanager", region_name=REGION)


def create_routing_rule_set():
    """
    Create a rule set with recipient-based routing.
    Rules are evaluated in order — first match wins.
    """
    response = client.create_rule_set(
        RuleSetName="recipient-routing",
        Rules=[
            {
                "Name": "route-support",
                "Conditions": [
                    {
                        "StringExpression": {
                            "Evaluate": {"Attribute": "RECIPIENT"},
                            "Operator": "EQUALS",
                            "Values": ["support@example.com"],
                        }
                    }
                ],
                "Actions": [
                    {
                        "Relay": {
                            "Relay": RELAY_ID,
                            "MailFrom": "PRESERVE",
                            "ActionFailurePolicy": "CONTINUE",
                        }
                    }
                ],
            },
            {
                "Name": "route-legal",
                "Conditions": [
                    {
                        "StringExpression": {
                            "Evaluate": {"Attribute": "RECIPIENT"},
                            "Operator": "EQUALS",
                            "Values": ["legal@example.com"],
                        }
                    }
                ],
                "Actions": [
                    {
                        "Archive": {
                            "TargetArchive": ARCHIVE_ID,
                            "ActionFailurePolicy": "CONTINUE",
                        }
                    }
                ],
            },
            {
                "Name": "catch-all-to-s3",
                # No conditions = matches everything not caught above
                "Actions": [
                    {
                        "WriteToS3": {
                            "S3Bucket": S3_BUCKET,
                            "RoleArn": S3_ROLE_ARN,
                            "S3Prefix": "inbound/",
                            "ActionFailurePolicy": "CONTINUE",
                        }
                    }
                ],
            },
        ],
    )
    rule_set_id = response["RuleSetId"]
    print(f"Rule set created: {rule_set_id}")
    return rule_set_id


def add_rule_to_existing(rule_set_id, new_rule):
    """
    Add a rule to an existing rule set.

    IMPORTANT: update_rule_set replaces ALL rules.
    Always fetch current rules first and append to them.
    """
    current = client.get_rule_set(RuleSetId=rule_set_id)
    existing_rules = current["Rules"]

    updated_rules = existing_rules + [new_rule]

    client.update_rule_set(
        RuleSetId=rule_set_id,
        Rules=updated_rules,
    )
    print(f"Rule '{new_rule['Name']}' added to rule set {rule_set_id}")


def main():
    rule_set_id = create_routing_rule_set()

    # Example: add a rule for a new address without losing existing rules
    new_rule = {
        "Name": "route-billing",
        "Conditions": [
            {
                "StringExpression": {
                    "Evaluate": {"Attribute": "RECIPIENT"},
                    "Operator": "EQUALS",
                    "Values": ["billing@example.com"],
                }
            }
        ],
        "Actions": [
            {
                "WriteToS3": {
                    "S3Bucket": S3_BUCKET,
                    "RoleArn": S3_ROLE_ARN,
                    "S3Prefix": "billing/",
                    "ActionFailurePolicy": "CONTINUE",
                }
            }
        ],
    }

    # Insert before the catch-all (index -1 inserts before last element)
    current = client.get_rule_set(RuleSetId=rule_set_id)
    rules = current["Rules"]
    rules.insert(-1, new_rule)  # before catch-all
    client.update_rule_set(RuleSetId=rule_set_id, Rules=rules)
    print(f"Billing rule inserted before catch-all in {rule_set_id}")


if __name__ == "__main__":
    main()
