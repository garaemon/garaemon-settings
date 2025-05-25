#!/bin/bash

# Run the setup script
echo "Running setup.sh..."
bash ./setup.sh

# Verify git configurations
echo "Verifying git configurations..."
GIT_USER_NAME=$(git config --global user.name)
GIT_USER_EMAIL=$(git config --global user.email)

EXPECTED_USER_NAME="<secret_hidden> (bot)"
EXPECTED_USER_EMAIL="<secret_hidden>"

if [ "$GIT_USER_NAME" == "$EXPECTED_USER_NAME" ] && [ "$GIT_USER_EMAIL" == "$EXPECTED_USER_EMAIL" ]; then
    echo "Git configurations are set correctly."
    exit 0
else
    echo "Error: Git configurations are NOT set correctly."
    echo "Expected User Name: $EXPECTED_USER_NAME, Got: $GIT_USER_NAME"
    echo "Expected User Email: $EXPECTED_USER_EMAIL, Got: $GIT_USER_EMAIL"
    exit 1
fi