# Amazon SES and SES Mail Manager — API Reference Index

> AI-friendly markdown index covering Amazon SES v2 and SES Mail Manager APIs.

> Total: 275 operations, 266 data types across 2 services.

> **Note:** Some API names and data types (such as `GetBlacklistReports`, `BlacklistEntry`) use legacy terminology that is part of the official AWS API and cannot be changed. These names are documented here as-is for API compatibility. In all other contexts, this documentation uses current inclusive terminology (such as "deny list" instead of "blocklist").

## Amazon Simple Email Service

Amazon SES provides email sending, receiving, and management capabilities across two API surfaces.

### Amazon SES v2

> Amazon Simple Email Service - send, receive, and manage email at scale.

The following operations and data types are available in the Amazon SES v2 API.

#### Operations

The operations are grouped by functional area.

##### Sending Email

- [SendEmail](services/ses/docs/SendEmail.md): Sends an email message. You can use the Amazon SES API v2 to send the following types of messages:
- [SendBulkEmail](services/ses/docs/SendBulkEmail.md): Composes an email message to multiple destinations.
- [SendCustomVerificationEmail](services/ses/docs/SendCustomVerificationEmail.md): Adds an email address to the list of identities for your Amazon SES account in the current AWS Region and attempts to...

##### Email Identities

- [CreateEmailIdentity](services/ses/docs/CreateEmailIdentity.md): Starts the process of verifying an email identity. An _identity_ is an email address or domain that you use when you...
- [GetEmailIdentity](services/ses/docs/GetEmailIdentity.md): Provides information about a specific identity, including the identity's verification status, sending authorization...
- [ListEmailIdentities](services/ses/docs/ListEmailIdentities.md): Returns a list of all of the email identities that are associated with your AWS account. An identity can be either an...
- [DeleteEmailIdentity](services/ses/docs/DeleteEmailIdentity.md): Deletes an email identity. An identity can be either an email address or a domain name.
- [GetEmailIdentityPolicies](services/ses/docs/GetEmailIdentityPolicies.md): Returns the requested sending authorization policies for the given identity (an email address or a domain). The...
- [CreateEmailIdentityPolicy](services/ses/docs/CreateEmailIdentityPolicy.md): Creates the specified sending authorization policy for the given identity (an email address or a domain).
- [UpdateEmailIdentityPolicy](services/ses/docs/UpdateEmailIdentityPolicy.md): Updates the specified sending authorization policy for the given identity (an email address or a domain). This API...
- [DeleteEmailIdentityPolicy](services/ses/docs/DeleteEmailIdentityPolicy.md): Deletes the specified sending authorization policy for the given identity (an email address or a domain). This API...
- [PutEmailIdentityConfigurationSetAttributes](services/ses/docs/PutEmailIdentityConfigurationSetAttributes.md): Used to associate a configuration set with an email identity.
- [PutEmailIdentityDkimAttributes](services/ses/docs/PutEmailIdentityDkimAttributes.md): Used to enable or disable DKIM authentication for an email identity.
- [PutEmailIdentityDkimSigningAttributes](services/ses/docs/PutEmailIdentityDkimSigningAttributes.md): Used to configure or change the DKIM authentication settings for an email domain identity. You can use this operation...
- [PutEmailIdentityFeedbackAttributes](services/ses/docs/PutEmailIdentityFeedbackAttributes.md): Used to enable or disable feedback forwarding for an identity. This setting determines what happens when an identity is...
- [PutEmailIdentityMailFromAttributes](services/ses/docs/PutEmailIdentityMailFromAttributes.md): Used to enable or disable the custom Mail-From domain configuration for an email identity.

##### Email Templates

- [CreateEmailTemplate](services/ses/docs/CreateEmailTemplate.md): Creates an email template. Email templates enable you to send personalized email to one or more destinations in a...
- [GetEmailTemplate](services/ses/docs/GetEmailTemplate.md): Displays the template object (which includes the subject line, HTML part and text part) for the template you specify.
- [UpdateEmailTemplate](services/ses/docs/UpdateEmailTemplate.md): Updates an email template. Email templates enable you to send personalized email to one or more destinations in a...
- [DeleteEmailTemplate](services/ses/docs/DeleteEmailTemplate.md): Deletes an email template.
- [ListEmailTemplates](services/ses/docs/ListEmailTemplates.md): Lists the email templates present in your Amazon SES account in the current AWS Region.
- [TestRenderEmailTemplate](services/ses/docs/TestRenderEmailTemplate.md): Creates a preview of the MIME content of an email when provided with a template and a set of replacement data.

##### Configuration Sets

- [CreateConfigurationSet](services/ses/docs/CreateConfigurationSet.md): Create a configuration set. _Configuration sets_ are groups of rules that you can apply to the emails that you send....
- [GetConfigurationSet](services/ses/docs/GetConfigurationSet.md): Get information about an existing configuration set, including the dedicated IP pool that it's associated with, whether...
- [UpdateConfigurationSet](services/ses/docs/UpdateConfigurationSet.md)
- [ListConfigurationSets](services/ses/docs/ListConfigurationSets.md): List all of the configuration sets associated with your account in the current region.
- [DeleteConfigurationSet](services/ses/docs/DeleteConfigurationSet.md): Delete an existing configuration set.
- [GetConfigurationSetEventDestinations](services/ses/docs/GetConfigurationSetEventDestinations.md): Retrieve a list of event destinations that are associated with a configuration set.
- [CreateConfigurationSetEventDestination](services/ses/docs/CreateConfigurationSetEventDestination.md): Create an event destination. _Events_ include message sends, deliveries, opens, clicks, bounces, and complaints. _Event...
- [UpdateConfigurationSetEventDestination](services/ses/docs/UpdateConfigurationSetEventDestination.md): Update the configuration of an event destination for a configuration set.
- [DeleteConfigurationSetEventDestination](services/ses/docs/DeleteConfigurationSetEventDestination.md): Delete an event destination.
- [PutConfigurationSetDeliveryOptions](services/ses/docs/PutConfigurationSetDeliveryOptions.md): Associate a configuration set with a dedicated IP pool. You can use dedicated IP pools to create groups of dedicated IP...
- [PutConfigurationSetReputationOptions](services/ses/docs/PutConfigurationSetReputationOptions.md): Enable or disable collection of reputation metrics for emails that you send using a particular configuration set in a...
- [PutConfigurationSetSendingOptions](services/ses/docs/PutConfigurationSetSendingOptions.md): Enable or disable email sending for messages that use a particular configuration set in a specific AWS Region.
- [PutConfigurationSetSuppressionOptions](services/ses/docs/PutConfigurationSetSuppressionOptions.md): Specify the account suppression list preferences for a configuration set.
- [PutConfigurationSetTrackingOptions](services/ses/docs/PutConfigurationSetTrackingOptions.md): Specify a custom domain to use for open and click tracking elements in email that you send.
- [PutConfigurationSetVdmOptions](services/ses/docs/PutConfigurationSetVdmOptions.md): Specify VDM preferences for email that you send using the configuration set.

