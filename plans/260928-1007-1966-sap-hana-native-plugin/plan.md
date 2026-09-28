---
title: "SAP HANA native driver"
description: "Registry HANA driver without SAP HDB Client"
status: in-progress
priority: P1
effort: "3 phases"
tags: ["1966", "plugin", "sap-hana"]
created: 2026-09-28
---

# SAP HANA native driver

## Overview

Add a downloadable SAP HANA plugin that uses SAP/go-hdb through a universal C archive. It supports database username/password, TLS, schema browsing, and SQL query execution without requiring SAP HDB Client.

## Goals

| # | Goal | Priority |
|---|------|----------|
| 1 | Package the native Go transport behind a bounded C ABI | P1 |
| 2 | Expose HANA through the TablePro plugin and registry | P1 |
| 3 | Verify the contracts and publish user documentation | P1 |

## Phases

| # | Phase | Status |
|---|-------|--------|
| 1 | [Native bridge](./phase-01-start.md) | In progress |
| 2 | [Plugin integration](./phase-02-plugin-integration.md) | Pending |
| 3 | [Verification and docs](./phase-03-verification-and-docs.md) | Pending |

## Success Criteria

- [ ] Plugin loads as a signed, universal `.tableplugin` with no HDB Client dependency.
- [ ] Username/password connections and TLS configuration reach a HANA endpoint.
- [ ] Schema, table, column, index, query, and result paths are covered by focused tests.
- [ ] Registry metadata, CI build path, documentation, and supported-driver counts agree.

<!-- slug: 1966-sap-hana-native-plugin -->
