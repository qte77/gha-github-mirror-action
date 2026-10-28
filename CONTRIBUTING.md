# Contributing

Technical workflow for changing this action. See [README](README.md) for what it does and why.

## Tests

```bash
# Run tests
bats tests/unit/

# Lint shell scripts (shellcheck ships preinstalled on ubuntu-latest CI runners;
# nullglob so this still works if .github/scripts/ doesn't exist)
shopt -s nullglob; targets=(scripts/*.sh .github/scripts/*.sh); shellcheck "${targets[@]}"

# Lint workflow files (actionlint is not preinstalled; install locally first, e.g.
# via https://github.com/rhysd/actionlint/blob/main/docs/install.md)
actionlint
```

CI (`test.yaml`, `lint.yaml`) runs the same commands on every push and pull request to `main`.

## Commits

[Conventional Commits](https://www.conventionalcommits.org/en/v1.0.0/) — see
[`.gitmessage`](.gitmessage) for the pattern and common types
(`feat`, `fix`, `chore`, `ci`, `docs`, `test`, ...).

## Pull requests

Fill in the [PR template](.github/pull_request_template.md); CI must pass before merge.
