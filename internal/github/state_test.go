package github

import (
	"context"
	"net/http"
	"strings"
	"testing"
)

func TestSetPRStateReadyLooksUpNodeThenMutates(t *testing.T) {
	var ops []string
	c := newClient(func(r *http.Request) (*http.Response, error) {
		body := string(readBody(t, r))
		switch {
		case strings.Contains(body, "PRNodeID"):
			ops = append(ops, "lookup")
			return resp(200, `{"data":{"repository":{"pullRequest":{"id":"PR_NODE"}}}}`, nil), nil
		case strings.Contains(body, "markPullRequestReadyForReview"):
			ops = append(ops, "ready")
			if !strings.Contains(body, `"prId":"PR_NODE"`) {
				t.Errorf("node id not threaded: %s", body)
			}
			return resp(200, `{"data":{"result":{"pullRequest":{"state":"OPEN","isDraft":false}}}}`, nil), nil
		}
		t.Fatalf("unexpected request: %s", body)
		return nil, nil
	})
	res, err := c.SetPRState(context.Background(), "o", "r", 3, "ready")
	if err != nil {
		t.Fatal(err)
	}
	if res.State != "open" {
		t.Errorf("state = %q, want open", res.State)
	}
	if len(ops) != 2 || ops[0] != "lookup" || ops[1] != "ready" {
		t.Errorf("want lookup then ready, got %v", ops)
	}
}

// each requested transition routes to its mutation and normalises the result.
func TestSetPRStateTransitions(t *testing.T) {
	cases := []struct {
		state    string
		mutation string
		respJSON string
		want     string
	}{
		{"draft", "convertPullRequestToDraft", `{"data":{"result":{"pullRequest":{"state":"OPEN","isDraft":true}}}}`, "draft"},
		{"closed", "closePullRequest", `{"data":{"result":{"pullRequest":{"state":"CLOSED","isDraft":false}}}}`, "closed"},
		{"open", "reopenPullRequest", `{"data":{"result":{"pullRequest":{"state":"OPEN","isDraft":false}}}}`, "open"},
	}
	for _, tc := range cases {
		t.Run(tc.state, func(t *testing.T) {
			c := newClient(func(r *http.Request) (*http.Response, error) {
				body := string(readBody(t, r))
				if strings.Contains(body, "PRNodeID") {
					return resp(200, `{"data":{"repository":{"pullRequest":{"id":"PR_NODE"}}}}`, nil), nil
				}
				if !strings.Contains(body, tc.mutation) {
					t.Errorf("state %q should hit %s: %s", tc.state, tc.mutation, body)
				}
				return resp(200, tc.respJSON, nil), nil
			})
			res, err := c.SetPRState(context.Background(), "o", "r", 3, tc.state)
			if err != nil {
				t.Fatal(err)
			}
			if res.State != tc.want {
				t.Errorf("state = %q, want %q", res.State, tc.want)
			}
		})
	}
}

func TestSetPRStateRejectsUnknownState(t *testing.T) {
	c := newClient(func(*http.Request) (*http.Response, error) {
		t.Fatal("must not hit the network for an unknown state")
		return nil, nil
	})
	_, err := c.SetPRState(context.Background(), "o", "r", 3, "frozen")
	if codeOf(t, err) != "bad_request" {
		t.Fatalf("want bad_request, got %v", err)
	}
}
