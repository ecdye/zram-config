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
See [here](https://chris.beams.io/posts/git-commit) for great explanation as to why.

Code review comments may be added to your pull request.
Discuss, then make the suggested modifications and push additional commits to your feature branch.
Be sure to post a comment after pushing.
The new commits will show up in the pull request automatically, but the reviewers will not be notified unless you comment.

Pull requests will be tested on the GitHub Actions platform which **shall** pass.

Commits that fix or close an issue should include a reference like `Closes #XXX` or `Fixes #XXX`, which will automatically close the issue when merged.

Before the pull request is merged, your commits might get squashed, based on the size and style of your contribution.
Include documentation changes in the same pull request, so that a revert would remove all traces of the feature or fix.

### Sign your work

The sign-off is a simple line at the end of the explanation for the patch, which certifies that you wrote it or otherwise have the right to pass it on as an open-source patch.
The rules are pretty simple: if you can certify the below (from [developercertificate.org](https://developercertificate.org/)):

```
Developer Certificate of Origin
Version 1.1

Copyright (C) 2004, 2006 The Linux Foundation and its contributors.
660 York Street, Suite 102,
San Francisco, CA 94110 USA

Everyone is permitted to copy and distribute verbatim copies of this
license document, but changing it is not allowed.


Developer's Certificate of Origin 1.1

By making a contribution to this project, I certify that:

(a) The contribution was created in whole or in part by me and I
    have the right to submit it under the open source license
    indicated in the file; or

(b) The contribution is based upon previous work that, to the best
    of my knowledge, is covered under an appropriate open source
    license and I have the right under that license to submit that
    work with modifications, whether created in whole or in part
    by me, under the same open source license (unless I am
    permitted to submit under a different license), as indicated
    in the file; or

(c) The contribution was provided directly to me by some other
    person who certified (a), (b) or (c) and I have not modified
    it.

(d) I understand and agree that this project and the contribution
    are public and that a record of the contribution (including all
    personal information I submit with it, including my sign-off) is
    maintained indefinitely and may be redistributed consistent with
    this project or the open source license(s) involved.
```

then you just add a line to every git commit message:

```
Signed-off-by: Joe Smith <joe.smith@email.com>
```

using your real name (sorry, no pseudonyms or anonymous contributions) and an e-mail address under which you can be reached (sorry, no GitHub no-reply e-mail addresses (such as username@users.noreply.github.com) or other non-reachable addresses are allowed).

#### Small patch exception

There are a few exceptions to the signing requirement.
Currently these are:

*   Your patch fixes spelling or grammar errors.
*   Your patch is a single line change to documentation.

#### Sign your Work using GPG

You can additionally sign your contribution using GPG.
Have a look at the [git documentation](https://git-scm.com/book/en/v2/Git-Tools-Signing-Your-Work) for more details.
This step is optional and not needed for the acceptance of your pull request.

### Linter

The [ShellCheck](https://www.shellcheck.net/) linter can be run by using the following commands:

``` bash
shellcheck -x -s bash install.bash
shellcheck -x -s bash update.bash
shellcheck -x -s bash uninstall.bash
shellcheck -x -s bash zram-config
```
