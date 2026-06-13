package handlers

import (
	"context"
	"encoding/json"

	"github.com/seanhalberthal/dipher.nvim/internal/protocol"
)

type getFileVersionsParams struct {
	prParams
	Path string `json:"path"`
}

// getFileVersions returns the full base/head blobs for one PR file (§7.3).
func (d Deps) getFileVersions(ctx context.Context, params json.RawMessage) (any, error) {
	var p getFileVersionsParams
	if err := decode(params, &p); err != nil {
		return nil, err
	}
	if err := requirePR(p.Owner, p.Repo, p.Number); err != nil {
		return nil, err
	}
	if p.Path == "" {
		return nil, protocol.NewError(protocol.CodeBadRequest, "path is required")
	}
	return d.GH.GetFileVersions(ctx, p.Owner, p.Repo, p.Number, p.Path)
}
