package handlers

import (
	"context"
	"encoding/json"

	"github.com/seanhalberthal/dipher.nvim/internal/protocol"
)

// startReview creates (or reattaches to) the viewer's pending review (§7.3).
func (d Deps) startReview(ctx context.Context, params json.RawMessage) (any, error) {
	var p prParams
	if err := decode(params, &p); err != nil {
		return nil, err
	}
	if err := requirePR(p.Owner, p.Repo, p.Number); err != nil {
		return nil, err
	}
	return d.GH.StartReview(ctx, p.Owner, p.Repo, p.Number)
}

type submitReviewParams struct {
	prParams
	ReviewID string `json:"review_id"`
	Event    string `json:"event"`
	Body     string `json:"body"`
}

// submitReview finalizes a pending review as one batch (§7.3).
func (d Deps) submitReview(ctx context.Context, params json.RawMessage) (any, error) {
	var p submitReviewParams
	if err := decode(params, &p); err != nil {
		return nil, err
	}
	if err := requirePR(p.Owner, p.Repo, p.Number); err != nil {
		return nil, err
	}
	if err := requireReviewID(p.ReviewID); err != nil {
		return nil, err
	}
	if !validReviewEvent(p.Event) {
		return nil, protocol.NewError(protocol.CodeBadRequest, "event must be APPROVE, REQUEST_CHANGES, or COMMENT")
	}
	return d.GH.SubmitReview(ctx, p.ReviewID, p.Event, p.Body)
}

type discardReviewParams struct {
	prParams
	ReviewID string `json:"review_id"`
}

// discardReview deletes a pending review and its unsubmitted comments (§7.3).
func (d Deps) discardReview(ctx context.Context, params json.RawMessage) (any, error) {
	var p discardReviewParams
	if err := decode(params, &p); err != nil {
		return nil, err
	}
	if err := requirePR(p.Owner, p.Repo, p.Number); err != nil {
		return nil, err
	}
	if err := requireReviewID(p.ReviewID); err != nil {
		return nil, err
	}
	if err := d.GH.DiscardReview(ctx, p.ReviewID); err != nil {
		return nil, err
	}
	return struct{}{}, nil
}

func requireReviewID(reviewID string) error {
	if reviewID == "" {
		return protocol.NewError(protocol.CodeBadRequest, "review_id is required")
	}
	return nil
}

func validReviewEvent(event string) bool {
	switch event {
	case "APPROVE", "REQUEST_CHANGES", "COMMENT":
		return true
	default:
		return false
	}
}
