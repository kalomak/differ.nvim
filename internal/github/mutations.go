package github

// GraphQL mutation documents (and the lookups their methods need). kept apart from
// the read queries in queries.go.

// startReviewLookupQuery fetches the PR node id plus the viewer's existing pending
// review (if any) in one round trip, so start_review can be idempotent.
const startReviewLookupQuery = `
query StartReviewLookup($owner: String!, $repo: String!, $number: Int!) {
  repository(owner: $owner, name: $repo) {
    pullRequest(number: $number) {
      id
      reviews(first: 1, states: [PENDING]) {
        nodes { id }
      }
    }
  }
}`

// addReviewMutation creates a pending review (no event) on the PR.
const addReviewMutation = `
mutation AddReview($prId: ID!) {
  addPullRequestReview(input: {pullRequestId: $prId}) {
    pullRequestReview { id }
  }
}`

// submitReviewMutation finalizes a pending review with an event (APPROVE /
// REQUEST_CHANGES / COMMENT) and optional body.
const submitReviewMutation = `
mutation SubmitReview($reviewId: ID!, $event: PullRequestReviewEvent!, $body: String) {
  submitPullRequestReview(input: {pullRequestReviewId: $reviewId, event: $event, body: $body}) {
    pullRequestReview { fullDatabaseId }
  }
}`

// deleteReviewMutation discards a pending review and its unsubmitted comments.
const deleteReviewMutation = `
mutation DeleteReview($reviewId: ID!) {
  deletePullRequestReview(input: {pullRequestReviewId: $reviewId}) {
    pullRequestReview { id }
  }
}`
