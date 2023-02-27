#!/usr/bin/env bash

tests=`find ./tests/*.spec.sh`

for path in ${tests[@]}; do
    ./tests/bash_unit $path
done
