#!/bin/sh
forge fmt --check &&
    export FOUNDRY_PROFILE=test &&
    forge test
