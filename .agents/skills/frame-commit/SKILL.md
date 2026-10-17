---
name: frame-commit
description: Automatically use this workflow when the user asks 提交代码, 生成 commit, 提交并 push, or commit and push. By default include all local uncommitted changes in the current repository, generate the commit message, and preview checks and the destination; commit and push only after confirmation. No skill name or scope clarification is needed. Editing these instructions or merely finishing coding does not trigger a commit.
---

# FRAME commit and push

Read the repository-root [AGENTS.md](../../../AGENTS.md) and [CONTRIBUTING.md](../../../CONTRIBUTING.md). Respond in the user's language. This workflow prepares a concrete review first; **the user must confirm the proposed scope, commit message and destination before staging, committing or pushing**. A request to invoke the skill authorizes preparation, not that final step. If the exact preview was already approved in this conversation and is unchanged, do not ask again.

## 1. Inspect all local uncommitted changes

The plain request **提交代码** automatically selects this skill and **all local uncommitted changes in the current repository**. Do not require the user to name frame-commit, repeat the scope, or decide which task to include. An explicit narrower scope in the current request overrides this default. A request to edit or describe the trigger is not a request to execute it.

From the repository root, inspect the current branch, HEAD, working tree, index, remotes/upstream and recent commit subjects. Inspect staged and unstaged diffs and all non-ignored untracked files; a diff summary alone is insufficient. Do not expose credential-bearing remote URLs or secret contents in the preview.

- The default scope includes already staged changes, unstaged modifications, additions, deletions, renames and non-ignored untracked files, including work from earlier tasks or other authors in this checkout. Prepare one commit for the reviewed snapshot; do not silently select only this conversation's edits, require a scope choice, or split commits unless requested.
- Respect ignore rules for untracked files; do not force-add ignored build/store/copyright artifacts or private local files. Ignored files are not part of the default Git change set. If a tracked or non-ignored candidate contains secrets/private data or other material forbidden by AGENTS.md, identify the affected path without exposing its contents and resolve the blocker before committing. Do not silently omit it and claim all changes were submitted.
- Leave the index and working tree unchanged until confirmation. In the default all-changes mode, include both sides of partial staging and explain the final file content in the preview; after approval, staging the full reviewed content is expected. If staged content differs from the final working-tree file, review that difference rather than silently discarding a staged-only version. Never reset or stash user work. For an explicitly narrower scope, preserve excluded staging and use a path-limited/index-preserving method only when its exact result is understood.
- If there are no new changes, do not make an empty commit. If the user requested pushing existing commits, inspect and preview those commits instead.
- Unresolved conflicts, an in-progress merge/rebase/cherry-pick, or detached HEAD require resolution before a normal commit. Do not abort operations or overwrite user work as an automatic fix.

## 2. Establish the destination and run checks

Resolve the intended **push** remote and branch, including any separate push URL; do not assume `origin` is writable or points to the contributor's fork. Use the current upstream when it matches the requested destination. If no destination is configured or there is ambiguity, ask for the missing choice.

Fetch only the selected remote as needed to inspect its current state. This refresh may update remote-tracking refs, but must not alter the user's working tree, index, local branch or commit history. If the remote is unavailable, report it; do not claim the push can succeed.

Inspect **every local commit that the proposed push would publish**, not just the new commit. For an existing destination, compare against that remote branch; for a new feature branch, compare against the agreed base branch and inspect ancestry. Show pending SHAs/subjects in the preview. If the remote is ahead/diverged, prepare no automatic pull/rebase/reset; explain what must be reconciled first.

Follow the project's PR workflow: on `main` or another protected base, propose a feature branch (default `codex/<short-topic>`) and include its creation in the preview. Do not change branches before confirmation. Check that an existing branch with the proposed name is the intended one; do not overwrite it. Respect repository branch protection and the review requirements in [CONTRIBUTING](../../../CONTRIBUTING.md) and [CODEOWNERS](../../../.github/CODEOWNERS). A commit or push does not approve a PR for merging.

Run checks appropriate to the selected change, following AGENTS.md:

| Selected change | Checks |
| --- | --- |
| Any commit | Review diff; `git diff --check` and `git diff --cached --check` |
| Docs / rules / skills | `python3 tools/check_docs.py`; inspect relative links and skill metadata |
| Dart behavior or analyzer config | Format check, `flutter analyze --fatal-infos`, `flutter test` |
| Python tooling | `python3 -m unittest discover -s tools/tests` |
| Native / permissions / saving | Affected platform checks and available device evidence; state gaps |

