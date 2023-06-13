# GitLab -> Discord notifier

This repo contains two bash scripts for notifying a Discord server of GitLab repository updates, like how the GitHub webhook does it.

\* Created for the ETH Zürich Game Programming Lab project. This is released without any support or update plans, so if you are looking for something like this, please take it as inspiration as I can't guarantee full functionality in your environments.

## Scripts

1. The first script sends a notification message to the given webhook URL when new commit hashes are found for the `master` branch on a repository. These are determined by fetching the last 100 commits on the `master` branch, comparing it with the cache from the last run, and finding hashes that are new.
2. The second script sends a notification message to the given webhook URL when a new branch is created on the repository.

These were created for a workflow where project team members create feature/fix branches on the main repo, which get merged into `master` once approved.

## Requirements

- `jq`
- `curl`
- `touch`

Tested only on an Ubuntu 22.04 server.

## Setup

Set up crontab entries to call the two scripts as frequent as you like. Every minute works best for the "instant feedback" feeling of committing and getting a notification.

```
* * * * * cd ~/notifier && ./run_master_commit_notif.sh
* * * * * cd ~/notifier && ./run_branch_creation_notif.sh
```