##### Contacts & Lists

- [CreateContact](services/ses/docs/CreateContact.md): Creates a contact, which is an end-user who is receiving the email, and adds them to a contact list.
- [GetContact](services/ses/docs/GetContact.md): Returns a contact from a contact list.
- [UpdateContact](services/ses/docs/UpdateContact.md): Updates a contact's preferences for a list.
- [DeleteContact](services/ses/docs/DeleteContact.md): Removes a contact from a contact list.
- [ListContacts](services/ses/docs/ListContacts.md): Lists the contacts present in a specific contact list.
- [CreateContactList](services/ses/docs/CreateContactList.md): Creates a contact list.
- [GetContactList](services/ses/docs/GetContactList.md): Returns contact list metadata. It does not return any information about the contacts present in the list.
- [UpdateContactList](services/ses/docs/UpdateContactList.md): Updates contact list metadata. This operation does a complete replacement.
- [DeleteContactList](services/ses/docs/DeleteContactList.md): Deletes a contact list and all of the contacts on that list.
- [ListContactLists](services/ses/docs/ListContactLists.md): Lists all of the contact lists available.

##### Dedicated IPs

- [CreateDedicatedIpPool](services/ses/docs/CreateDedicatedIpPool.md): Create a new pool of dedicated IP addresses. A pool can include one or more dedicated IP addresses that are associated...
- [GetDedicatedIp](services/ses/docs/GetDedicatedIp.md): Get information about a dedicated IP address, including the name of the dedicated IP pool that it's associated with, as...
- [GetDedicatedIpPool](services/ses/docs/GetDedicatedIpPool.md): Retrieve information about the dedicated pool.
- [GetDedicatedIps](services/ses/docs/GetDedicatedIps.md): List the dedicated IP addresses that are associated with your AWS account.
- [ListDedicatedIpPools](services/ses/docs/ListDedicatedIpPools.md): List all of the dedicated IP pools that exist in your AWS account in the current Region.
- [DeleteDedicatedIpPool](services/ses/docs/DeleteDedicatedIpPool.md): Delete a dedicated IP pool.
- [PutDedicatedIpInPool](services/ses/docs/PutDedicatedIpInPool.md): Move a dedicated IP address to an existing dedicated IP pool.
- [PutDedicatedIpPoolScalingAttributes](services/ses/docs/PutDedicatedIpPoolScalingAttributes.md): Used to convert a dedicated IP pool to a different scaling mode.
- [PutDedicatedIpWarmupAttributes](services/ses/docs/PutDedicatedIpWarmupAttributes.md): PUT /v2/email/dedicated-ips/IP/warmup HTTP/1.1 Content-type: application/json

##### Suppression List

- [PutSuppressedDestination](services/ses/docs/PutSuppressedDestination.md): Adds an email address to the suppression list for your account.
- [GetSuppressedDestination](services/ses/docs/GetSuppressedDestination.md): Retrieves information about a specific email address that's on the suppression list for your account.
- [ListSuppressedDestinations](services/ses/docs/ListSuppressedDestinations.md): Retrieves a list of email addresses that are on the suppression list for your account.
- [DeleteSuppressedDestination](services/ses/docs/DeleteSuppressedDestination.md): Removes an email address from the suppression list for your account.

##### Deliverability & Metrics

- [BatchGetMetricData](services/ses/docs/BatchGetMetricData.md): Retrieves batches of metric data collected based on your sending activity.
- [GetDeliverabilityDashboardOptions](services/ses/docs/GetDeliverabilityDashboardOptions.md): Retrieve information about the status of the Deliverability dashboard for your account. When the Deliverability...
- [PutDeliverabilityDashboardOption](services/ses/docs/PutDeliverabilityDashboardOption.md): Enable or disable the Deliverability dashboard. When you enable the Deliverability dashboard, you gain access to...
- [GetDeliverabilityTestReport](services/ses/docs/GetDeliverabilityTestReport.md): Retrieve the results of a predictive inbox placement test.
- [ListDeliverabilityTestReports](services/ses/docs/ListDeliverabilityTestReports.md): Show a list of the predictive inbox placement tests that you've performed, regardless of their statuses. For predictive...
- [CreateDeliverabilityTestReport](services/ses/docs/CreateDeliverabilityTestReport.md): Create a new predictive inbox placement test. Predictive inbox placement tests can help you predict how your messages...
- [GetDomainDeliverabilityCampaign](services/ses/docs/GetDomainDeliverabilityCampaign.md): Retrieve all the deliverability data for a specific campaign. This data is available for a campaign only if the...
- [ListDomainDeliverabilityCampaigns](services/ses/docs/ListDomainDeliverabilityCampaigns.md): Retrieve deliverability data for all the campaigns that used a specific domain to send email during a specified time...
- [GetDomainStatisticsReport](services/ses/docs/GetDomainStatisticsReport.md): Retrieve inbox placement and engagement rates for the domains that you use to send email.
- [GetMessageInsights](services/ses/docs/GetMessageInsights.md): Provides information about a specific message, including the from address, the subject, the recipient address, email...
- [GetBlacklistReports](services/ses/docs/GetBlacklistReports.md): Retrieve a list of the deny lists that your dedicated IP addresses appear on.

##### Import & Export

- [CreateImportJob](services/ses/docs/CreateImportJob.md): Creates an import job for a data destination.
- [GetImportJob](services/ses/docs/GetImportJob.md): Provides information about an import job.
- [ListImportJobs](services/ses/docs/ListImportJobs.md): Lists all of the import jobs.
- [CreateExportJob](services/ses/docs/CreateExportJob.md): Creates an export job for a data source and destination.
- [GetExportJob](services/ses/docs/GetExportJob.md): Provides information about an export job.
- [ListExportJobs](services/ses/docs/ListExportJobs.md): Lists all of the export jobs.
- [CancelExportJob](services/ses/docs/CancelExportJob.md): Cancels an export job.

