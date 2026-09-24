---
description: "Deploy a complete Amazon SES Mail Manager inbound email pipeline using AWS CDK TypeScript. Includes ingress point, traffic policy, rule set with archive, S3, and send actions."
---

# CDK Inbound Email Pipeline

AWS CDK (TypeScript) example that deploys a complete Mail Manager inbound email pipeline.

## What It Deploys

- Open ingress endpoint (public, no SMTP auth)
- Allow-all traffic policy (tighten for production)
- Rule set with three actions: Archive → Write to S3 → Send to internet
- Archive with unique name (avoids `PENDING_DELETION` collisions)
- S3 bucket with unique name and IAM role for WriteToS3
- IAM role for Send to internet (`ses:SendRawEmail`)

## Prerequisites

- Node.js 18+ and npm
- AWS CDK CLI: `npm install -g aws-cdk`
- AWS credentials configured
- CDK bootstrapped in your account/region: `cdk bootstrap`

## Cost Note

This example creates billable resources: a Mail Manager ingress point (per-message charges), archive (storage charges), and Amazon S3 bucket (storage charges). Delete resources when no longer needed by running `npx cdk destroy`.

## Usage

To use this example, create a new CDK project and copy the stack code below:

```bash
mkdir mail-manager-pipeline && cd mail-manager-pipeline
npx cdk init app --language typescript
npm install aws-cdk-lib constructs
```

