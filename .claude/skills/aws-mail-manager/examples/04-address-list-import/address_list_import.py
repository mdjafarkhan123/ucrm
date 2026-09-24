# Copyright Amazon.com, Inc. or its affiliates. All Rights Reserved.
# SPDX-License-Identifier: Apache-2.0
"""
Address list management: create, add members, and bulk import via CSV.

Address lists are used in rule set conditions for allow/block list matching.

Bulk import workflow (IMPORTANT — two-step process):
  1. create_address_list_import_job() → returns PreSignedUrl
  2. PUT your CSV/JSON data to the PreSignedUrl
  3. start_address_list_import_job() → begins processing

Usage:
    python address_list_import.py

Prerequisites:
    pip install boto3 requests

Cleanup:
    Delete the address list when no longer needed. Remove it from any
    rule set conditions first, then:
      client.delete_address_list(AddressListId=address_list_id)
    Address lists do not incur ongoing charges, but keeping unused
    resources increases management overhead.
"""

import time

import boto3
import requests  # for uploading to the pre-signed URL

REGION = "us-east-1"

client = boto3.client("mailmanager", region_name=REGION)


def create_address_list(name):
    """Create a new address list."""
    response = client.create_address_list(AddressListName=name)
    list_id = response["AddressListId"]
    print(f"Address list created: {list_id} ({name})")
    return list_id


def add_single_address(list_id, address):
    """Add a single address to the list."""
    client.register_member_to_address_list(
        AddressListId=list_id,
        Address=address,
    )
    print(f"Added: {address}")


def remove_address(list_id, address):
    """Remove a single address from the list."""
    client.deregister_member_from_address_list(
        AddressListId=list_id,
        Address=address,
    )
    print(f"Removed: {address}")


def list_members(list_id, prefix_filter=None):
    """List all members of an address list, with optional prefix filter."""
    kwargs = {"AddressListId": list_id, "PageSize": 100}
    if prefix_filter:
        kwargs["Filter"] = {"AddressFilter": {"AddressPrefix": prefix_filter}}

    members = []
    while True:
        response = client.list_members_of_address_list(**kwargs)
        members.extend(response.get("Members", []))
        next_token = response.get("NextToken")
        if not next_token:
            break
        kwargs["NextToken"] = next_token

    print(f"Total members: {len(members)}")
    return members


def bulk_import_csv(list_id, addresses):
    """
    Bulk import addresses via CSV.

    IMPORTANT: This is a two-step process:
      1. Create the import job to get a pre-signed upload URL
      2. PUT the CSV data to the URL
      3. Start the job

    CSV format: one address per line, no header.
    """
    # Step 1: Create the import job
    response = client.create_address_list_import_job(
        AddressListId=list_id,
        Name="bulk-import",
        ImportDataFormat={"ImportDataType": "CSV"},
    )
    job_id = response["JobId"]
    presigned_url = response["PreSignedUrl"]
    print(f"Import job created: {job_id}")

    # Step 2: Upload CSV data to the pre-signed URL
    csv_content = "\n".join(addresses)
    upload_response = requests.put(
        presigned_url,
        data=csv_content.encode("utf-8"),
        headers={"Content-Type": "text/csv"},
    )
    upload_response.raise_for_status()
    print(f"Uploaded {len(addresses)} addresses to pre-signed URL")

    # Step 3: Start the import job
    client.start_address_list_import_job(JobId=job_id)
    print(f"Import job started: {job_id}")

    return job_id


def wait_for_import(job_id, timeout=120):
    """Poll until the import job completes."""
    deadline = time.time() + timeout
    while time.time() < deadline:
        response = client.get_address_list_import_job(JobId=job_id)
        status = response["Status"]
        if status == "COMPLETED":
            counts = response.get("ImportedItemsCount", 0)
            failed = response.get("FailedItemsCount", 0)
            print(f"Import complete: {counts} imported, {failed} failed")
            return response
        if status in ("FAILED", "STOPPED"):
            raise RuntimeError(f"Import job {status}: {response}")
        print(f"  Status: {status}...")
        time.sleep(5)
    raise TimeoutError("Import job did not complete within timeout")


def main():
    # Create a block list
    list_id = create_address_list("spam-deny-list")

    # Add individual addresses
    add_single_address(list_id, "spammer@bad-domain.example")
    add_single_address(list_id, "noreply@phishing.example")

    # Bulk import from a larger list
    bulk_addresses = [
        "bulk-spam1@example.net",
        "bulk-spam2@example.net",
        "bulk-spam3@example.net",
        "@entire-bad-domain.example",  # domain-level block
    ]
    job_id = bulk_import_csv(list_id, bulk_addresses)
    wait_for_import(job_id)

    # List all members
    members = list_members(list_id)
    for m in members:
        print(f"  {m['Address']}")

    print(f"\nAddress list {list_id} is ready to use in rule set conditions.")
    print("Reference it in a rule condition with AddressListId.")


if __name__ == "__main__":
    main()
