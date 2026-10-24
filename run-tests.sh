#!/bin/zsh
# run-tests.sh — runs the whole suite (Python, zsh and Swift tests). No vendor app or module needed.
cd "${0:A:h}" && exec python3 -I -W error::ResourceWarning -m unittest discover -s tests -t tests -v "$@"
