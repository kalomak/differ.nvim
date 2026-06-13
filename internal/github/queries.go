package github

// getPRQuery fetches PR metadata plus a page of files carrying viewerViewedState.
// the file list itself (with rename info) comes from REST; this supplies the
// per-file viewed state and the metadata REST splits across endpoints.
const getPRQuery = `
query GetPR($owner: String!, $repo: String!, $number: Int!, $cursor: String) {
  repository(owner: $owner, name: $repo) {
    pullRequest(number: $number) {
      title
      body
      url
      state
      isDraft
      mergeable
      baseRefOid
      headRefOid
      headRefName
      author { login }
      files(first: 100, after: $cursor) {
        nodes {
          path
          viewerViewedState
        }
        pageInfo {
          hasNextPage
          endCursor
        }
      }
    }
  }
}`