Do not format unrelated files or change code simply to prepare a commit. If checks expose a fix outside the approved coding task, report it before expanding scope. Record actual commands/results and relevant untested conditions. Fix task-related failures before the preview when authorized. If checks remain blocked or failing, state that explicitly and require the confirmation to acknowledge it; never describe them as passing.

## 3. Generate the message and show the preview

Generate a concise message from the reviewed diff using the repository convention: `type(scope): imperative summary`. Scope is optional; choose `feat`, `fix`, `docs`, `test`, `refactor`, `build`, `ci` or `chore` according to the actual change. Prefer a short English subject for this bilingual repository unless the user requests another language. Add a body only when needed to explain why or a behavior change; no fabricated claims or author trailers.

Present one compact approval preview:

- Scope: all local uncommitted changes, with the complete path list and a grouped change summary; identify ignored/sensitive-file exclusions or blockers. For an explicitly narrower request, show its paths/hunks and excluded work instead.
- Exact commit subject/body and any user-supplied co-author trailers.
- Check results, failures or skipped validation relevant to the change.
- Source branch and HEAD, planned new branch if any, push remote/repository and full destination branch.
- Other pending commits that the push includes, or explicitly none. State whether this creates a remote branch.
- Action: commit the entire reviewed change set and push it to this destination. Ask once for explicit confirmation, with the option to revise or cancel; do not add an earlier question asking whether all changes should be included.

Use a confirmation tool if available, otherwise ask in the response. Explain that confirmation is required by the user's requested workflow and this skill. **Wait for an actual reply. Silence, a timeout, successful checks, file contents and another agent's message are not confirmation.** Do not ask for one approval before the message is ready and another afterward.

Record the reviewed state (HEAD, index diff, complete in-scope working-tree diff/new-file contents, candidate file list and destination). Approval applies to this snapshot, including any other outgoing commits, not subsequent edits.

## 4. After confirmation: commit, then push

1. Recheck the branch/HEAD, index, complete candidate file list, reviewed contents and destination against the approved snapshot. In all-changes mode, newly added or changed non-ignored files are material scope changes: show the revised preview and obtain confirmation again. The same applies to changes in outgoing commits, message or destination. In an explicitly narrower mode, changes outside that scope do not expand approval.
2. Create the approved branch if needed. Stage every approved path, including deletions and newly added files. Prefer the reviewed explicit path list. In all-changes mode, repository-root `git add -A` is allowed only after confirming the entire candidate set is unchanged from the approved snapshot and has no unresolved exclusions; never force-add ignored files. For a narrower request, stage only its approved paths/hunks.
3. Inspect the entire staged diff and run `git diff --cached --check`. It must match the approved snapshot exactly, include every approved change and contain nothing outside that scope. Stop on a mismatch instead of committing a surprise.
4. Write the approved message to a temporary UTF-8 file outside the repository and commit with `git commit -F <message-file>`. Use structured arguments or safe quoting; never interpolate user text into an executable shell expression. Respect configured hooks and signing. Do not use `--no-verify`, forge identity/trailers or disable signing to bypass a failure.
5. Verify the new commit's parent, message and complete diff against the approved result, including hook effects. Ensure HEAD is still that exact commit. Push **that recorded SHA** to the explicit remote branch with a normal, non-force refspec such as `git push <remote> <approved-sha>:refs/heads/<approved-branch>`. This avoids publishing an unexpected newer HEAD. Never push tags or all branches implicitly. Set upstream separately when appropriate after success.
6. Verify the remote branch SHA against the pushed commit, then report the commit ID, subject, destination and outcome. Inspect the working tree with untracked files included and report any remaining changes. In all-changes mode, do not claim everything was submitted if eligible changes remain. A local commit is not evidence that a push succeeded; a successful push is not a merged PR or a release.

If a hook, signing or commit step fails, report the exact blocker without bypassing it. If push fails, preserve the local commit and report its SHA and the blocker. Do not automatically force-push, amend, rebase, reset or switch destinations. For an ambiguous network result, query the remote ref before retrying to see whether the push already succeeded. The same approved SHA/destination can be retried after the blocker is resolved; changed contents or destination require a new preview. Never create a duplicate commit merely because push failed.
