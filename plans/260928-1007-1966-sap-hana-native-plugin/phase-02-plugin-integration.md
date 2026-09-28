---
title: "Phase 2: Plugin integration"
status: todo
---

# Phase 2: Plugin integration

## Overview

Connect the native bridge to a registry-only DriverPlugin with HANA schema navigation and safe TLS behavior.

## Requirements

- [x] Keep the Database field as initial schema, not a cross-tenant database selector.
- [x] Enable normal SSL modes and a TLS server-name override for tunneled cloud endpoints.
- [x] Do not expose unverified LDAP, X.509, JWT, SSO, or data-grid editing features.

## Implementation Steps

1. Add the plugin principal, driver, connection adapter, metadata, and C module map.
2. Add curated metadata and registry entry for the pre-install chooser.
3. Add project targets, CI bridge build steps, and contract tests.

## Todo

- [x] Add `Plugins/HanaDriverPlugin` and `Plugins/HanaDriverPluginTests`.
- [x] Modify `project.yml`, `.github/plugin-registry.json`, and macOS/plugin CI workflows.
- [x] Modify registry-default and plugin metadata tests.

## Success Criteria

The chooser can install SAP HANA and the plugin implements connect, schema/table browse, and SQL query through the existing plugin contracts.
