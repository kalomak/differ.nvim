package handlers

import (
	"context"
	"encoding/json"

	"github.com/seanhalberthal/dipher.nvim/internal/protocol"
)

type listPRsParams struct {
	Owner  string `json:"owner"`
	Repo   string `json:"repo"`
	Filter string `json:"filter"`
}

// listPRs returns the PR picker list (§7.3).
func (d Deps) listPRs(ctx context.Context, params json.RawMessage) (any, error) {
	var p listPRsParams
	if err := decode(params, &p); err != nil {
		return nil, err
	}
	if err := requireRepo(p.Owner, p.Repo); err != nil {
		return nil, err
	}
	return d.GH.ListPRs(ctx, p.Owner, p.Repo, p.Filter)
}

type getPRParams struct {
	Owner  string `json:"owner"`
	Repo   string `json:"repo"`
	Number int    `json:"number"`
}

// getPR returns full PR detail incl. per-file viewed state and rename info (§7.3).
func (d Deps) getPR(ctx context.Context, params json.RawMessage) (any, error) {
	var p getPRParams
	if err := decode(params, &p); err != nil {
		return nil, err
	}
	if err := requireRepo(p.Owner, p.Repo); err != nil {
		return nil, err
	}
	if p.Number <= 0 {
		return nil, protocol.NewError(protocol.CodeBadRequest, "number is required")
	}
	return d.GH.GetPR(ctx, p.Owner, p.Repo, p.Number)
}

func requireRepo(owner, repo string) error {
	if owner == "" || repo == "" {
		return protocol.NewError(protocol.CodeBadRequest, "owner and repo are required")
	}
	return nil
}
