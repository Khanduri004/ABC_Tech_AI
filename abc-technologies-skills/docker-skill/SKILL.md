---
name: docker-skill
description: Writes and reviews Dockerfiles using multi-stage builds, minimal base images, and selective COPY to keep image size down. Use when the user asks to create, review, or optimize a Dockerfile or container image.
---

Run this workflow top to bottom.

1. In the builder stage, identify the binary's actual runtime requirements:
   - Compiled binaries: run `ldd <binary>` for shared library dependencies
   - Interpreted apps: locate the dependency directory (`node_modules`, `.venv`, `vendor`)
   - Either case: note any system assets read at runtime (e.g. `/etc/ssl/certs`)
2. Confirm the final stage's base image matches the C library the binary was built against (glibc vs musl) — a binary built on debian will not run on alpine without a rebuild.
3. For each item from step 1, confirm it's either pre-installed in the final base image or explicitly pulled in via `COPY --from=builder`.
