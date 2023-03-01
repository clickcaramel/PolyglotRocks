#!/bin/bash

if [ -z "$TOKEN" ]; then
  echo "Error: TOKEN environment variable is not set"
  exit 1
fi

if [ -z "$PRODUCT_BUNDLE_IDENTIFIER" ]; then
  echo "Error: PRODUCT_BUNDLE_IDENTIFIER environment variable is not set"
  exit 1
fi

if [ -z "$PROJECT_NAME" ]; then
  echo "Error: PROJECT_NAME environment variable is not set"
  exit 1
fi

./bin/polyglot "$TOKEN" ./target
