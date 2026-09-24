# Copyright Amazon.com, Inc. or its affiliates. All Rights Reserved.
# SPDX-License-Identifier: Apache-2.0
"""
Archive management: create, search, export, and retrieve messages.

Archive search and export are async operations:
  1. Start the job
  2. Poll until complete
  3. Fetch results

Usage:
    python archive_search.py

Prerequisites:
    An existing Mail Manager archive, or run create_archive() first.

Cost notice:
    Archives incur storage charges based on email volume and retention
    period. Delete archives when no longer needed:
      client.delete_archive(ArchiveId=archive_id)
    Archive deletion is async (enters PENDING_DELETION state).
"""

import time
from datetime import datetime, timedelta, timezone

import boto3

REGION = "us-east-1"
ARCHIVE_ID = "a-xxxxxxxxxx"  # Replace with your archive ID

client = boto3.client("mailmanager", region_name=REGION)


def create_archive(name, retention="ONE_YEAR"):
    """
    Create an archive.

    Cost note: Archives incur storage charges based on email volume and
    retention period. Delete when no longer needed with delete_archive().

    Retention options:
    THREE_MONTHS, SIX_MONTHS, NINE_MONTHS, ONE_YEAR, EIGHTEEN_MONTHS,
    TWO_YEARS, THIRTY_MONTHS, THREE_YEARS, FOUR_YEARS, FIVE_YEARS,
    SIX_YEARS, SEVEN_YEARS, EIGHT_YEARS, NINE_YEARS, TEN_YEARS, PERMANENT
    """
    response = client.create_archive(
        ArchiveName=name,
        Retention={"RetentionPeriod": retention},
    )
    archive_id = response["ArchiveId"]
    archive = client.get_archive(ArchiveId=archive_id)
    print(f"Archive created: {archive_id}")
    print(f"Archive ARN: {archive['ArchiveArn']} (for IAM policies)")
    print(f"Use archive_id '{archive_id}' in TargetArchive rule actions (not the ARN)")
    return archive_id


def search_archive(archive_id, from_address_contains=None, days_back=7):
    """
    Search an archive. Returns a list of matching message metadata rows.

    Archive search is async:
      start_archive_search → poll get_archive_search → get_archive_search_results
    """
    now = datetime.now(timezone.utc)
    from_ts = int((now - timedelta(days=days_back)).timestamp())
    to_ts = int(now.timestamp())

    # Build optional filters
    filters = {}
    if from_address_contains:
        filters["Include"] = [
            {
                "StringExpression": {
                    "Evaluate": {"Attribute": "FROM"},
                    # Archive search only supports CONTAINS operator
                    "Operator": "CONTAINS",
                    "Values": [from_address_contains],
                }
            }
        ]

    kwargs = {
        "ArchiveId": archive_id,
        "FromTimestamp": from_ts,
        "ToTimestamp": to_ts,
        "MaxResults": 100,
    }
    if filters:
        kwargs["Filters"] = filters

    # 1. Start the search job
    response = client.start_archive_search(**kwargs)
    search_id = response["SearchId"]
    print(f"Search started: {search_id}")

    # 2. Poll until complete
    while True:
        status = client.get_archive_search(SearchId=search_id)
        completion = status["Status"].get("CompletionTimestamp")
        if completion:
            print(f"Search complete at {completion}")
            break
        print("  Searching...")
        time.sleep(2)

    # 3. Fetch results
    results = client.get_archive_search_results(SearchId=search_id)
    rows = results.get("Rows", [])
    print(f"Found {len(rows)} messages")
    return rows


def get_message_content(archived_message_id):
    """
    Retrieve the text content of an archived message (no attachments).
    Returns headers and body text.
    """
    response = client.get_archive_message_content(
        ArchivedMessageId=archived_message_id
    )
    return response["Body"]


def get_message_download_url(archived_message_id):
    """
    Get a pre-signed URL to download the full raw message (EML format).
    URL is time-limited.
    """
    response = client.get_archive_message(ArchivedMessageId=archived_message_id)
    return response["MessageDownloadLink"]


def export_to_s3(archive_id, s3_bucket, s3_prefix="export/", days_back=30):
    """
    Export archived messages to S3. Also async — poll until complete.
    """
    now = datetime.now(timezone.utc)
    from_ts = int((now - timedelta(days=days_back)).timestamp())
    to_ts = int(now.timestamp())

    response = client.start_archive_export(
        ArchiveId=archive_id,
        FromTimestamp=from_ts,
        ToTimestamp=to_ts,
        ExportDestinationConfiguration={
            "S3": {"S3Location": f"s3://{s3_bucket}/{s3_prefix}"}
        },
        IncludeMetadata=True,
    )
    export_id = response["ExportId"]
    print(f"Export started: {export_id}")

    # Poll until complete
    while True:
        status = client.get_archive_export(ExportId=export_id)
        completion = status["Status"].get("CompletionTimestamp")
        if completion:
            print(f"Export complete: s3://{s3_bucket}/{s3_prefix}")
            break
        print("  Exporting...")
        time.sleep(5)

    return export_id


def main():
    # Search for messages from a specific domain in the last 7 days
    rows = search_archive(
        archive_id=ARCHIVE_ID,
        from_address_contains="@example.com",
        days_back=7,
    )

    for row in rows[:5]:  # show first 5
        msg_id = row["ArchivedMessageId"]
        envelope = row.get("Envelope", {})
        print(f"\nMessage: {msg_id}")
        print(f"  From:    {envelope.get('From', 'unknown')}")
        print(f"  To:      {envelope.get('To', 'unknown')}")
        print(f"  Subject: {row.get('Subject', '(no subject)')}")

        # Get download URL for the full EML
        url = get_message_download_url(msg_id)
        print(f"  Download: {url[:80]}...")

    # Cleanup reminder: delete the archive when no longer needed.
    # WARNING: Deleting an archive permanently removes all stored emails.
    # Export any needed data first with export_to_s3().
    #   client.delete_archive(ArchiveId=ARCHIVE_ID)


if __name__ == "__main__":
    main()
