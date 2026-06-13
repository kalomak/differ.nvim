package github

// client-facing result shapes. these track the frozen §7.3 contract and must not
// drift; the github wire shapes they are built from live in dtos.go.

// PR is one row in the list_prs result.
type PR struct {
	Number    int    `json:"number"`
	Title     string `json:"title"`
	Author    string `json:"author"`
	HeadRef   string `json:"head_ref"`
	UpdatedAt string `json:"updated_at"`
	Draft     bool   `json:"draft"`
}

// PRDetail is the get_pr result.
type PRDetail struct {
	Title     string   `json:"title"`
	Body      string   `json:"body"`
	Author    string   `json:"author"`
	BaseSHA   string   `json:"base_sha"`
	HeadSHA   string   `json:"head_sha"`
	HeadRef   string   `json:"head_ref"`
	URL       string   `json:"url"`
	State     string   `json:"state"`
	Draft     bool     `json:"draft"`
	Mergeable string   `json:"mergeable"`
	Files     []PRFile `json:"files"`
}

// PRFile is one changed file in a PRDetail. ViewedState is VIEWED/DISMISSED/UNVIEWED.
type PRFile struct {
	Path         string `json:"path"`
	Status       string `json:"status"`
	Additions    int    `json:"additions"`
	Deletions    int    `json:"deletions"`
	PreviousPath string `json:"previous_path,omitempty"`
	ViewedState  string `json:"viewed_state"`
}
