#!/usr/bin/env bash

bash <(curl -s https://raw.githubusercontent.com/pgrange/bash_unit/master/install.sh)
tests=`find ./Tests/*.spec.sh`

for path in ${tests[@]}; do
    ./bash_unit $path
done
