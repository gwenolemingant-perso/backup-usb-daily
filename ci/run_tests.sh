#!/bin/bash
set -e

echo "▶ ShellCheck"
shellcheck bin/*.sh

echo "▶ BATS tests"
bats tests/