##### Account Management

- [GetAccount](services/ses/docs/GetAccount.md): Obtain information about the email-sending status and capabilities of your Amazon SES account in the current AWS Region.
- [PutAccountDetails](services/ses/docs/PutAccountDetails.md): Update your Amazon SES account details.
- [PutAccountDedicatedIpWarmupAttributes](services/ses/docs/PutAccountDedicatedIpWarmupAttributes.md): Enable or disable the automatic warm-up feature for dedicated IP addresses.
- [PutAccountSendingAttributes](services/ses/docs/PutAccountSendingAttributes.md): Enable or disable the ability of your account to send email.
- [PutAccountSuppressionAttributes](services/ses/docs/PutAccountSuppressionAttributes.md): Change the settings for the account-level suppression list.
- [PutAccountVdmAttributes](services/ses/docs/PutAccountVdmAttributes.md): Update your Amazon SES account VDM attributes.

##### Custom Verification

- [CreateCustomVerificationEmailTemplate](services/ses/docs/CreateCustomVerificationEmailTemplate.md): Creates a new custom verification email template.
- [GetCustomVerificationEmailTemplate](services/ses/docs/GetCustomVerificationEmailTemplate.md): Returns the custom email verification template for the template name you specify.
- [UpdateCustomVerificationEmailTemplate](services/ses/docs/UpdateCustomVerificationEmailTemplate.md): Updates an existing custom verification email template.
- [DeleteCustomVerificationEmailTemplate](services/ses/docs/DeleteCustomVerificationEmailTemplate.md): Deletes an existing custom verification email template.
- [ListCustomVerificationEmailTemplates](services/ses/docs/ListCustomVerificationEmailTemplates.md): Lists the existing custom verification email templates for your account in the current AWS Region.

##### Tagging

- [TagResource](services/ses/docs/TagResource.md): Add one or more tags (keys and values) to a specified resource. A _tag_ is a label that you optionally define and...
- [UntagResource](services/ses/docs/UntagResource.md): Remove one or more tags (keys and values) from a specified resource.
- [ListTagsForResource](services/ses/docs/ListTagsForResource.md): Retrieve a list of the tags (keys and values) that are associated with a specified resource. A  _tag_ is a label that...

##### Multi-Region & Tenants

- [CreateMultiRegionEndpoint](services/ses/docs/CreateMultiRegionEndpoint.md): Creates a multi-region endpoint (global-endpoint).
- [GetMultiRegionEndpoint](services/ses/docs/GetMultiRegionEndpoint.md): Displays the multi-region endpoint (global-endpoint) configuration.
- [ListMultiRegionEndpoints](services/ses/docs/ListMultiRegionEndpoints.md): List the multi-region endpoints (global-endpoints).
- [DeleteMultiRegionEndpoint](services/ses/docs/DeleteMultiRegionEndpoint.md): Deletes a multi-region endpoint (global-endpoint).
- [CreateTenant](services/ses/docs/CreateTenant.md): Create a tenant.
- [GetTenant](services/ses/docs/GetTenant.md): Get information about a specific tenant, including the tenant's name, ID, ARN, creation timestamp, tags, and sending...
- [ListTenants](services/ses/docs/ListTenants.md): List all tenants associated with your account in the current AWS Region.
- [DeleteTenant](services/ses/docs/DeleteTenant.md): Delete an existing tenant.

##### Reputation

- [ListRecommendations](services/ses/docs/ListRecommendations.md): Lists the recommendations present in your Amazon SES account in the current AWS Region.
- [GetReputationEntity](services/ses/docs/GetReputationEntity.md): Retrieve information about a specific reputation entity, including its reputation management policy, customer-managed...
- [ListReputationEntities](services/ses/docs/ListReputationEntities.md): List reputation entities in your Amazon SES account in the current AWS Region. You can filter the results by entity...

#### Data Types

