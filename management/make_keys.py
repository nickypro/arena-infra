#!/usr/bin/env python3
"""
Generate OpenRouter API keys for arena machines.
- Checks if keys with the same name already exist
- Creates new keys with a $10 limit if they don't exist
- Updates existing keys to $10 limit if needed
- Saves results to CSV

Loads MACHINE_NAME_LIST and MACHINE_NAME_PREFIX from config.env
"""
import ast
import csv
import os
import requests
import sys

from mydotenv import load_env
load_env()

# Configuration
BASE_DIR = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))

# Load from config.env
PREFIX = os.environ.get("MACHINE_NAME_PREFIX", "arena7")
OUTPUT_CSV_PATH = os.path.join(BASE_DIR, f"keys/{PREFIX}_openrouter_keys.csv")

# Parse MACHINE_NAME_LIST from environment (stored as string representation of list)
machine_list_str = os.environ.get("MACHINE_NAME_LIST", "[]")
try:
    MACHINE_NAME_LIST = ast.literal_eval(machine_list_str)
except (ValueError, SyntaxError):
    MACHINE_NAME_LIST = []

if not MACHINE_NAME_LIST:
    print("Error: MACHINE_NAME_LIST not found or empty in config.env")
    sys.exit(1)

# OpenRouter API configuration
OPENROUTER_API_BASE = "https://openrouter.ai/api/v1"
LIMIT_USD = 10.0


def get_headers(provision_token: str) -> dict:
    return {
        "Authorization": f"Bearer {provision_token}",
        "Content-Type": "application/json",
    }


def list_existing_keys(provision_token: str) -> dict:
    """Fetch all existing keys and return a map of name -> key info."""
    headers = get_headers(provision_token)
    resp = requests.get(f"{OPENROUTER_API_BASE}/keys", headers=headers)
    resp.raise_for_status()
    data = resp.json()
    
    # Handle different response formats
    if isinstance(data, dict) and "data" in data:
        keys = data["data"]
    elif isinstance(data, list):
        keys = data
    else:
        keys = []
    
    return {k.get("name"): k for k in keys if k.get("name")}


def create_key(provision_token: str, name: str, limit: float) -> dict:
    """Create a new API key with the given name and limit."""
    headers = get_headers(provision_token)
    body = {"name": name, "limit": limit}
    resp = requests.post(f"{OPENROUTER_API_BASE}/keys", headers=headers, json=body)
    resp.raise_for_status()
    return resp.json()


def update_key_limit(provision_token: str, key_hash: str, limit: float) -> dict:
    """Update an existing key's limit."""
    headers = get_headers(provision_token)
    body = {"limit": limit}
    resp = requests.patch(f"{OPENROUTER_API_BASE}/keys/{key_hash}", headers=headers, json=body)
    resp.raise_for_status()
    return resp.json()


def main():
    # Get provisioning token from env var or command line argument
    provision_token = os.environ.get("OPENROUTER_PROVISION_KEY")
    
    if not provision_token and len(sys.argv) > 1:
        provision_token = sys.argv[1].strip()
    
    if not provision_token:
        print("Error: No provisioning token provided")
        print("Usage: python make_keys.py <OPENROUTER_PROVISION_KEY>")
        print("   or: OPENROUTER_PROVISION_KEY=<key> python make_keys.py")
        sys.exit(1)
    
    print(f"Fetching existing keys...")
    existing_keys = list_existing_keys(provision_token)
    print(f"Found {len(existing_keys)} existing keys")
    
    # Check for existing arena7 keys
    arena7_existing = {name: info for name, info in existing_keys.items() 
                       if name and name.startswith(f"{PREFIX}-")}
    print(f"Found {len(arena7_existing)} existing {PREFIX} keys")
    
    results = []
    skipped = []
    created = []
    updated = []
    
    for machine_name in MACHINE_NAME_LIST:
        key_name = f"{PREFIX}-{machine_name}"
        print(f"\nProcessing: {key_name}")
        
        if key_name in existing_keys:
            key_info = existing_keys[key_name]
            current_limit = key_info.get("limit")
            print(f"  Key already exists (limit: ${current_limit})")
            
            # Check if we need to update the limit
            if current_limit is None or current_limit < LIMIT_USD:
                print(f"  Updating limit to ${LIMIT_USD}...")
                try:
                    update_key_limit(provision_token, key_info["hash"], LIMIT_USD)
                    updated.append(key_name)
                    print(f"  Limit updated successfully")
                except Exception as e:
                    print(f"  Warning: Could not update limit: {e}")
            
            # We don't have the literal key for existing keys
            skipped.append(key_name)
            print(f"  NOTE: Cannot retrieve literal key for existing key (only shown at creation)")
        else:
            print(f"  Creating new key with ${LIMIT_USD} limit...")
            try:
                result = create_key(provision_token, key_name, LIMIT_USD)
                
                # The literal key might be in different fields depending on API version
                literal_key = (
                    result.get("key") or 
                    result.get("literal_key") or 
                    result.get("data", {}).get("key") or
                    result.get("data", {}).get("literal_key") or
                    result.get("api_key")
                )
                
                if literal_key:
                    results.append([key_name, literal_key])
                    created.append(key_name)
                    print(f"  Created successfully: {literal_key[:20]}...")
                else:
                    print(f"  Warning: Key created but literal key not in response: {result}")
                    skipped.append(key_name)
            except Exception as e:
                print(f"  Error creating key: {e}")
                skipped.append(key_name)
    
    # Save results to CSV
    if results:
        print(f"\n--- Saving {len(results)} new keys to {OUTPUT_CSV_PATH} ---")
        with open(OUTPUT_CSV_PATH, "w", newline="") as f:
            writer = csv.writer(f)
            for row in results:
                writer.writerow(row)
        print(f"Saved to: {OUTPUT_CSV_PATH}")
    else:
        print("\nNo new keys were created (all keys may already exist)")
    
    # Summary
    print("\n" + "=" * 50)
    print("SUMMARY")
    print("=" * 50)
    print(f"Total machines: {len(MACHINE_NAME_LIST)}")
    print(f"Keys created: {len(created)}")
    print(f"Keys updated (limit changed): {len(updated)}")
    print(f"Keys skipped (already existed): {len(skipped)}")
    
    if skipped:
        print(f"\nNote: {len(skipped)} keys already existed and their literal values")
        print("cannot be retrieved. If you need those keys, you'll need to")
        print("delete them and recreate, or find them in your records.")


if __name__ == "__main__":
    main()
