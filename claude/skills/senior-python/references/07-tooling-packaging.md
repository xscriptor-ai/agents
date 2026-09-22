# Tooling and Packaging

uv/ruff/hatch/pdm workflows, a complete pyproject, lockfile policy, src layout, versioning, building and publishing to PyPI, monorepos, pre-commit, and CI.

## Toolchain Map

| Need | Primary | Alternatives | Notes |
|---|---|---|---|
| Env + lock + run | uv | pdm, poetry | uv is fastest and handles Python installs too |
| Lint + format | ruff | flake8 + black + isort | One tool, one config section |
| Build backend | hatchling | setuptools, flit, pdm-backend | Hatchling is simple and VCS-version friendly |
| Release versioning | hatch-vcs | setuptools-scm | Single source: git tags |
| Task runner | uv scripts / just | make, taskipy | Keep CI and local commands identical |
| Publish | uv publish | twine, flit publish | Use PyPI trusted publishing |

Standardize on one stack and document it in the README; mixed pip/poetry/pdm projects are
a chronic source of environment drift.

## uv Workflows

```bash
uv init --lib mypkg          # or --app for services
uv add httpx                 # runtime dependency
uv add --group dev pytest    # PEP 735 dependency group
uv sync --frozen             # CI/prod: exact lockfile
uv run ruff check .          # run in the project env
uv run pytest -q
uv python install 3.13       # managed interpreter
uv lock --upgrade            # refresh resolution (PR-reviewed)
uv export --format requirements-txt --no-dev > requirements.txt
uv tool install ruff          # global CLI tools, isolated
```

- `uv sync --frozen` fails if `uv.lock` disagrees with `pyproject.toml`; always use it in CI
  and images.
- `uv run` guarantees the project environment; no manual `source .venv/bin/activate` in
  scripts.
- `uv export` exists for consumers that still need `requirements.txt`; the lockfile remains
  the source of truth.
- Use `[tool.uv] default-groups` to control what `uv sync` installs by default.

## Complete pyproject.toml

```toml
[build-system]
requires = ["hatchling>=1.27", "hatch-vcs>=0.4"]
build-backend = "hatchling.build"

[project]
name = "my-service"
description = "Example service"
readme = "README.md"
license = "MIT"
requires-python = ">=3.12"
dynamic = ["version"]
dependencies = [
    "fastapi>=0.115",
    "pydantic>=2.9",
    "sqlalchemy[asyncio]>=2.0.35",
]

[project.optional-dependencies]
postgres = ["asyncpg>=0.30"]

[dependency-groups]
dev = ["pytest>=8", "pytest-asyncio", "ruff>=0.9", "mypy>=1.13"]

[project.scripts]
my-service = "my_service.__main__:main"

[tool.uv]
default-groups = ["dev"]

[tool.hatch.version]
source = "vcs"

[tool.hatch.build.targets.wheel]
packages = ["src/my_service"]

[tool.ruff]
line-length = 100
target-version = "py312"

[tool.ruff.lint]
select = ["E", "F", "W", "I", "N", "UP", "B", "C4", "SIM", "RUF", "S", "ASYNC", "PT", "TID", "LOG", "G"]

[tool.ruff.lint.per-file-ignores]
"tests/**" = ["S101"]

[tool.ruff.format]
quote-style = "double"
```

- `license = "MIT"` uses SPDX expressions (PEP 639); older tooling requires the legacy
  `license = { text = "MIT" }` form — verify your build backend.
- Build-system requirements are pinned with floors; the build must be reproducible from the
  sdist alone.
- The wheel target must point at `src/`; without it hatchling guesses and can ship an empty
  wheel.
- Keep tool config in `pyproject.toml`; avoid scattering `setup.cfg`, `.flake8`, and
  `mypy.ini`.
- If you cannot use VCS versioning (no tags in build context), set `version` explicitly and
  keep it in exactly one place.

## Lockfile and Dependency Policy

- **Applications** commit `uv.lock`; deploys install `--frozen`. Never resolve at deploy
  time.
- **Libraries** commit the lockfile for development/CI but must not pin consumers; test
  against your declared lower bounds (a periodic `uv lock --upgrade` plus a minimum-versions
  job).
- Do not commit `uv.lock` inside published wheels/sdists; it is not part of the
  distribution.
- Dependency ranges: floors (`>=`) for libraries; for services, the lockfile provides the
  exactness (`==` not needed in metadata).
- Avoid unpinned VCS/Git dependencies in released packages; they break rebuilds. Pin a
  commit and plan to replace with a release.
- AUDIT: run a dependency vulnerability scan in CI ([security](./09-security-observability.md)).
- PEP 735 `[dependency-groups]` is the standard place for dev/lint/test tooling;
  `optional-dependencies` is for user-facing extras (`pip install "pkg[postgres]"`).

## src Layout

```text
project/
  src/my_service/
    __init__.py
    __main__.py
  tests/
  pyproject.toml
  uv.lock
```

- `src/` prevents tests and scripts from importing the working directory by accident; you
  always test the installed package.
- Flat layout is acceptable for applications, but src is the default for anything with a
  public API.
- Mark the package with `__init__.py` (regular) or explicitly name packages in the build
  backend (namespace packages).
- Keep a single top-level import name matching the distribution, or document the mapping.

## Versioning

- One source of truth: git tags (`v1.2.3`) via hatch-vcs/setuptools-scm, or one `version`
  field in `pyproject.toml`.