- [AccountDetails](services/ses/types/AccountDetails.md): An object that contains information about your account details.
- [ArchivingOptions](services/ses/types/ArchivingOptions.md): Used to associate a configuration set with a MailManager archive.
- [Attachment](services/ses/types/Attachment.md): Contains metadata and attachment raw content.
- [BatchGetMetricDataQuery](services/ses/types/BatchGetMetricDataQuery.md): Represents a single metric data query to include in a batch.
- [BlacklistEntry](services/ses/types/BlacklistEntry.md): An object that contains information about a deny listing event that impacts one of the dedicated IP addresses that is...
- [Body](services/ses/types/Body.md): Represents the body of the email message.
- [Bounce](services/ses/types/Bounce.md): Information about a `Bounce` event.
- [BulkEmailContent](services/ses/types/BulkEmailContent.md): An object that contains the body of the message. You can specify a template message.
- [BulkEmailEntry](services/ses/types/BulkEmailEntry.md): Destination
- [BulkEmailEntryResult](services/ses/types/BulkEmailEntryResult.md): The result of the `SendBulkEmail` operation of each specified `BulkEmailEntry`.
- [CloudWatchDestination](services/ses/types/CloudWatchDestination.md): An object that defines an Amazon CloudWatch destination for email events. You can use Amazon CloudWatch to monitor and...
- [CloudWatchDimensionConfiguration](services/ses/types/CloudWatchDimensionConfiguration.md): An object that defines the dimension configuration to use when you send email events to Amazon CloudWatch.
- [Complaint](services/ses/types/Complaint.md): Information about a `Complaint` event.
- [Contact](services/ses/types/Contact.md): A contact is the end-user who is receiving the email.
- [ContactList](services/ses/types/ContactList.md): A list that contains contacts that have subscribed to a particular topic or topics.
- [ContactListDestination](services/ses/types/ContactListDestination.md): An object that contains details about the action of a contact list.
- [Content](services/ses/types/Content.md): An object that represents the content of the email, and optionally a character set specification.
- [CustomVerificationEmailTemplateMetadata](services/ses/types/CustomVerificationEmailTemplateMetadata.md): Contains information about a custom verification email template.
- [DailyVolume](services/ses/types/DailyVolume.md): An object that contains information about the volume of email sent on each day of the analysis period.
- [DashboardAttributes](services/ses/types/DashboardAttributes.md): An object containing additional settings for your VDM configuration as applicable to the Dashboard.
- [DashboardOptions](services/ses/types/DashboardOptions.md): An object containing additional settings for your VDM configuration as applicable to the Dashboard.
- [DedicatedIp](services/ses/types/DedicatedIp.md): Contains information about a dedicated IP address that is associated with your Amazon SES account.
- [DedicatedIpPool](services/ses/types/DedicatedIpPool.md): Contains information about a dedicated IP pool.
- [DeliverabilityTestReport](services/ses/types/DeliverabilityTestReport.md): An object that contains metadata related to a predictive inbox placement test.
- [DeliveryOptions](services/ses/types/DeliveryOptions.md): Used to associate a configuration set with a dedicated IP pool.
- [Destination](services/ses/types/Destination.md): An object that describes the recipients for an email.
- [Details](services/ses/types/Details.md): An object that contains configuration details of multi-region endpoint (global-endpoint).
- [DkimAttributes](services/ses/types/DkimAttributes.md): An object that contains information about the DKIM authentication status for an email identity.
- [DkimSigningAttributes](services/ses/types/DkimSigningAttributes.md): An object that contains configuration for Bring Your Own DKIM (BYODKIM), or, for Easy DKIM
- [DomainDeliverabilityCampaign](services/ses/types/DomainDeliverabilityCampaign.md): An object that contains the deliverability data for a specific campaign. This data is available for a campaign only if...
- [DomainDeliverabilityTrackingOption](services/ses/types/DomainDeliverabilityTrackingOption.md): An object that contains information about the Deliverability dashboard subscription for a verified domain that you use...
- [DomainIspPlacement](services/ses/types/DomainIspPlacement.md): An object that contains inbox placement data for email sent from one of your email domains to a specific email provider.
- [EmailAddressInsightsMailboxEvaluations](services/ses/types/EmailAddressInsightsMailboxEvaluations.md): Contains individual validation checks performed on an email address.
- [EmailAddressInsightsVerdict](services/ses/types/EmailAddressInsightsVerdict.md): Contains the overall validation verdict for an email address.
- [EmailContent](services/ses/types/EmailContent.md): An object that defines the entire content of the email, including the message headers, body content, and attachments....
- [EmailInsights](services/ses/types/EmailInsights.md): An email's insights contain metadata and delivery information about a specific email.
- [EmailTemplateContent](services/ses/types/EmailTemplateContent.md): The content of the email, composed of a subject line, an HTML part, and a text-only part.
- [EmailTemplateMetadata](services/ses/types/EmailTemplateMetadata.md): Contains information about an email template.
- [EventBridgeDestination](services/ses/types/EventBridgeDestination.md): An object that defines an Amazon EventBridge destination for email events. You can use Amazon EventBridge to send...
- [EventDestination](services/ses/types/EventDestination.md): In the Amazon SES API v2, _events_ include message sends, deliveries, opens, clicks, bounces, complaints and delivery...
- [EventDestinationDefinition](services/ses/types/EventDestinationDefinition.md): An object that defines the event destination. Specifically, it defines which services receive events from emails sent...
- [EventDetails](services/ses/types/EventDetails.md): Contains a `Bounce` object if the event type is `BOUNCE`. Contains a `Complaint` object if the event type is...
- [ExportDataSource](services/ses/types/ExportDataSource.md): An object that contains details about the data source of the export job. It can only contain one of `MetricsDataSource`...
- [ExportDestination](services/ses/types/ExportDestination.md): An object that contains details about the destination of the export job.
- [ExportJobSummary](services/ses/types/ExportJobSummary.md): A summary of the export job.
- [ExportMetric](services/ses/types/ExportMetric.md): An object that contains a mapping between a `Metric` and `MetricAggregation`.
- [ExportStatistics](services/ses/types/ExportStatistics.md): Statistics about the execution of an export job.
- [FailureInfo](services/ses/types/FailureInfo.md): An object that contains the failure details about a job.
- [GuardianAttributes](services/ses/types/GuardianAttributes.md): An object containing additional settings for your VDM configuration as applicable to the Guardian.
- [GuardianOptions](services/ses/types/GuardianOptions.md): An object containing additional settings for your VDM configuration as applicable to the Guardian.
- [IdentityInfo](services/ses/types/IdentityInfo.md): Information about an email identity.
- [ImportDataSource](services/ses/types/ImportDataSource.md): An object that contains details about the data source of the import job.
- [ImportDestination](services/ses/types/ImportDestination.md): An object that contains details about the resource destination the import job is going to target.
- [ImportJobSummary](services/ses/types/ImportJobSummary.md): A summary of the import job.
- [InboxPlacementTrackingOption](services/ses/types/InboxPlacementTrackingOption.md): An object that contains information about the inbox placement data settings for a verified domain that's associated...
- [InsightsEvent](services/ses/types/InsightsEvent.md): An object containing details about a specific event.
- [IspPlacement](services/ses/types/IspPlacement.md): An object that describes how email sent during the predictive inbox placement test was handled by a certain email...
- [KinesisFirehoseDestination](services/ses/types/KinesisFirehoseDestination.md): An object that defines an Amazon Data Firehose destination for email events. You can use Amazon Data Firehose...
- [ListContactsFilter](services/ses/types/ListContactsFilter.md): A filter that can be applied to a list of contacts.
- [ListManagementOptions](services/ses/types/ListManagementOptions.md): An object used to specify a list or topic to which an email belongs, which will be used when a contact chooses to...
- [MailboxValidation](services/ses/types/MailboxValidation.md): Contains detailed validation information about an email address.
- [MailFromAttributes](services/ses/types/MailFromAttributes.md): A list of attributes that are associated with a MAIL FROM domain.
- [Message](services/ses/types/Message.md): Represents the email message that you're sending. The `Message` object consists of a subject line and a message body.
- [MessageHeader](services/ses/types/MessageHeader.md): Contains the name and value of a message header that you add to an email.
- [MessageInsightsDataSource](services/ses/types/MessageInsightsDataSource.md): An object that contains filters applied when performing the Message Insights export.
- [MessageInsightsFilters](services/ses/types/MessageInsightsFilters.md): An object containing Message Insights filters.
- [MessageTag](services/ses/types/MessageTag.md): Contains the name and value of a tag that you apply to an email. You can use message tags when you publish email...
- [MetricDataError](services/ses/types/MetricDataError.md): An error corresponding to the unsuccessful processing of a single metric data query.
- [MetricDataResult](services/ses/types/MetricDataResult.md): The result of a single metric data query.
- [MetricsDataSource](services/ses/types/MetricsDataSource.md): An object that contains details about the data source for the metrics export.
- [MultiRegionEndpoint](services/ses/types/MultiRegionEndpoint.md): An object that contains multi-region endpoint (global-endpoint) properties.
- [OverallVolume](services/ses/types/OverallVolume.md): An object that contains information about email that was sent from the selected domain.
- [PinpointDestination](services/ses/types/PinpointDestination.md): An object that defines an Amazon Pinpoint project destination for email events. You can send email event data to a...
- [PlacementStatistics](services/ses/types/PlacementStatistics.md): An object that contains inbox placement data for an email provider.
- [RawMessage](services/ses/types/RawMessage.md): Represents the raw content of an email message.
- [Recommendation](services/ses/types/Recommendation.md): A recommendation generated for your account.
- [ReplacementEmailContent](services/ses/types/ReplacementEmailContent.md): The `ReplaceEmailContent` object to be used for a specific `BulkEmailEntry`. The `ReplacementTemplate` can be specified...
- [ReplacementTemplate](services/ses/types/ReplacementTemplate.md): An object which contains `ReplacementTemplateData` to be used for a specific `BulkEmailEntry`.
- [ReputationEntity](services/ses/types/ReputationEntity.md): An object that contains information about a reputation entity, including its reference, type, policy, status records,...
- [ReputationOptions](services/ses/types/ReputationOptions.md): Enable or disable collection of reputation metrics for emails that you send using this configuration set in the current...
- [ResourceTenantMetadata](services/ses/types/ResourceTenantMetadata.md): A structure that contains information about a tenant associated with a resource.
- [ReviewDetails](services/ses/types/ReviewDetails.md): An object that contains information about your account details review.
- [Route](services/ses/types/Route.md): An object which contains an AWS-Region and routing status.
- [RouteDetails](services/ses/types/RouteDetails.md): An object that contains route configuration. Includes secondary region name.
- [SendingOptions](services/ses/types/SendingOptions.md): Used to enable or disable email sending for messages that use this configuration set in the current AWS Region.
- [SendQuota](services/ses/types/SendQuota.md): An object that contains information about the per-day and per-second sending limits for your Amazon SES account in the...
- [SnsDestination](services/ses/types/SnsDestination.md): An object that defines an Amazon SNS destination for email events. You can use Amazon SNS to send notifications when...
- [SOARecord](services/ses/types/SOARecord.md): An object that contains information about the start of authority (SOA) record associated with the identity.
- [StatusRecord](services/ses/types/StatusRecord.md): An object that contains status information for a reputation entity, including the current status, cause description,...
- [SuppressedDestination](services/ses/types/SuppressedDestination.md): An object that contains information about an email address that is on the suppression list for your account.
- [SuppressedDestinationAttributes](services/ses/types/SuppressedDestinationAttributes.md): An object that contains additional attributes that are related an email address that is on the suppression list for...
- [SuppressedDestinationSummary](services/ses/types/SuppressedDestinationSummary.md): A summary that describes the suppressed email address.
- [SuppressionAttributes](services/ses/types/SuppressionAttributes.md): An object that contains information about the email address suppression preferences for your account in the current AWS...
- [SuppressionConditionThreshold](services/ses/types/SuppressionConditionThreshold.md): Contains Auto Validation settings, allowing you to suppress sending to specific destination(s) if they do not meet...
- [SuppressionConfidenceThreshold](services/ses/types/SuppressionConfidenceThreshold.md): Contains the confidence threshold settings for Auto Validation.
- [SuppressionListDestination](services/ses/types/SuppressionListDestination.md): An object that contains details about the action of suppression list.
- [SuppressionOptions](services/ses/types/SuppressionOptions.md): An object that contains information about the suppression list preferences for your account.
- [SuppressionValidationAttributes](services/ses/types/SuppressionValidationAttributes.md): Structure containing validation attributes used for suppressing sending to specific destination on account level.
- [SuppressionValidationOptions](services/ses/types/SuppressionValidationOptions.md): Contains validation options for email address suppression.
- [Tag](services/ses/types/Tag.md): An object that defines the tags that are associated with a resource. A  _tag_ is a label that you optionally define and...
- [Template](services/ses/types/Template.md): An object that defines the email template to use for an email message, and the values to use for any message variables...
- [Tenant](services/ses/types/Tenant.md): A structure that contains details about a tenant.
- [TenantInfo](services/ses/types/TenantInfo.md): A structure that contains basic information about a tenant.
- [TenantResource](services/ses/types/TenantResource.md): A structure that contains information about a resource associated with a tenant.
- [Topic](services/ses/types/Topic.md): An interest group, theme, or label within a list. Lists can have multiple topics.
- [TopicFilter](services/ses/types/TopicFilter.md): Used for filtering by a specific topic preference.
- [TopicPreference](services/ses/types/TopicPreference.md): The contact's preference for being opted-in to or opted-out of a topic.
- [TrackingOptions](services/ses/types/TrackingOptions.md): An object that defines the tracking options for a configuration set. When you use the Amazon SES API v2 to send an...
- [VdmAttributes](services/ses/types/VdmAttributes.md): The VDM attributes that apply to your Amazon SES account.
- [VdmOptions](services/ses/types/VdmOptions.md): An object that defines the VDM settings that apply to emails that you send using the configuration set.
- [VerificationInfo](services/ses/types/VerificationInfo.md): An object that contains additional information about the verification status for the identity.
- [VolumeStatistics](services/ses/types/VolumeStatistics.md): An object that contains information about the amount of email that was delivered to recipients.

