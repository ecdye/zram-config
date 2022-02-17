# Contribution Guidelines

## Pull requests are always welcome

We are always thrilled to receive pull requests, and do our best to process them as fast as possible.
Not sure if that typo is worth a pull request?
Do it!
We will appreciate it.

If your pull request is not accepted on the first try, don't be discouraged!
If there's a problem with the implementation, you will receive feedback on what to improve.

We might decide against incorporating a new feature that does not match the scope of this project.
Get in contact early in the development to propose your idea.

## Conventions

Fork the repo and make changes on your fork in a feature branch.
Then be sure to update the documentation when creating or modifying features.
Test your changes for clarity, concision, and correctness.

Always write clean, modular and testable code.
We use [ShellCheck](https://www.shellcheck.net/) as a linter for our code, and as our coding guidelines.
See [Linter](#linter) below for more details on running ShellCheck.

Pull requests descriptions should be as clear as possible and include a reference to all the issues that they address.

Pull requests must not contain commits from other users or branches.

Commit messages **must** start with a capitalized and short summary (max. 50 chars) written in the imperative, followed by an optional, more detailed explanatory text which is separated from the summary by an empty line.
See [here](https://cbea.ms/git-commit/) for great explanation as to why.

Code review comments may be added to your pull request.
Discuss, then make the suggested modifications and push additional commits to your feature branch.
Be sure to post a comment after pushing.
The new commits will show up in the pull request automatically, but the reviewers will not be notified unless you comment.

Pull requests will be tested on the GitHub Actions platform which **shall** pass.

Commits that fix or close an issue should include a reference like `Closes #XXX` or `Fixes #XXX`, which will automatically close the issue when merged.

Before the pull request is merged, your commits might get squashed, based on the size and style of your contribution.
Include documentation changes in the same pull request, so that a revert would remove all traces of the feature or fix.

### Sign off your work

The sign-off is a simple line at the end of the explanation for the patch, which certifies that you wrote it or otherwise have the right to pass it on as an open-source patch.
The rules are pretty simple: if you can certify your patch under the guidelines provided by <https://developercertificate.org/> then you just add the following line to every git commit message.

```
Signed-off-by: Joe Smith <joe.smith@email.com>
```

You must use your real name (sorry, no pseudonyms or anonymous contributions) and an e-mail address under which you can be reached (sorry, no GitHub no-reply e-mail addresses (such as username@users.noreply.github.com) or other non-reachable addresses are allowed).

### Sign your work using GPG

You can additionally sign your contribution using GPG.
Have a look at the [git documentation](https://git-scm.com/book/en/v2/Git-Tools-Signing-Your-Work) for more details.
This step is optional and not needed for the acceptance of your pull request.

### Linter

The [ShellCheck](https://www.shellcheck.net/) linter can be run by using the following commands:

``` bash
shellcheck -x -s bash tests/*.bash
shellcheck -x -s bash install.bash
shellcheck -x -s bash update.bash
shellcheck -x -s bash uninstall.bash
shellcheck -x -s bash zram-config
```
