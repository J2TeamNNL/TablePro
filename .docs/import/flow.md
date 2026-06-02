# import — flow

## DBeaver import (sau #1366)

```mermaid
flowchart TD
  A[User chọn Import from DBeaver] --> B[Check includePasswords]
  B --> C[loadDataSources from data-sources.json]
  C --> D[loadCredentials from credentials-config.json<br/>LUÔN load, không gate]
  D --> E[for each connection in sources]
  E --> F{credentials có #connection.user?}
  F -->|yes| G[username = creds.user]
  F -->|no| H{config có user?}
  H -->|yes| I[username = config.user fallback]
  H -->|no| J[username = empty string]
  G --> K{includePasswords?}
  I --> K
  J --> K
  K -->|yes| L[password = creds.password OR empty]
  K -->|no| M[password = empty]
  L --> N[Create connection record]
  M --> N
```

## DBeaver storage layout

```mermaid
flowchart LR
  subgraph DBeaver 6.1.3+
    A1[data-sources.json] -->|host, port, ssh, ssl| C1[Connection metadata]
    A2[credentials-config.json] -->|username, password| C2[Auth secrets]
    A2 -.encrypted on disk.-> A2
  end
  subgraph DBeaver < 6.1.3 hoặc admin config
    B1[data-sources.json] -->|host, port, user| D1[Combined]
  end
  C1 --> Z[TablePro import]
  C2 --> Z
  D1 --> Z
```

## Metadata vs Secret split

```mermaid
flowchart LR
  A[Import file/config] --> B{Field type?}
  B -->|metadata: host, port, user, ssh-host| C[LUÔN load]
  B -->|secret: password, private-key| D[Gated by includePasswords]
  C --> E[Connection record]
  D --> E
```