### SES Mail Manager

> SES Mail Manager - manage email ingress, archiving, rules, relays, and traffic policies.

The following operations and data types are available in the SES Mail Manager API.

#### Operations

Operations are grouped by resource type.

##### Add-ons

- [CreateAddonInstance](services/mail-manager/docs/CreateAddonInstance.md): Creates an Add On instance for the subscription indicated in the request. The resulting Amazon Resource Name (ARN) can...
- [CreateAddonSubscription](services/mail-manager/docs/CreateAddonSubscription.md): Creates a subscription for an Add On representing the acceptance of its terms of use and additional pricing. The...
- [DeleteAddonInstance](services/mail-manager/docs/DeleteAddonInstance.md): Deletes an Add On instance.
- [DeleteAddonSubscription](services/mail-manager/docs/DeleteAddonSubscription.md): Deletes an Add On subscription.
- [GetAddonInstance](services/mail-manager/docs/GetAddonInstance.md): Gets detailed information about an Add On instance.
- [GetAddonSubscription](services/mail-manager/docs/GetAddonSubscription.md): Gets detailed information about an Add On subscription.
- [ListAddonInstances](services/mail-manager/docs/ListAddonInstances.md): Lists all Add On instances in your account.
- [ListAddonSubscriptions](services/mail-manager/docs/ListAddonSubscriptions.md): Lists all Add On subscriptions in your account.

