# Pixez rhttp native reuse

Source: https://github.com/Notsfsssf/pixez-flutter/tree/0750c38b0c8aaf200e992ec9b4303f5cd6abba87/plugins/rhttp/rhttp

Component license: MIT (LICENSE retained). This is the separately licensed rhttp component, not the GPL application UI or Dart OAuth code.

Reused: client.rs (ECH bootstrap, TLS construction, per-host cache, DNS configuration), error.rs, socket_addr.rs, HTTP value types and the vendored reqwest/h3/quinn dependency tree. All upstream third-party license files are retained.

Native-only changes: replace DartFnFuture with its boxed Rust Future equivalent, remove two Flutter binding attributes, expose RequestClient::new/client_for_url, and omit Flutter bindings/UI. The Swift-facing adapter continues to enforce fixed destinations, verified certificates, no redirects with credentials, no cookie persistence, bounded responses and request deadlines.

The application Cargo.lock is seeded from upstream's rust/Cargo.lock. In particular the ECH/TLS/HTTP graph retains rustls 0.23.40, aws-lc-rs 1.17.0, hyper 1.10.1 and h2 0.4.14 for reproducible compatibility checks. The optional local-login certificate generator uses rcgen's ring backend so that it does not upgrade rhttp's aws-lc-rs dependency.
