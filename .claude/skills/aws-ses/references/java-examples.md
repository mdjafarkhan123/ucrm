# Java Code Examples

Java examples for Amazon SES V2 API using AWS SDK for Java v2. Add `software.amazon.awssdk:sesv2` to your Maven or Gradle dependencies.

## Send Simple Email

```java
import software.amazon.awssdk.regions.Region;
import software.amazon.awssdk.services.sesv2.SesV2Client;
import software.amazon.awssdk.services.sesv2.model.*;

public class SendEmail {
    public static void main(String[] args) {
        String sender = "sender@example.com";
        String recipient = "success@simulator.amazonses.com";

        SesV2Client client = SesV2Client.builder().region(Region.US_EAST_1).build();

        try {
            SendEmailResponse response = client.sendEmail(SendEmailRequest.builder()
                .fromEmailAddress(sender)
                .destination(Destination.builder().toAddresses(recipient).build())
                .content(EmailContent.builder()
                    .simple(Message.builder()
                        .subject(Content.builder().data("Hello from Amazon SES").build())
                        .body(Body.builder()
                            .text(Content.builder().data("Sent using SES V2 API.").build())
                            .build())
                        .build())
                    .build())
                .configurationSetName("my-config-set")
                .build());
            System.out.println("Message sent: " + response.messageId());
        } catch (SesV2Exception e) {
            System.err.println("Send failed: " + e.awsErrorDetails().errorCode() + " - " + e.getMessage());
        } finally {
            client.close();
        }
    }
}
```

## Send Templated Email

```java
import software.amazon.awssdk.regions.Region;
import software.amazon.awssdk.services.sesv2.SesV2Client;
import software.amazon.awssdk.services.sesv2.model.*;

SesV2Client client = SesV2Client.builder().region(Region.US_EAST_1).build();

SendEmailResponse response = client.sendEmail(SendEmailRequest.builder()
    .fromEmailAddress("sender@example.com")
    .destination(Destination.builder().toAddresses("success@simulator.amazonses.com").build())
    .content(EmailContent.builder()
        .template(Template.builder()
            .templateName("welcome-email")
            .templateData("{\"name\":\"Alice\",\"company\":\"Acme Corp\"}")
            .build())
        .build())
    .configurationSetName("my-config-set")
    .build());
```

## Verify Domain Identity

```java
CreateEmailIdentityResponse response = client.createEmailIdentity(
    CreateEmailIdentityRequest.builder()
        .emailIdentity("example.com")
        .dkimSigningAttributes(DkimSigningAttributes.builder()
            .domainSigningAttributesOrigin("AWS_SES")
            .build())
        .build());

response.dkimAttributes().tokens().forEach(token ->
    System.out.println(token + "._domainkey.example.com -> " + token + ".dkim.amazonses.com"));
```

## Setup Configuration Set

```java
client.createConfigurationSet(CreateConfigurationSetRequest.builder()
    .configurationSetName("my-config-set")
    .sendingOptions(SendingOptions.builder().sendingEnabled(true).build())
    .reputationOptions(ReputationOptions.builder().reputationMetricsEnabled(true).build())
    .suppressionOptions(SuppressionOptions.builder().suppressedReasons("BOUNCE", "COMPLAINT").build())
    .build());
```

## Setup Tenant

```java
client.createTenant(CreateTenantRequest.builder().tenantName("my-tenant").build());

client.createTenantResourceAssociation(CreateTenantResourceAssociationRequest.builder()
    .tenantName("my-tenant")
    .resourceArn("arn:aws:ses:us-east-1:123456789012:identity/example.com")
    .build());

client.createTenantResourceAssociation(CreateTenantResourceAssociationRequest.builder()
    .tenantName("my-tenant")
    .resourceArn("arn:aws:ses:us-east-1:123456789012:configuration-set/my-config-set")
    .build());
```

## Validate Email Address

```java
GetEmailAddressInsightsResponse response = client.getEmailAddressInsights(
    GetEmailAddressInsightsRequest.builder()
        .emailAddress("user@example.com")
        .build());

MailboxValidation validation = response.mailboxValidation();
System.out.println("Valid: " + validation.isValid().confidenceVerdict());
```