##### Address Lists

- [CreateAddressList](services/mail-manager/docs/CreateAddressList.md): Creates a new address list.
- [CreateAddressListImportJob](services/mail-manager/docs/CreateAddressListImportJob.md): Creates an import job for an address list.
- [DeleteAddressList](services/mail-manager/docs/DeleteAddressList.md): Deletes an address list.
- [DeregisterMemberFromAddressList](services/mail-manager/docs/DeregisterMemberFromAddressList.md): Removes a member from an address list.
- [GetAddressList](services/mail-manager/docs/GetAddressList.md): Fetch attributes of an address list.
- [GetAddressListImportJob](services/mail-manager/docs/GetAddressListImportJob.md): Fetch attributes of an import job.
- [GetMemberOfAddressList](services/mail-manager/docs/GetMemberOfAddressList.md): Fetch attributes of a member in an address list.
- [ListAddressListImportJobs](services/mail-manager/docs/ListAddressListImportJobs.md): Lists jobs for an address list.
- [ListAddressLists](services/mail-manager/docs/ListAddressLists.md): Lists address lists for this account.
- [ListMembersOfAddressList](services/mail-manager/docs/ListMembersOfAddressList.md): Lists members of an address list.
- [RegisterMemberToAddressList](services/mail-manager/docs/RegisterMemberToAddressList.md): Adds a member to an address list.
- [StartAddressListImportJob](services/mail-manager/docs/StartAddressListImportJob.md): Starts an import job for an address list.
- [StopAddressListImportJob](services/mail-manager/docs/StopAddressListImportJob.md): Stops an ongoing import job for an address list.

##### Archives

- [CreateArchive](services/mail-manager/docs/CreateArchive.md): Creates a new email archive resource for storing and retaining emails.
- [DeleteArchive](services/mail-manager/docs/DeleteArchive.md): Initiates deletion of an email archive. This changes the archive state to pending deletion. In this state, no new...
- [GetArchive](services/mail-manager/docs/GetArchive.md): Retrieves the full details and current state of a specified email archive.
- [GetArchiveExport](services/mail-manager/docs/GetArchiveExport.md): Retrieves the details and current status of a specific email archive export job.
- [GetArchiveMessage](services/mail-manager/docs/GetArchiveMessage.md): Returns a pre-signed URL that provides temporary download access to the specific email message stored in the archive.
- [GetArchiveMessageContent](services/mail-manager/docs/GetArchiveMessageContent.md): Returns the textual content of a specific email message stored in the archive. Attachments are not included.
- [GetArchiveSearch](services/mail-manager/docs/GetArchiveSearch.md): Retrieves the details and current status of a specific email archive search job.
- [GetArchiveSearchResults](services/mail-manager/docs/GetArchiveSearchResults.md): Returns the results of a completed email archive search job.
- [ListArchiveExports](services/mail-manager/docs/ListArchiveExports.md): Returns a list of email archive export jobs.
- [ListArchives](services/mail-manager/docs/ListArchives.md): Returns a list of all email archives in your account.
- [ListArchiveSearches](services/mail-manager/docs/ListArchiveSearches.md): Returns a list of email archive search jobs.
- [StartArchiveExport](services/mail-manager/docs/StartArchiveExport.md): Initiates an export of emails from the specified archive.
- [StartArchiveSearch](services/mail-manager/docs/StartArchiveSearch.md): Initiates a search across emails in the specified archive.
- [StopArchiveExport](services/mail-manager/docs/StopArchiveExport.md): Stops an in-progress export of emails from an archive.
- [StopArchiveSearch](services/mail-manager/docs/StopArchiveSearch.md): Stops an in-progress archive search job.
- [UpdateArchive](services/mail-manager/docs/UpdateArchive.md): Updates the attributes of an existing email archive.

##### Ingress Points

- [CreateIngressPoint](services/mail-manager/docs/CreateIngressPoint.md): Provision a new ingress endpoint resource.
- [DeleteIngressPoint](services/mail-manager/docs/DeleteIngressPoint.md): Delete an ingress endpoint resource.
- [GetIngressPoint](services/mail-manager/docs/GetIngressPoint.md): Fetch ingress endpoint resource attributes.
- [ListIngressPoints](services/mail-manager/docs/ListIngressPoints.md): List all ingress endpoint resources.
- [UpdateIngressPoint](services/mail-manager/docs/UpdateIngressPoint.md): Update attributes of a provisioned ingress endpoint resource.

##### Relays

- [CreateRelay](services/mail-manager/docs/CreateRelay.md): Creates a relay resource which can be used in rules to relay incoming emails to defined relay destinations.
- [DeleteRelay](services/mail-manager/docs/DeleteRelay.md): Deletes an existing relay resource.
- [GetRelay](services/mail-manager/docs/GetRelay.md): Fetch the relay resource and it's attributes.
- [ListRelays](services/mail-manager/docs/ListRelays.md): Lists all the existing relay resources.
- [UpdateRelay](services/mail-manager/docs/UpdateRelay.md): Updates the attributes of an existing relay resource.

##### Rule Sets

- [CreateRuleSet](services/mail-manager/docs/CreateRuleSet.md): Provision a new rule set.
- [DeleteRuleSet](services/mail-manager/docs/DeleteRuleSet.md): Delete a rule set.
- [GetRuleSet](services/mail-manager/docs/GetRuleSet.md): Fetch attributes of a rule set.
- [ListRuleSets](services/mail-manager/docs/ListRuleSets.md): List rule sets for this account.
- [UpdateRuleSet](services/mail-manager/docs/UpdateRuleSet.md): Update attributes of an already provisioned rule set.

