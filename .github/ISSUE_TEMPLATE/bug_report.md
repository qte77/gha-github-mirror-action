---
name: Bug report
about: Report a mirror failure or unexpected behavior
title: ''
labels: bug
assignees: ''
---

## Description

<!-- A clear and concise description of the bug -->

## Mirror Targets

<!-- Which targets are affected? -->

- [ ] GitLab
- [ ] Codeberg
- [ ] Both

## Steps to Reproduce

1. Run `...`
2. ...

## Expected Behavior

<!-- What you expected to happen -->

## Actual Behavior

<!-- What actually happened. Include error traces if applicable -->

## PAT Configuration

<!-- Which PATs are set in your repository secrets? -->

- [ ] `gitlab_pat`
- [ ] `codeberg_pat`

## Action Mode

- [ ] Per-repo (`uses: qte77/gha-github-mirror-action@v0`)
- [ ] Central hub (`mirror-all.yaml`)

## Error Logs

<!-- Paste relevant mirror.sh output below. Redact any PAT values. -->

```
```

## Environment

- OS/Runner:
- Action version (`@v0`, commit SHA, etc.):

## Additional Context

<!-- Screenshots, related issues, repos.yaml config (redact secrets), etc. -->
