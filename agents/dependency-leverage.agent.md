---
name: dependency-leverage
description: "Refactor source modules to delegate directly to installed package.json dependencies."
---

1. Audit the requested scope against the **Delegate to dependencies** rule in `engineering-guidelines`.
2. Replace duplicated or hand-rolled code with calls to installed `package.json` libraries and delete superseded local helpers.