##### Traffic Policies

- [CreateTrafficPolicy](services/mail-manager/docs/CreateTrafficPolicy.md): Provision a new traffic policy resource.
- [DeleteTrafficPolicy](services/mail-manager/docs/DeleteTrafficPolicy.md): Delete a traffic policy resource.
- [GetTrafficPolicy](services/mail-manager/docs/GetTrafficPolicy.md): Fetch attributes of a traffic policy resource.
- [ListTrafficPolicies](services/mail-manager/docs/ListTrafficPolicies.md): List traffic policy resources.
- [UpdateTrafficPolicy](services/mail-manager/docs/UpdateTrafficPolicy.md): Update attributes of an already provisioned traffic policy resource.

##### Tagging

- [ListTagsForResource](services/mail-manager/docs/ListTagsForResource.md): Retrieves the list of tags (keys and values) assigned to the resource.
- [TagResource](services/mail-manager/docs/TagResource.md): Adds one or more tags (keys and values) to a specified resource.
- [UntagResource](services/mail-manager/docs/UntagResource.md): Remove one or more tags (keys and values) from a specified resource.

#### Data Types

- [AddHeaderAction](services/mail-manager/types/AddHeaderAction.md): The action to add a header to a message. When executed, this action will add the given header to the message.
- [AddonInstance](services/mail-manager/types/AddonInstance.md): An Add On instance represents a specific configuration of an Add On.
- [AddonSubscription](services/mail-manager/types/AddonSubscription.md): A subscription for an Add On representing the acceptance of its terms of use and additional pricing.
- [AddressFilter](services/mail-manager/types/AddressFilter.md): Filtering options for ListMembersOfAddressList operation.
- [AddressList](services/mail-manager/types/AddressList.md): An address list contains a list of emails and domains that are used in MailManager Ingress endpoints and Rules for...
- [Analysis](services/mail-manager/types/Analysis.md): The result of an analysis can be used in conditions to trigger actions. Analyses can inspect the email content and...
- [Archive](services/mail-manager/types/Archive.md): An archive resource for storing and retaining emails.
- [ArchiveAction](services/mail-manager/types/ArchiveAction.md): The action to archive the email by delivering the email to an Amazon SES archive.
- [ArchiveBooleanExpression](services/mail-manager/types/ArchiveBooleanExpression.md): A boolean expression to evaluate email attribute values.
- [ArchiveBooleanToEvaluate](services/mail-manager/types/ArchiveBooleanToEvaluate.md): The attribute to evaluate in a boolean expression.
- [ArchiveFilterCondition](services/mail-manager/types/ArchiveFilterCondition.md): A filter condition used to include or exclude emails when exporting from or searching an archive.
- [ArchiveFilters](services/mail-manager/types/ArchiveFilters.md): A set of filter conditions to include and/or exclude emails.
- [ArchiveRetention](services/mail-manager/types/ArchiveRetention.md): The retention policy for an email archive that specifies how long emails are kept before being automatically deleted.
- [ArchiveStringExpression](services/mail-manager/types/ArchiveStringExpression.md): A string expression to evaluate an email attribute value against one or more string values.
- [ArchiveStringToEvaluate](services/mail-manager/types/ArchiveStringToEvaluate.md): Specifies the email attribute to evaluate in a string expression.
- [DeliverToMailboxAction](services/mail-manager/types/DeliverToMailboxAction.md): This action to delivers an email to a mailbox.
- [DeliverToQBusinessAction](services/mail-manager/types/DeliverToQBusinessAction.md): The action to deliver incoming emails to an Amazon Q Business application for indexing.
- [DropAction](services/mail-manager/types/DropAction.md): This action causes processing to stop and the email to be dropped. If the action applies only to certain recipients,...
- [Envelope](services/mail-manager/types/Envelope.md): The SMTP envelope information of the email.
- [ExportDestinationConfiguration](services/mail-manager/types/ExportDestinationConfiguration.md): The destination configuration for delivering exported email data.
- [ExportStatus](services/mail-manager/types/ExportStatus.md): The current status of an archive export job.
- [ExportSummary](services/mail-manager/types/ExportSummary.md): Summary statuses of an archive export job.
- [ImportDataFormat](services/mail-manager/types/ImportDataFormat.md): The import data format contains the specifications of the input file that would be passed to the address list import...
- [ImportJob](services/mail-manager/types/ImportJob.md): Details about an import job.
- [IngressAnalysis](services/mail-manager/types/IngressAnalysis.md): The Add On ARN and its returned value that is evaluated in a policy statement's conditional expression to either deny...
- [IngressBooleanExpression](services/mail-manager/types/IngressBooleanExpression.md): The structure for a boolean condition matching on the incoming mail.
- [IngressBooleanToEvaluate](services/mail-manager/types/IngressBooleanToEvaluate.md): The union type representing the allowed types of operands for a boolean condition.
- [IngressIpToEvaluate](services/mail-manager/types/IngressIpToEvaluate.md): The structure for an IP based condition matching on the incoming mail.
- [IngressIpv4Expression](services/mail-manager/types/IngressIpv4Expression.md): The union type representing the allowed types for the left hand side of an IP condition.
- [IngressIpv6Expression](services/mail-manager/types/IngressIpv6Expression.md): The union type representing the allowed types for the left hand side of an IPv6 condition.
- [IngressIpv6ToEvaluate](services/mail-manager/types/IngressIpv6ToEvaluate.md): The structure for an IPv6 based condition matching on the incoming mail.
- [IngressIsInAddressList](services/mail-manager/types/IngressIsInAddressList.md): The address lists and the address list attribute value that is evaluated in a policy statement's conditional expression...
- [IngressPoint](services/mail-manager/types/IngressPoint.md): The structure of an ingress endpoint resource.
- [IngressPointAuthConfiguration](services/mail-manager/types/IngressPointAuthConfiguration.md): The authentication configuration for the ingress endpoint resource.
- [IngressPointConfiguration](services/mail-manager/types/IngressPointConfiguration.md): The configuration of the ingress endpoint resource.
- [IngressPointPasswordConfiguration](services/mail-manager/types/IngressPointPasswordConfiguration.md): The password configuration of the ingress endpoint resource.
- [IngressStringExpression](services/mail-manager/types/IngressStringExpression.md): The structure for a string based condition matching on the incoming mail.
- [IngressStringToEvaluate](services/mail-manager/types/IngressStringToEvaluate.md): The union type representing the allowed types for the left hand side of a string condition.
- [IngressTlsProtocolExpression](services/mail-manager/types/IngressTlsProtocolExpression.md): The structure for a TLS related condition matching on the incoming mail.
- [IngressTlsProtocolToEvaluate](services/mail-manager/types/IngressTlsProtocolToEvaluate.md): The union type representing the allowed types for the left hand side of a TLS condition.
- [MessageBody](services/mail-manager/types/MessageBody.md): The textual body content of an email message.
- [Metadata](services/mail-manager/types/Metadata.md): The metadata about the email.
- [NetworkConfiguration](services/mail-manager/types/NetworkConfiguration.md): The network type (IPv4-only, Dual-Stack, PrivateLink) of the ingress endpoint resource.
- [NoAuthentication](services/mail-manager/types/NoAuthentication.md): Explicitly indicate that the relay destination server does not require SMTP credential authentication.
- [PolicyCondition](services/mail-manager/types/PolicyCondition.md): The email traffic filtering conditions which are contained in a traffic policy resource.
- [PolicyStatement](services/mail-manager/types/PolicyStatement.md): The structure containing traffic policy conditions and actions.
- [PrivateNetworkConfiguration](services/mail-manager/types/PrivateNetworkConfiguration.md): Specifies the network configuration for the private ingress point.
- [PublicNetworkConfiguration](services/mail-manager/types/PublicNetworkConfiguration.md): Specifies the network configuration for the public ingress point.
- [Relay](services/mail-manager/types/Relay.md): The relay resource that can be used as a rule to relay receiving emails to the destination relay server.
- [RelayAction](services/mail-manager/types/RelayAction.md): The action relays the email via SMTP to another specific SMTP server.
- [RelayAuthentication](services/mail-manager/types/RelayAuthentication.md): Authentication for the relay destination server-specify the secretARN where the SMTP credentials are stored, or specify...
- [ReplaceRecipientAction](services/mail-manager/types/ReplaceRecipientAction.md): This action replaces the email envelope recipients with the given list of recipients. If the condition of this action...
- [Row](services/mail-manager/types/Row.md): A result row containing metadata for an archived email message.
- [Rule](services/mail-manager/types/Rule.md): A rule contains conditions, "unless conditions" and actions. For each envelope recipient of an email, if all conditions...
- [RuleAction](services/mail-manager/types/RuleAction.md): The action for a rule to take. Only one of the contained actions can be set.
- [RuleBooleanExpression](services/mail-manager/types/RuleBooleanExpression.md): A boolean expression to be used in a rule condition.
- [RuleBooleanToEvaluate](services/mail-manager/types/RuleBooleanToEvaluate.md): The union type representing the allowed types of operands for a boolean condition.
- [RuleCondition](services/mail-manager/types/RuleCondition.md): The conditional expression used to evaluate an email for determining if a rule action should be taken.
- [RuleDmarcExpression](services/mail-manager/types/RuleDmarcExpression.md): A DMARC policy expression. The condition matches if the given DMARC policy matches that of the incoming email.
- [RuleIpExpression](services/mail-manager/types/RuleIpExpression.md): An IP address expression matching certain IP addresses within a given range of IP addresses.
- [RuleIpToEvaluate](services/mail-manager/types/RuleIpToEvaluate.md): The IP address to evaluate for this condition.
- [RuleIsInAddressList](services/mail-manager/types/RuleIsInAddressList.md): The structure type for a boolean condition that provides the address lists and address list attribute to evaluate.
- [RuleNumberExpression](services/mail-manager/types/RuleNumberExpression.md): A number expression to match numeric conditions with integers from the incoming email.
- [RuleNumberToEvaluate](services/mail-manager/types/RuleNumberToEvaluate.md): The number to evaluate in a numeric condition expression.
- [RuleSet](services/mail-manager/types/RuleSet.md): A rule set contains a list of rules that are evaluated in order. Each rule is evaluated sequentially for each email.
- [RuleStringExpression](services/mail-manager/types/RuleStringExpression.md): A string expression is evaluated against strings or substrings of the email.
- [RuleStringToEvaluate](services/mail-manager/types/RuleStringToEvaluate.md): The string to evaluate in a string condition expression.
- [RuleVerdictExpression](services/mail-manager/types/RuleVerdictExpression.md): A verdict expression is evaluated against verdicts of the email.
- [RuleVerdictToEvaluate](services/mail-manager/types/RuleVerdictToEvaluate.md): The verdict to evaluate in a verdict condition expression.
- [S3Action](services/mail-manager/types/S3Action.md): Writes the MIME content of the email to an S3 bucket.
- [S3ExportDestinationConfiguration](services/mail-manager/types/S3ExportDestinationConfiguration.md): The configuration for exporting email data to an Amazon S3 bucket.
- [SavedAddress](services/mail-manager/types/SavedAddress.md): An address that is a member of an address list.
- [SearchStatus](services/mail-manager/types/SearchStatus.md): The current status of an archive search job.
- [SearchSummary](services/mail-manager/types/SearchSummary.md): Summary details of an archive search job.
- [SendAction](services/mail-manager/types/SendAction.md): Sends the email to the internet using the ses:SendRawEmail API.
- [SnsAction](services/mail-manager/types/SnsAction.md): The action to publish the email content to an Amazon SNS topic. When executed, this action will send the email as a...
- [Tag](services/mail-manager/types/Tag.md): A key-value pair (the value is optional), that you can define and assign to AWS resources.
- [TrafficPolicy](services/mail-manager/types/TrafficPolicy.md): The structure of a traffic policy resource which is a container for policy statements.

## Next Steps

For task-oriented guides on using these APIs, refer to the following resources:

- [Getting Started Guide](../setup/getting-started.md) — end-to-end setup walkthrough using the Mail Manager API
- [Mail Manager Developer Guide](https://docs.aws.amazon.com/ses/latest/dg/mail-manager.html) — official AWS documentation
- [Amazon SES API v2 Reference](https://docs.aws.amazon.com/ses/latest/APIReference-V2/Welcome.html) — full API reference for Amazon SES v2
- [SES Mail Manager API Reference](https://docs.aws.amazon.com/ses/latest/APIReference-V2/API_Operations_Amazon_SES_Mail_Manager.html) — full API reference for Mail Manager operations
