package handlers

import (
	"context"
	"encoding/json"
	"errors"
	"io"
	"log/slog"
	"testing"

	"github.com/seanhalberthal/dipher.nvim/internal/github"
	"github.com/seanhalberthal/dipher.nvim/internal/protocol"
)

// mockAPI records what it was called with so handler routing/validation can be
// asserted without the github transport.
type mockAPI struct {
	prs       []github.PR
	detail    *github.PRDetail
	gotFilter string
	gotNumber int
	called    bool
}

func (m *mockAPI) ListPRs(_ context.Context, _, _, filter string) ([]github.PR, error) {
	m.called = true
	m.gotFilter = filter
	return m.prs, nil
}

func (m *mockAPI) GetPR(_ context.Context, _, _ string, number int) (*github.PRDetail, error) {
	m.called = true
	m.gotNumber = number
	return m.detail, nil
}

func deps(m *mockAPI) Deps {
	return Deps{GH: m, Log: slog.New(slog.NewTextHandler(io.Discard, nil))}
}

func wantBadRequest(t *testing.T, err error) {
	t.Helper()
	var pe *protocol.Error
	if !errors.As(err, &pe) || pe.Code != protocol.CodeBadRequest {
		t.Fatalf("want bad_request, got %v", err)
	}
}

func TestListPRsRoutes(t *testing.T) {
	m := &mockAPI{prs: []github.PR{{Number: 9}}}
	res, err := deps(m).listPRs(context.Background(), json.RawMessage(`{"owner":"o","repo":"r","filter":"mine"}`))
	if err != nil {
		t.Fatal(err)
	}
	if m.gotFilter != "mine" {
		t.Errorf("filter not forwarded: %q", m.gotFilter)
	}
	if prs := res.([]github.PR); len(prs) != 1 || prs[0].Number != 9 {
		t.Errorf("result not forwarded: %+v", res)
	}
}

func TestListPRsRequiresRepo(t *testing.T) {
	m := &mockAPI{}
	_, err := deps(m).listPRs(context.Background(), json.RawMessage(`{"owner":"o"}`))
	wantBadRequest(t, err)
	if m.called {
		t.Error("GH must not be called when validation fails")
	}
}

func TestGetPRRoutes(t *testing.T) {
	m := &mockAPI{detail: &github.PRDetail{Title: "T"}}
	res, err := deps(m).getPR(context.Background(), json.RawMessage(`{"owner":"o","repo":"r","number":42}`))
	if err != nil {
		t.Fatal(err)
	}
	if m.gotNumber != 42 {
		t.Errorf("number not forwarded: %d", m.gotNumber)
	}
	if res.(*github.PRDetail).Title != "T" {
		t.Errorf("result not forwarded: %+v", res)
	}
}

func TestGetPRRequiresNumber(t *testing.T) {
	m := &mockAPI{}
	_, err := deps(m).getPR(context.Background(), json.RawMessage(`{"owner":"o","repo":"r"}`))
	wantBadRequest(t, err)
	if m.called {
		t.Error("GH must not be called without a number")
	}
}

func TestMalformedParams(t *testing.T) {
	m := &mockAPI{}
	_, err := deps(m).getPR(context.Background(), json.RawMessage(`{"number":"not-an-int"}`))
	wantBadRequest(t, err)
}
