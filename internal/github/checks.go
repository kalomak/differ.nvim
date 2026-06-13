package github

import "context"

// GetChecks returns the status-check rollup for the PR's head commit: the overall
// state plus each check (CheckRun or legacy StatusContext) normalised to a common
// shape. an absent rollup (no checks configured) yields an empty rollup and list.
func (c *Client) GetChecks(ctx context.Context, owner, repo string, number int) (*Checks, error) {
	var page checksGQL
	vars := map[string]any{"owner": owner, "repo": repo, "number": number}
	if err := c.graphql(ctx, getChecksQuery, vars, &page); err != nil {
		return nil, err
	}
	out := &Checks{Checks: []Check{}}
	commits := page.Repository.PullRequest.Commits.Nodes
	if len(commits) == 0 {
		return out, nil
	}
	rollup := commits[0].Commit.StatusCheckRollup
	if rollup == nil {
		return out, nil
	}
	out.Rollup = rollup.State
	for _, n := range rollup.Contexts.Nodes {
		out.Checks = append(out.Checks, normaliseCheck(n))
	}
	return out, nil
}

// normaliseCheck flattens one rollup context. a CheckRun maps directly; a legacy
// StatusContext carries a single state, surfaced as the conclusion with a derived
// status (PENDING/EXPECTED stay in-progress, anything else is complete).
func normaliseCheck(n checkContextGQL) Check {
	if n.Typename == "StatusContext" {
		status := "COMPLETED"
		if n.State == "PENDING" || n.State == "EXPECTED" {
			status = "PENDING"
		}
		return Check{
			Name:       n.Context,
			Status:     status,
			Conclusion: n.State,
			URL:        n.TargetURL,
			StartedAt:  n.CreatedAt,
		}
	}
	return Check{
		Name:       n.Name,
		Status:     n.Status,
		Conclusion: n.Conclusion,
		URL:        n.DetailsURL,
		StartedAt:  n.StartedAt,
	}
}
