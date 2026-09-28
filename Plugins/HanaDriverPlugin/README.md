# SAP HANA Driver Plugin

This plugin connects TablePro to SAP HANA Cloud and SAP HANA 2.0 through [SAP/go-hdb](https://github.com/SAP/go-hdb), a native implementation of the HANA SQL wire protocol. It needs no SAP HANA Client, ODBC, SQLDBC or local SAP install.

The Go bridge in `Native/HanaBridge` is built by `scripts/build-hana.sh` as a universal arm64/x86_64 C archive. `CHana/CHana.h` is the whole interface: the bridge owns one HANA session per id and returns JSON, and the Swift side writes every message the user reads.

What the plugin does:

- User name and password login, with TLS in every TablePro mode. Preferred and Required encrypt without checking the certificate, Verify CA checks the chain only, and Verify Identity checks the chain and the host name, against the system roots unless a CA file is set. A client certificate and key can be added for mutual TLS. The TLS Server Name field overrides the name checked by Verify Identity when the certificate names another host.
- Schema browsing, columns with full types, primary keys, identity and generated columns, indexes, foreign keys, row counts, table DDL and view definitions.
- SQL execution with bound parameters, so grid edits, inserts and deletes work.
- Stop and the query timeout. Both send `ALTER SYSTEM CANCEL SESSION` for the connection's own session, which keeps the session open. When the server refuses the cancel, the bridge closes the session and TablePro reconnects.
- `EXPLAIN PLAN FOR` runs as one step that saves the plan, reads it and deletes it again. Reading plans needs the `OPTIMIZER ADMIN` privilege on recent HANA versions.

Not supported: structure editing, transactions, LDAP, JWT and SSO logins. Large object values longer than 64 MiB are cut short, and the result says so.
