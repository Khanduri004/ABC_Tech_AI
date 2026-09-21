---
name: dockerfile-security-hygiene
description: Hardens Dockerfiles for security and build efficiency — non-root USER, .dockerignore, layer-caching order, pinned base images, and minimal attack surface. Use whenever the user writes, reviews, or hardens a Dockerfile, asks about container security, or asks why an image is large or slow to build.
---

Run this checklist top to bottom on any Dockerfile being written or reviewed.

## 1. Non-root user
- Never run the final container as root. Add a dedicated user/group in the final stage:
  ```dockerfile
  RUN groupadd -r appgroup && useradd -r -g appgroup appuser
  ```
- `chown` any directories the app writes to (logs, tmp, uploads) to that user.
- Place `USER appuser` **after** all root-only steps (package installs, chmod) and **before** `CMD`/`ENTRYPOINT`.
- If the base image already ships a non-root user (e.g. `node`, `tomcat` images sometimes do), prefer reusing it over creating a new one.

## 2. .dockerignore
- Every Dockerfile needs a matching `.dockerignore` in the same build context. At minimum exclude:
  `.git`, `target/`, `build/`, `node_modules/`, `*.log`, `.env*`, local IDE folders (`.idea/`, `.vscode/`), and any secrets/credentials files.
- Check this before optimizing anything else — a bloated build context slows every build and can leak secrets into layers even if they're never referenced in a `COPY`.

## 3. Layer-caching order
- Order instructions from least-frequently-changed to most-frequently-changed:
  1. Base image + OS packages
  2. Dependency manifests only (`pom.xml`, `package.json`, `requirements.txt`) + install command
  3. Application source code
  4. Build command
- Copying dependency manifests before source code means dependency layers stay cached across source-only changes. Verify this order explicitly — it's the single most common efficiency mistake.

## 4. Base image pinning
- Never use `:latest`. Pin to a specific version tag (and digest for production-critical images).
- Prefer official, actively-maintained images (`eclipse-temurin`, not an unofficial JDK image).

## 5. Minimal attack surface
- Multi-stage build: build tools (compilers, package managers, dev dependencies) stay in the builder stage and never reach the final image.
- Avoid `ADD` unless you specifically need its remote-URL or tar-auto-extract behavior — use `COPY` otherwise, since `ADD`'s extra behavior is a common source of surprises.
- Don't bake secrets, tokens, or `.env` files into any layer, even ones later removed — earlier layers persist in image history. Use build secrets (`--mount=type=secret`) or runtime env injection instead.

## 6. Vulnerability scanning (mention, don't assume)
- Suggest running a scanner (`trivy image <name>` or `grype <name>`) on the final image before pushing, especially before first deploy or when the base image is updated.
