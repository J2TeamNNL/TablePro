---
title: "Phase 1: Native bridge"
status: in-progress
---

# Phase 1: Native bridge

## Overview

Create the static Go bridge around SAP/go-hdb and keep its exported C ABI independent from TableProPluginKit.

## Requirements

- [x] Pin the Go module and all transitive checksums.
- [x] Export lifecycle, query, catalog, TLS, and result ownership functions with input bounds.
- [x] Build arm64 and x86_64 archives with one reproducible script.

## Implementation Steps

1. Define the C ABI and Go handle/result/error ownership.
2. Implement basic authentication, TLS, query result conversion, and catalog queries.
3. Build universal archives and fail if required symbols are absent.

## Todo

- [x] Add `Native/HanaBridge` source, module metadata, and dependency licenses.
- [x] Add `scripts/build-hana.sh`.

## Success Criteria

The bridge has no HDB Client, ODBC, or SQLDBC dependency and its archive exports the functions the Swift plugin consumes.
