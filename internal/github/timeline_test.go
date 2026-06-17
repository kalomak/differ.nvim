package github

import (
	"context"
	"encoding/json"
	"net/http"
	"testing"
)

// one review node, rendered into the reviews connection of a timeline page.
func reviewNode(author, state, body, submittedAt string) string {
	b, _ := json.Marshal(struct {
		Author      loginDTO `json:"author"`
		State       string   `json:"state"`
		Body        string   `json:"body"`
		SubmittedAt string   `json:"submittedAt"`
	}{loginDTO{author}, state, body, submittedAt})
	return string(b)
}

func timelinePage(comments, reviews, hasNext, cursor string) string {
	return `{"data":{"repository":{"pullRequest":{` +
		`"comments":{"nodes":[` + comments + `],"pageInfo":{"hasNextPage":` + hasNext + `,"endCursor":"` + cursor + `"}},` +
		`"reviews":{"nodes":[` + reviews + `]}` +
		`}}}}`
}

func TestGetTimelinePaginatesComments(t *testing.T) {
	c1 := `{"author":{"login":"alice"},"body":"first","createdAt":"2026-01-01T00:00:00Z"}`
	c2 := `{"author":{"login":"bob"},"body":"second","createdAt":"2026-01-02T00:00:00Z"}`
	review := reviewNode("carol", "APPROVED", "lgtm", "2026-01-03T00:00:00Z")
	calls := 0
	c := newClient(func(*http.Request) (*http.Response, error) {
		calls++
		if calls == 1 {
			// reviews only collected on the first page
			return resp(200, timelinePage(c1, review, "true", "CUR"), nil), nil
		}
		return resp(200, timelinePage(c2, "", "false", ""), nil), nil
	})
	tl, err := c.GetTimeline(context.Background(), "o", "r", 3)
	if err != nil {
		t.Fatal(err)
	}
	if calls != 2 {
		t.Fatalf("want 2 pages, got %d", calls)
	}
	if len(tl.Comments) != 2 || tl.Comments[0].Author != "alice" || tl.Comments[1].Author != "bob" {
		t.Fatalf("comments not paginated: %+v", tl.Comments)
	}
	// reviews collected once, not duplicated across pages
	if len(tl.Reviews) != 1 || tl.Reviews[0].State != "APPROVED" || tl.Reviews[0].CreatedAt != "2026-01-03T00:00:00Z" {
		t.Fatalf("reviews wrong: %+v", tl.Reviews)
	}
}

func TestGetTimelineDropsPendingDraft(t *testing.T) {
	// a PENDING draft has an empty submittedAt → not a timeline entry
	pending := reviewNode("alice", "PENDING", "wip", "")
	approved := reviewNode("bob", "APPROVED", "lgtm", "2026-01-02T00:00:00Z")
	c := newClient(func(*http.Request) (*http.Response, error) {
		return resp(200, timelinePage("", pending+","+approved, "false", ""), nil), nil
	})
	tl, err := c.GetTimeline(context.Background(), "o", "r", 3)
	if err != nil {
		t.Fatal(err)
	}
	if len(tl.Reviews) != 1 || tl.Reviews[0].Author != "bob" {
		t.Fatalf("pending draft not dropped: %+v", tl.Reviews)
	}
}

func TestGetTimelineDropsBareCommentedReview(t *testing.T) {
	// a bare COMMENTED review with no summary body is noise (its inline comments live
	// in the diff overlay); a CHANGES_REQUESTED verdict with an empty body is kept.
	bare := reviewNode("alice", "COMMENTED", "", "2026-01-01T00:00:00Z")
	changes := reviewNode("bob", "CHANGES_REQUESTED", "", "2026-01-02T00:00:00Z")
	commentedWithBody := reviewNode("carol", "COMMENTED", "a note", "2026-01-03T00:00:00Z")
	c := newClient(func(*http.Request) (*http.Response, error) {
		return resp(200, timelinePage("", bare+","+changes+","+commentedWithBody, "false", ""), nil), nil
	})
	tl, err := c.GetTimeline(context.Background(), "o", "r", 3)
	if err != nil {
		t.Fatal(err)
	}
	if len(tl.Reviews) != 2 {
		t.Fatalf("want 2 kept reviews, got %+v", tl.Reviews)
	}
	if tl.Reviews[0].Author != "bob" || tl.Reviews[1].Author != "carol" {
		t.Fatalf("kept the wrong reviews: %+v", tl.Reviews)
	}
}

func TestGetTimelineEmptyMarshalsToArrays(t *testing.T) {
	c := newClient(func(*http.Request) (*http.Response, error) {
		return resp(200, timelinePage("", "", "false", ""), nil), nil
	})
	tl, err := c.GetTimeline(context.Background(), "o", "r", 3)
	if err != nil {
		t.Fatal(err)
	}
	b, err := json.Marshal(tl)
	if err != nil {
		t.Fatal(err)
	}
	got := string(b)
	want := `{"comments":[],"reviews":[]}`
	if got != want {
		t.Fatalf("empty timeline marshalled to %s, want %s", got, want)
	}
}
