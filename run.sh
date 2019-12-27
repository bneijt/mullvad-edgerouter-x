#!/bin/bash
set -e
stack build
stack exec mullvad-edgerouter-x-exe mullvad-example.conf | tee mullvad-example_config.txt
echo "Done running"