- Read it at runtime with `importlib.metadata.version("my-service")`; do not duplicate a
  `__version__` string by hand.
- Follow semantic versioning; document deprecation policy (deprecate for at least one minor,
  remove at a major — see [language core](./01-language-core.md)).
- Pre-releases (`1.0.0rc1`) must be installable and tested; do not tag a release candidate
  that CI has not built.
- Tag signing and protected branches are part of release integrity.

## Building, Wheels, and sdists

```bash
uv build                     # sdist + wheel into dist/
uv build --wheel             # wheel only
unzip -l dist/my_service-0.1.0-py3-none-any.whl   # inspect contents
```

- Always ship both sdist and wheel for pure Python; ship wheels for every supported
  platform when there are binary extensions.
- Pure Python wheels are `py3-none-any`. Binary wheels must target the ABI; consider the
  stable ABI (`abi3`) so one wheel spans Python minor versions.
- Build manylinux/musllinux wheels with cibuildwheel in CI; never publish a Linux wheel built
  on a developer machine.
- Check the wheel contains `py.typed` if you ship type information, and that no tests,
  caches, or secrets are inside.
- `python -m build` remains a valid fallback; `twine check dist/*` validates metadata and
  README rendering.

## Publishing to PyPI

- Use PyPI **trusted publishing** (OIDC from GitHub Actions/other CI) rather than stored API
  tokens. Tokens, if unavoidable, are project-scoped and short-lived.
- Flow: build in CI on a version tag -> publish to TestPyPI -> install-test -> publish to
  PyPI.
- `uv publish` or the official `pypa/gh-action-pypi-publish` action; neither needs a token
  with trusted publishing.
- Never overwrite a release: yank instead, and release a patch. PyPI files are immutable.
- Verify post-publish: `pip install pkg==x.y.z` in a clean container and import it.
- Do not publish from a dirty working tree; the build must come from the tagged commit.

## Monorepos

```toml
# root pyproject.toml
[tool.uv.workspace]
members = ["packages/*"]
```

- uv workspaces share one virtual environment and one lockfile; members declare internal
  deps as `{ workspace = true }`.
- CI installs everything with `uv sync --all-packages` (or syncs only the affected member
  with `--package`).
- Keep per-package `pyproject.toml` metadata (name, version, deps); the workspace root holds
  only workspace and shared tool config.
- Independent versioning with VCS tags needs tag prefixes (`pkg-a-v1.2.3`) and per-package
  release automation; otherwise version the repo as one train.
- Enforce import boundaries with a linter rule (for example `TID`/`import-linter`) so
  packages do not reach into each other's internals.

## pre-commit

```yaml
# revs below are illustrative; pin the current releases and let autoupdate bump them
repos:
  - repo: https://github.com/astral-sh/ruff-pre-commit
    rev: v0.9.0
    hooks:
      - id: ruff
        args: [--fix]
      - id: ruff-format
  - repo: https://github.com/pre-commit/pre-commit-hooks
    rev: v6.0.0
    hooks:
      - id: check-merge-conflict
      - id: check-yaml
      - id: end-of-file-fixer
```

- Pin every `rev`; `pre-commit autoupdate` is a reviewable change.
- Keep hooks fast; move heavy checks (tests, type checking) to CI.
- CI remains the source of truth; developers can bypass hooks with `--no-verify` and CI must
  still fail.
- `pre-commit run --all-files` for the first adoption and for CI parity.

## CI Example

```yaml
name: ci
on: [push, pull_request]

jobs:
  test:
    runs-on: ubuntu-latest
    strategy:
      matrix:
        python-version: ["3.12", "3.13", "3.14"]
    steps:
      - uses: actions/checkout@v4
      - uses: astral-sh/setup-uv@v5
        with:
          python-version: ${{ matrix.python-version }}
          enable-cache: true
      - run: uv sync --frozen
      - run: uv run ruff check .
      - run: uv run ruff format --check .
      - run: uv run mypy src
      - run: uv run pytest -q
```

- Action versions above are illustrative; use current pinned majors.
- Cache uv's download cache, not the virtualenv, for cross-version reliability.
- Separate fast gates (lint, types, unit) from integration and build jobs.
- Add a build job that runs `uv build` and installs the wheel in a clean environment.
- Publish only on tags, after tests pass, with `id-token: write` for trusted publishing.

## Anti-Patterns

- `requirements.txt` as the only source of truth with no resolver lock.
- Committing `.venv`, `dist/`, or `__pycache__`.
- `setup.py` logic and `setup.cfg` split across files in new projects.
- Version duplicated in `pyproject.toml`, `__init__.py`, and docs.
- Unpinned `git+https://` dependencies in published packages.
- `pip install -e .` with a build backend that does not support editable installs.
- Publishing from a laptop or without provenance/attestations.
- Editing a released version in place (yank and bump instead).

## Checklist

- [ ] `pyproject.toml` is the single config source; `uv.lock` committed.
- [ ] `requires-python` matches CI matrix and code features.
- [ ] src layout with an explicit wheel packages target; `py.typed` shipped if typed.
- [ ] Version derived from VCS or one field; runtime reads `importlib.metadata`.
- [ ] Build produces inspectable sdist + wheel; binary wheels built in CI.
- [ ] Publishing uses trusted publishing and TestPyPI first.
- [ ] pre-commit pinned; CI runs lint, format check, types, tests, build.
- [ ] Workspace/monorepo boundaries enforced and release tagging documented.
