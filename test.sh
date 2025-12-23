#!/bin/bash
set -ex
c3c build lexv

files=()
files+=( $(find ../c3c/lib -name "*.c3") )
files+=( $(find ../c3c/test/ -name "*.c3" ! -name expected_directive.c3) )
c3c -E compile-only ${files[@]} | build/lexv
