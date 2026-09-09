# Contributing

Technical workflow for changing this action. See [README](README.md) for what it does and why.

## Tests

```bash
bats tests/unit/
```

CI (`test.yaml`) runs the same command on every push and pull request to `main`.

## Commits

[Conventional Commits](https://www.conventionalcommits.org/en/v1.0.0/) — see
[`.gitmessage`](.gitmessage) for the pattern and common types
(`feat`, `fix`, `chore`, `ci`, `docs`, `test`, ...).

## Pull requests

Fill in the [PR template](.github/pull_request_template.md); CI must pass before merge.
