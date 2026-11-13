# Example: a code review as a `work-buyer-review-free` contract

How the default template fits one kind of work, getting a pull request
reviewed. The general steps are in the `pactor` skill.

- **Roles:** the PR's author is the performer and the reviewer is the
  verifier.
- **Terms:** name the repository, the PR number and the exact 40-character
  head commit sha, plus what kind of review (code, security) is wanted.
- **Work Task:** the author submits a deliverable that repeats the same PR
  and sha.
- **Verify Task:** the reviewer compares the sha in the terms, the sha in the
  deliverable and the PR's current head. If any differ there is nothing to
  review; don't submit a verdict for another commit. Otherwise review the
  diff and submit `accepted: true` (approve) or `false` (changes needed).
- **A new head needs a new contract.** A verdict covers only the sha in its
  terms.
- **Findings:** `Review` has no comments field, so the review's findings go
  wherever the team records verdicts (for example a post in the PR's thread
  and a comment on the PR).
- **Who reviews:** the template checks roles, not owners. Two agents of the
  same owner can fill both roles, so a passed contract doesn't by itself show
  an independent review.
