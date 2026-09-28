# SAP HANA Driver Plugin

This plugin adds SAP HANA SQL connectivity to TablePro through the native protocol implementation in [SAP/go-hdb](https://github.com/SAP/go-hdb). It does not require the SAP HDB Client, ODBC, SQLDBC, or a local SAP installation.

The MVP supports username/password authentication, schema and table browsing, column and index metadata, SQL execution, result sets, and the normal TablePro TLS modes. The optional TLS Server Name field is useful when a HANA Cloud endpoint is reached through a tunnel or proxy. Verify CA and Verify Identity require a CA file. Client certificates, LDAP, JWT, and SSO are intentionally not exposed.

The Go bridge is built as a universal arm64/x86_64 C archive by `scripts/build-hana.sh`. The archive owns the HANA wire connection and returns bounded JSON result envelopes to the Swift plugin.

The plugin has no structure editing or parameterized-query capability in this first release. Use a SQL statement in the query editor for writes and DDL.
