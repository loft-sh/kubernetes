#!/bin/bash

# Check if argument is provided
if [ $# -eq 0 ]; then
    echo "Usage: $0 <variable-name>" >&2
    exit 1
fi

# Get the variable name to search for
VAR_NAME="$1"

# Default file path (adjust if needed)
FILE_PATH="${2:-./versions.txt}"

# Check if file exists
if [ ! -f "$FILE_PATH" ]; then
    echo "Error: File $FILE_PATH not found" >&2
    exit 1
fi

# Parse the value after '=' for the given variable name
VALUE=$(grep "^${VAR_NAME}=" "$FILE_PATH" | cut -d'=' -f2 | tr -d '"')

# Check if value was found
if [ -z "$VALUE" ]; then
    echo "Error: Variable $VAR_NAME not found in $FILE_PATH" >&2
    exit 1
fi

# Output the value
echo "$VALUE"