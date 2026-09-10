---
description: Classify deliverables and transient files without destructive cleanup
argument-hint: "[paths or objective]"
---
Audit artifacts for ${@:-the active objective}. Start read-only; this is not blanket permission to delete, untrack or rewrite files.

- Inspect the actual VCS status and the accepted deliverables. Classify each relevant item as source, required deliverable, reproducible fixture, presentation, dependency/build product, transient run output, or private state/secret.
- Preserve reports, slides, videos and single-file presentations explicitly requested by the user. Required artifacts need content inspection and provenance; a filename, size or successful generator exit is insufficient.
- Keep generated logs, PID/socket files, caches, dependency trees and private state out of source control. Do not read secret contents to classify them; use paths and metadata, and redact output from approved scanners.
- For ignore/untrack requests, explain the distinction: ignoring affects future discovery, untracking changes the index, and deletion removes the working file. Never infer deletion authority. Preserve unknown/user-owned files.
- Identify artifact producers, revision/configuration, live-versus-replay provenance and consumers. Flag unsupported claims or missing evidence instead of hiding failed runs.
- Propose only the smallest scoped changes. Apply authorized changes through the writer lease/permit protocol and project tooling; never use a broad clean/reset or remove another process's files. Recheck tracking and required artifact integrity afterward.
- Return the classification, changes actually made, remaining obligations and absolute artifact locations. Keep audit scratch output outside source roots.