Replace the generated stack with the code in the [Stack Code](#stack-code) section, then deploy:

```bash
npx cdk deploy
```

## SES Sandbox Note

If your Amazon SES account is in sandbox mode, the Send to internet action only delivers to verified SES identities (email addresses). Request production access to send to arbitrary recipients.

## Verify Deployment

After deployment, confirm the resources were created:

```bash
# Check stack outputs (ingress point hostname, archive ID, S3 bucket)
aws cloudformation describe-stacks --stack-name MailManagerPipeline --query 'Stacks[0].Outputs'

# Verify ingress point is ACTIVE
aws mailmanager get-ingress-point --ingress-point-id <IngressPointId from outputs>
```

Wait for the ingress point to reach `ACTIVE` status before updating DNS.

## Cleanup

```bash
npx cdk destroy
```

The archive enters `PENDING_DELETION` and the name remains claimed for up to 30 days. The S3 bucket must be empty before deletion — CDK handles this with `autoDeleteObjects`, which permanently removes all stored email objects during stack destruction. Export any needed data before running `cdk destroy`.

## App Entry Point

The CDK app entry point creates the stack with a descriptive CloudFormation description.

```typescript
#!/usr/bin/env node
import * as cdk from "aws-cdk-lib";
import { MailManagerPipelineStack } from "../lib/mail-manager-pipeline-stack";

const app = new cdk.App();
new MailManagerPipelineStack(app, "MailManagerPipeline", {
  description:
    "Mail Manager inbound email pipeline: ingress point, traffic policy, " +
    "rule set with archive + S3 + send to internet actions.",
});
```

## Stack Code

```typescript
// Copyright Amazon.com, Inc. or its affiliates. All Rights Reserved.
// SPDX-License-Identifier: Apache-2.0
//
// CDK stack that deploys a complete Mail Manager inbound email pipeline:
//   - Open ingress endpoint (public, no SMTP auth required)
//   - Allow-all traffic policy (tighten for production)
//   - Rule set: Archive → Write to S3 → Send to internet
//
// SES SANDBOX NOTE: If your account is in SES sandbox mode, the "Send to
// internet" action will only deliver to verified SES identities (email
// addresses). Request production access via the SES console to send to
// arbitrary recipients.

import * as cdk from "aws-cdk-lib";
import { Construct } from "constructs";
import * as iam from "aws-cdk-lib/aws-iam";
import * as s3 from "aws-cdk-lib/aws-s3";
import * as ses from "aws-cdk-lib/aws-ses";

export class MailManagerPipelineStack extends cdk.Stack {
  constructor(scope: Construct, id: string, props?: cdk.StackProps) {
    super(scope, id, props);

    // ---------------------------------------------------------------
    // Archive — unique name to avoid PENDING_DELETION collisions
    // ---------------------------------------------------------------
    const archive = new ses.CfnMailManagerArchive(this, "Archive", {
      archiveName: `mm-agent-context-pack-archive-${cdk.Names.uniqueId(this).slice(-8).toLowerCase()}`,
      retention: { retentionPeriod: "THREE_MONTHS" },
    });

    // ---------------------------------------------------------------
    // S3 Bucket — unique name, auto-delete objects on stack teardown
    // ---------------------------------------------------------------
    const emailBucket = new s3.Bucket(this, "EmailBucket", {
      bucketName: `mm-agent-context-pack-s3-${cdk.Names.uniqueId(this).slice(-8).toLowerCase()}`,
      removalPolicy: cdk.RemovalPolicy.DESTROY,
      autoDeleteObjects: true,
      lifecycleRules: [{ expiration: cdk.Duration.days(90) }],
    });

    // Bucket policy allowing SES to write objects
    emailBucket.addToResourcePolicy(
      new iam.PolicyStatement({
        sid: "AllowMailManagerWrite",
        effect: iam.Effect.ALLOW,
        principals: [new iam.ServicePrincipal("ses.amazonaws.com")],
        actions: ["s3:PutObject"],
        resources: [emailBucket.arnForObjects("*")],
        conditions: {
          StringEquals: { "aws:SourceAccount": this.account },
        },
      })
    );

    // ---------------------------------------------------------------
    // IAM Role — WriteToS3 action
    // ---------------------------------------------------------------
    const s3WriteRole = new iam.Role(this, "S3WriteRole", {
      assumedBy: new iam.ServicePrincipal("ses.amazonaws.com", {
        conditions: {
          StringEquals: { "aws:SourceAccount": this.account },
        },
      }),
      inlinePolicies: {
        S3PutObject: new iam.PolicyDocument({
          statements: [
            new iam.PolicyStatement({
              actions: ["s3:PutObject"],
              resources: [emailBucket.arnForObjects("*")],
            }),
          ],
        }),
      },
    });

    // ---------------------------------------------------------------
    // IAM Role — Send to internet action (ses:SendRawEmail)
    //
    // SES SANDBOX: In sandbox mode, SendRawEmail only works for
    // verified identities. Both sender and recipient must be verified.
    // Request production access to remove this restriction.
    // ---------------------------------------------------------------
    const sendRole = new iam.Role(this, "SendRole", {
      assumedBy: new iam.ServicePrincipal("ses.amazonaws.com", {
        conditions: {
          StringEquals: { "aws:SourceAccount": this.account },
        },
      }),
      inlinePolicies: {
        SESSendRawEmail: new iam.PolicyDocument({
          statements: [
            new iam.PolicyStatement({
              actions: ["ses:SendRawEmail"],
              resources: [
                `arn:${this.partition}:ses:${this.region}:${this.account}:identity/*`,
                `arn:${this.partition}:ses:${this.region}:${this.account}:configuration-set/*`,
              ],
            }),
          ],
        }),
      },
    });

    // ---------------------------------------------------------------
    // Traffic Policy — Allow all connections
    //
    // TODO: Tighten this for production. Common options:
    //   - Require TLS 1.2: Add ALLOW statement with TlsExpression
    //     (MINIMUM_TLS_VERSION / TLS1_2) and set DefaultAction to DENY
    //   - Restrict by recipient domain: Add ALLOW statement with
    //     StringExpression (RECIPIENT / ENDS_WITH / @yourdomain.com)
    //   - Block IP ranges: Add DENY statement with IpExpression
    // ---------------------------------------------------------------
    const trafficPolicy = new ses.CfnMailManagerTrafficPolicy(
      this,
      "TrafficPolicy",
      {
        trafficPolicyName: `${this.stackName}-allow-all`,
        defaultAction: "ALLOW",
        policyStatements: [],
      }
    );

    // ---------------------------------------------------------------
    // Rule Set — Three rules, no conditions (all fire on every message)
    //
    // Rule 1: Archive — store in Mail Manager archive
    // Rule 2: Write to S3 — store raw MIME in S3 bucket
    // Rule 3: Send to internet — deliver via SES SendRawEmail
    //
    // IMPORTANT: TargetArchive requires the short archive ID, not the
    // full ARN. CfnMailManagerArchive.attrArchiveId returns the ARN
    // (known CloudFormation behavior). We extract the ID with Fn::Select/Fn::Split.
    // ---------------------------------------------------------------
    const archiveId = cdk.Fn.select(
      1,
      cdk.Fn.split("/", archive.attrArchiveArn)
    );

    const ruleSet = new ses.CfnMailManagerRuleSet(this, "RuleSet", {
      ruleSetName: `${this.stackName}-rules`,
      rules: [
        {
          name: "archive",
          actions: [
            {
              archive: {
                targetArchive: archiveId,
                actionFailurePolicy: "CONTINUE",
              },
            },
          ],
        },
        {
          name: "write-to-s3",
          actions: [
            {
              writeToS3: {
                s3Bucket: emailBucket.bucketName,
                roleArn: s3WriteRole.roleArn,
                s3Prefix: "inbound/",
                actionFailurePolicy: "CONTINUE",
              },
            },
          ],
        },
        {
          name: "send-to-internet",
          actions: [
            {
              send: {
                roleArn: sendRole.roleArn,
                actionFailurePolicy: "CONTINUE",
              },
            },
          ],
        },
      ],
    });

    // ---------------------------------------------------------------
    // Ingress Point — Public, OPEN (no SMTP auth), IPv4
    //
    // After deployment, point your domain's MX record to the A Record
    // output. Wait for the ingress point to reach ACTIVE status before
    // updating DNS — email will bounce if DNS points to a provisioning
    // endpoint.
    // ---------------------------------------------------------------
    const ingressPoint = new ses.CfnMailManagerIngressPoint(
      this,
      "IngressPoint",
      {
        ingressPointName: `${this.stackName}-ingress`,
        type: "OPEN",
        ruleSetId: ruleSet.attrRuleSetId,
        trafficPolicyId: trafficPolicy.attrTrafficPolicyId,
      }
    );

    // ---------------------------------------------------------------
    // Outputs
    // ---------------------------------------------------------------
    new cdk.CfnOutput(this, "IngressPointARecord", {
      description:
        "DNS A Record for the ingress point — set as your MX record target",
      value: ingressPoint.attrARecord,
    });

    new cdk.CfnOutput(this, "IngressPointId", {
      description: "Ingress point resource ID",
      value: ingressPoint.attrIngressPointId,
    });

    new cdk.CfnOutput(this, "ArchiveId", {
      description: "Archive resource ID (use in API calls, not the ARN)",
      value: archiveId,
    });

    new cdk.CfnOutput(this, "S3BucketName", {
      description: "S3 bucket receiving inbound email",
      value: emailBucket.bucketName,
    });

    new cdk.CfnOutput(this, "SandboxReminder", {
      description:
        "SES sandbox: Send to internet only works for verified identities. " +
        "Request production access via the SES console.",
      value: "https://docs.aws.amazon.com/ses/latest/dg/request-production-access.html",
    });
  }
}
```

## Key CDK Patterns Demonstrated

- **Archive ID extraction**: `CfnMailManagerArchive.attrArchiveId` returns the full ARN (known CloudFormation behavior). Use `Fn.select(1, Fn.split("/", archive.attrArchiveArn))` to extract the short ID.
- **Unique resource names**: Append `cdk.Names.uniqueId(this).slice(-8)` to avoid `PENDING_DELETION` name collisions on redeployment.
- **Confused deputy protection**: All IAM roles use `aws:SourceAccount` condition to prevent cross-account abuse.
- **SES sandbox awareness**: Send to internet action only works for verified identities in sandbox mode.
