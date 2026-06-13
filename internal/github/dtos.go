package github

// github wire shapes we decode into. these track GitHub's API (REST field names,
// GraphQL enums, the {data,errors} envelope); the contract-facing shapes built
// from them are in results.go.

// pullDTO is a REST /pulls list item (also covers the fields list_prs filters on).
type pullDTO struct {
	Number int      `json:"number"`
	Title  string   `json:"title"`
	User   loginDTO `json:"user"`
	Head   struct {
		Ref string `json:"ref"`
	} `json:"head"`
	UpdatedAt string     `json:"updated_at"`
	Draft     bool       `json:"draft"`
	Reviewers []loginDTO `json:"requested_reviewers"`
}

type loginDTO struct {
	Login string `json:"login"`
}

// userDTO is the REST /user response (the authenticated viewer).
type userDTO struct {
	Login string `json:"login"`
}

// fileDTO is a REST /pulls/{n}/files item; the authoritative file list, carrying
// rename info (PreviousFilename) that the GraphQL files() connection omits.
type fileDTO struct {
	Filename         string `json:"filename"`
	Status           string `json:"status"`
	Additions        int    `json:"additions"`
	Deletions        int    `json:"deletions"`
	PreviousFilename string `json:"previous_filename"`
}

// prDetailGQL is the get_pr GraphQL response: PR metadata plus a page of files
// carrying viewerViewedState (REST has no equivalent field).
type prDetailGQL struct {
	Repository struct {
		PullRequest struct {
			Title       string   `json:"title"`
			Body        string   `json:"body"`
			URL         string   `json:"url"`
			State       string   `json:"state"`
			IsDraft     bool     `json:"isDraft"`
			Mergeable   string   `json:"mergeable"`
			BaseRefOid  string   `json:"baseRefOid"`
			HeadRefOid  string   `json:"headRefOid"`
			HeadRefName string   `json:"headRefName"`
			Author      loginDTO `json:"author"`
			Files       struct {
				Nodes []struct {
					Path              string `json:"path"`
					ViewerViewedState string `json:"viewerViewedState"`
				} `json:"nodes"`
				PageInfo pageInfoGQL `json:"pageInfo"`
			} `json:"files"`
		} `json:"pullRequest"`
	} `json:"repository"`
}

type pageInfoGQL struct {
	HasNextPage bool   `json:"hasNextPage"`
	EndCursor   string `json:"endCursor"`
}
