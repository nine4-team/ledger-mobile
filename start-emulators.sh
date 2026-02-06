#!/bin/bash
# Start Firebase emulators with persistence

# Ensure export directory exists
mkdir -p firebase-export

echo "Starting Firebase Emulators with persistence..."
echo "Data will be imported from and exported to ./firebase-export"

firebase emulators:start --import=./firebase-export --export-on-exit=./firebase-export
