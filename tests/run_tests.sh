#!/usr/bin/env bash

tests=`find ./tests/*.spec.sh`

for path in ${tests[@]}; do
    API_URL=https://api.dev.polyglot.rocks ./tests/bash_unit $path
done
