# Copyright Amazon.com, Inc. or its affiliates. All Rights Reserved.
# SPDX-License-Identifier: Apache-2.0
"""
End-to-end Mail Manager pipeline setup.

Creates the full resource chain in dependency order:
  Archive → Traffic Policy → Rule Set → Ingress Point

After running, update your domain's MX record to the ingress point hostname.

Usage:
    pip install boto3
    python setup_pipeline.py

Prerequisites:
    AWS credentials configured (aws configure, env vars, or IAM role).
    Amazon SES Mail Manager enabled in your account/region.

Cost notice:
    This script creates billable resources. Archives incur storage charges
    based on retention period and email volume. Ingress points incur
    per-message processing charges. Delete resources when no longer needed.

Cleanup:
    Delete in reverse dependency order:
      client.delete_ingress_point(IngressPointId=ingress_id)
      client.delete_rule_set(RuleSetId=rule_set_id)
      client.delete_traffic_policy(TrafficPolicyId=policy_id)
      client.delete_archive(ArchiveId=archive_id)
    WARNING: Deleting the archive permanently removes all stored emails.
    Export any needed data before deleting. Archive deletion is async
    (enters PENDING_DELETION state).
"""

import time
import boto3

REGION = "us-east-1"
DOMAIN = "example.com"  # Replace with your domain

client = boto3.client("mailmanager", region_name=REGION)


def create_archive():
    """Create an archive for long-term email storage."""
    response = client.create_archive(
        ArchiveName=f"{DOMAIN}-archive",
        Retention={"RetentionPeriod": "ONE_YEAR"},
    )
    archive_id = response["ArchiveId"]
    print(f"Archive created: {archive_id}")
    return archive_id


def create_traffic_policy():
    """
    Create a traffic policy that:
    - Allows only connections using TLS 1.2 or higher
    - Denies everything else by default
    """
    response = client.create_traffic_policy(
        TrafficPolicyName=f"{DOMAIN}-policy",
        DefaultAction="DENY",
        PolicyStatements=[
            {
                # Allow connections that meet TLS 1.2 minimum
                # MINIMUM_TLS_VERSION matches connections AT or ABOVE the specified version
                "Action": "ALLOW",
                "Conditions": [
                    {
                        # TlsExpression uses singular "Value", not "Values"
                        "TlsExpression": {
                            "Evaluate": {"Attribute": "TLS_PROTOCOL"},
                            "Operator": "MINIMUM_TLS_VERSION",
                            "Value": "TLS1_2",
                        }
                    }
                ],
            }
        ],
    )
    policy_id = response["TrafficPolicyId"]
    print(f"Traffic policy created: {policy_id}")
    return policy_id


def create_rule_set(archive_id):
    """
    Create a rule set that:
    - Archives all email
    - Drops messages that fail SPF
    """
    response = client.create_rule_set(
        RuleSetName=f"{DOMAIN}-rules",
        Rules=[
            {
                "Name": "drop-spf-fail",
                "Conditions": [
                    {
                        "VerdictExpression": {
                            "Evaluate": {"Attribute": "SPF"},
                            "Operator": "EQUALS",
                            "Values": ["FAIL"],
                        }
                    }
                ],
                "Actions": [{"Drop": {}}],
            },
            {
                "Name": "archive-all",
                # No conditions = matches all messages
                "Actions": [
                    {
                        "Archive": {
                            "TargetArchive": archive_id,  # use ID, not ARN
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


def create_ingress_point(traffic_policy_id, rule_set_id):
    """
    Create an OPEN ingress point (no SMTP auth required).
    For AUTH type, add IngressPointConfiguration with SmtpPassword or SecretArn.
    For MTLS type, add IngressPointConfiguration with TlsAuthConfiguration.
    """
    response = client.create_ingress_point(
        IngressPointName=f"{DOMAIN}-ingress",
        Type="OPEN",
        TrafficPolicyId=traffic_policy_id,
        RuleSetId=rule_set_id,
        TlsPolicy="REQUIRED",  # REQUIRED | OPTIONAL | FIPS
        # Default: FIPS in US/CA regions, REQUIRED elsewhere
    )
    ingress_id = response["IngressPointId"]
    print(f"Ingress point created: {ingress_id} (provisioning...)")
    return ingress_id


def wait_for_active(ingress_id, timeout=300):
    """Poll until ingress point is ACTIVE. Do NOT update DNS before this."""
    deadline = time.time() + timeout
    while time.time() < deadline:
        response = client.get_ingress_point(IngressPointId=ingress_id)
        status = response["Status"]
        if status == "ACTIVE":
            hostname = response["ARecord"]
            print(f"Ingress point ACTIVE: {hostname}")
            return hostname
        if status == "FAILED":
            raise RuntimeError(f"Ingress point provisioning failed: {response}")
        print(f"  Status: {status} — waiting...")
        time.sleep(10)
    raise TimeoutError("Ingress point did not become ACTIVE within timeout")


def main():
    print("=== Mail Manager Pipeline Setup ===\n")

    # Step 1: Archive (no dependencies)
    archive_id = create_archive()

    # Step 2: Traffic policy (no dependencies)
    policy_id = create_traffic_policy()

    # Step 3: Rule set (references archive ID — not ARN)
    rule_set_id = create_rule_set(archive_id)

    # Step 4: Ingress point (requires traffic policy + rule set)
    ingress_id = create_ingress_point(policy_id, rule_set_id)

    # Step 5: Wait for ACTIVE before touching DNS
    hostname = wait_for_active(ingress_id)

    print("\n=== Setup Complete ===")
    print(f"Archive ID:        {archive_id}")
    print(f"Traffic Policy ID: {policy_id}")
    print(f"Rule Set ID:       {rule_set_id}")
    print(f"Ingress Point ID:  {ingress_id}")
    print(f"\nNext step: Set your MX record for {DOMAIN} to:")
    print(f"  10 {hostname}")


if __name__ == "__main__":
    main()
