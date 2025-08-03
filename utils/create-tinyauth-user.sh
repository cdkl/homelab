#!/bin/bash

# TinyAuth User Creation Script
# Creates a user:bcrypt_hash pair for TinyAuth configuration

set -e

echo "========================================="
echo "  TinyAuth User Creation Tool"
echo "========================================="
echo ""

# Get username
echo -n "Enter username: "
read -r username

# Validate username (no spaces, colons, or special chars that could break the format)
if [[ ! "$username" =~ ^[a-zA-Z0-9_-]+$ ]]; then
    echo "Error: Username can only contain letters, numbers, underscores, and hyphens"
    exit 1
fi

echo ""

# Get password (hidden input)
echo -n "Enter password: "
read -s password
echo ""

echo -n "Confirm password: "
read -s password_confirm
echo ""

# Check passwords match
if [ "$password" != "$password_confirm" ]; then
    echo "Error: Passwords do not match"
    exit 1
fi

# Validate password length
if [ ${#password} -lt 8 ]; then
    echo "Error: Password must be at least 8 characters long"
    exit 1
fi

echo ""
echo "Generating bcrypt hash..."

# Generate bcrypt hash using htpasswd
hash=$(htpasswd -bnBC 10 "" "$password" | tr -d ':\n' | sed 's/^//')

if [ $? -ne 0 ]; then
    echo "Error: Failed to generate bcrypt hash. Make sure htpasswd is installed."
    exit 1
fi

echo ""
echo "========================================="
echo "  TinyAuth Configuration"
echo "========================================="
echo ""
echo "Add this to your TinyAuth USERS environment variable:"
echo ""
echo "${username}:${hash}"
echo ""
echo "For multiple users, separate with commas:"
echo "admin:existing_hash,${username}:${hash}"
echo ""
echo "========================================="
echo "  Security Notes"
echo "========================================="
echo "- Store this output securely"
echo "- The hash cannot be reversed to get the password"
echo "- Each time you run this script, a new hash is generated"
echo "- Clear your terminal history if needed: history -c"
echo ""
