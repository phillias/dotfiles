# MyWebApp Design Lessons

Design patterns, gotchas, and best practices for Go + HTMX web applications. Load when starting a new web project, adding pages to an existing Go+HTMX app, or debugging template rendering issues.

---

## Go html/template Gotchas

### The Dynamic Template Name Trap

`html/template` does **not** support dynamic template names. This will panic at parse time:

```go
// BROKEN — panics: unexpected ".ContentTe"... in template clause
{{template .ContentTemplate .}}
```

**Use explicit conditionals instead:**

```html
{{if eq .Page "bills"}}{{template "bill_list_content" .}}{{end}}
{{if eq .Page "email"}}{{template "email_action_content" .}}{{end}}
{{if eq .Page "bill_detail"}}{{template "bill_detail_content" .}}{{end}}
```

Each handler sets a `"Page"` key in its data map. This works, is explicit, and fails at render time with a clear message if the page name is wrong.

> **Note:** `text/template` *does* support `{{template .Var .}}` but loses HTML escaping. Don't use it for user-facing HTML.

### Template Name Collisions with ParseGlob

When using `template.ParseGlob("templates/*.html")`, if two files define `{{define "same_name"}}`, the **last file parsed (alphabetically) wins silently**. No error, no warning.

```go
tmpl := template.Must(tmpl.ParseGlob("templates/*.html"))
```

If `bill_list.html` defines `{{define "page"}}` and `email_action.html` also defines `{{define "page"}}`, the email template silently overwrites the bill list. Every page renders the email content.

**Rule:** Every `{{define}}` name must be globally unique across all template files. Name them after their purpose: `bill_list_content`, `email_action_content`, `bill_detail_content`.

### Recommended Base Template Pattern

```html
{{define "base"}}
<!DOCTYPE html>
<html>
<head>...</head>
<body>
    <header>...</header>
    <main>
        {{if eq .Page "bills"}}{{template "bill_list_content" .}}{{end}}
        {{if eq .Page "bill_detail"}}{{template "bill_detail_content" .}}{{end}}
        {{if eq .Page "email"}}{{template "email_action_content" .}}{{end}}
    </main>
    <footer>...</footer>
</body>
</html>
{{end}}
```

Each content template uses a unique `{{define "name"}}` and the handler passes `"Page": "name"`.

### Template Caching

Precompile templates at startup, not per-request. Store the parsed `*template.Template` on your handler struct:

```go
type Handler struct {
    templates *template.Template
    // ... other deps
}

func main() {
    tmpl := template.Must(template.New("").Funcs(funcMap).ParseGlob("templates/*.html"))
    handler.SetTemplates(tmpl)
}
```

This eliminates parse overhead on every request. Precompilation reduces response time by ~25% under load.

---

## Templ vs html/template Decision

### When to Use html/template

- Simple apps, admin panels, CRUD dashboards
- Team is backend-focused, no need for type-safe components
- Quick prototyping — zero build step
- CMS-like content rendering

### When to Consider Templ

- Larger apps where template errors at runtime are costly
- Team wants compile-time checking of template variables
- Component composition (passing components as props)
- When you'd benefit from IDE autocomplete in template code

Templ compiles to pure Go functions — no virtual DOM, no reconciliation, just `io.Writer` streaming bytes. It brings the "component" mental model (props, composition, type safety) to the backend.

```go
// Templ component with type safety
templ UserProfile(user types.User) {
    <div class="p-4 border">
        <h1>{ user.Name }</h1>
        if user.IsAdmin {
            @AdminBadge(user.Role)
        }
    </div>
}
```

If you remove `Role` from the `User` struct, the UI code fails to compile. With `html/template`, you discover this at runtime.

**Recommendation:** Start with `html/template` for simplicity. Migrate to Templ if template errors become a pain point or the component model adds clear value.

---

## HTMX Architecture Patterns

### The HX-Request Header

HTMX sends `HX-Request: true` with every AJAX request. Use it to distinguish between full page loads and HTMX partial updates:

```go
func listUsers(w http.ResponseWriter, r *http.Request) {
    users := getUsersFromDB()

    if r.Header.Get("HX-Request") != "" {
        // HTMX request — return just the fragment
        tmpl.ExecuteTemplate(w, "partials/user-list", users)
    } else {
        // Full page load — return complete page
        tmpl.ExecuteTemplate(w, "base", map[string]interface{}{
            "Page":  "users",
            "Users": users,
        })
    }
}
```

This pattern lets the same handler serve both full pages and HTMX fragments.

### Fragment Handlers

For HTMX partial page updates, use separate `renderFragment` calls that return raw HTML without the base layout:

```go
func (h *Handler) renderFragment(w http.ResponseWriter, name string, data interface{}) {
    w.Header().Set("Content-Type", "text/html; charset=utf-8")
    h.templates.ExecuteTemplate(w, name, data)
}
```

Fragments don't go through `base` — they're injected directly into the DOM via `hx-target`.

### hx-target Extended Selectors

Avoid peppering your HTML with `id` attributes. Use HTMX's extended CSS selectors:

```html
<!-- Target closest ancestor -->
<button hx-post="/toggle" hx-target="closest .card">Toggle</button>

<!-- Target next sibling -->
<button hx-get="/data" hx-target="next .results">Load</button>

<!-- Target first child descendant -->
<div hx-get="/status" hx-target="find .status">
    <span class="status">Loading...</span>
</div>

<!-- Target the element itself -->
<a hx-post="/refresh" hx-target="this" hx-swap="outerHTML">Refresh</a>
```

### hx-swap Strategies

Choose the right swap strategy for your use case:

| Strategy | Use When |
|----------|----------|
| `innerHTML` (default) | Replacing content inside a container |
| `outerHTML` | Replacing the element itself (e.g., swapping a form for a success message) |
| `beforeend` | Appending to a list |
| `afterbegin` | Prepending to a list |
| `delete` | Removing an element (return empty response) |
| `none` | Server-side only, no DOM update |

### Error Handling

HTMX 4+ swaps all HTTP responses by default, including 4xx and 5xx. Design error responses as swapable HTML:

```html
<!-- Server returns validation errors as a fragment -->
<form hx-post="/submit" hx-target="#result">
    <input name="email" type="email">
    <button type="submit">Submit</button>
</form>
<div id="result"></div>
<!-- Server returns: <div class="text-red-500">Email already exists</div> -->
```

Use `hx-status` for per-code targeting:

```html
<form hx-post="/submit"
      hx-target="#result"
      hx-status:422="target:#validation-errors"
      hx-status:500="target:#server-error">
```

### Loading States

Show loading indicators during HTMX requests:

```html
<button hx-get="/slow-operation"
        hx-indicator="#spinner">
    Run
</button>
<div id="spinner" class="htmx-indicator">Loading...</div>
```

HTMX adds/removes the `htmx-request` class automatically. Style it:

```css
.htmx-indicator { display: none; }
.htmx-request .htmx-indicator { display: inline-block; }
.htmx-request.htmx-indicator { display: inline-block; }
```

### Out-of-Band (OOB) Swaps

Update multiple elements from one response using `hx-swap-oob`:

```html
<!-- Server response updates two separate elements -->
<div id="messages" hx-swap-oob="beforeend">
    <p>New message received</p>
</div>
<div id="count" hx-swap-oob="true">
    <span>5 new items</span>
</div>
```

### Server-Sent Events (SSE) with HTMX

For real-time updates, HTMX has native SSE support:

```html
<div hx-sse="connect:/sse/events swap:new-request">
    <div id="live-content"></div>
</div>
```

Go server SSE pattern:

```go
func (h *Handler) handleSSE(w http.ResponseWriter, r *http.Request) {
    w.Header().Set("Content-Type", "text/event-stream")
    w.Header().Set("Cache-Control", "no-cache")
    w.Header().Set("Connection", "keep-alive")

    ctx := r.Context()
    for {
        select {
        case event := <-h.eventChan:
            fmt.Fprintf(w, "event: new-request\ndata: %s\n\n", event.HTML)
            w.(http.Flusher).Flush()
        case <-ctx.Done():
            return
        }
    }
}
```

SSE is simpler than WebSockets for one-directional server→browser data. The browser handles reconnection natively.

---

## Go Project Structure

### Recommended Layout for Server-Rendered Apps

```
cmd/server/main.go          # Entry point, template parsing, route registration
internal/
  api/handlers.go           # HTTP handlers (page + fragment + API)
  bills/models.go           # Domain models
  bills/service.go          # Business logic
  email/service.go          # Email templating
  representatives/          # Other domain packages
templates/
  base.html                 # Layout with conditional content routing
  bill_list_content.html    # Unique {{define}} names
  bill_detail_content.html
  email_action_content.html
  scheduled_tab.html        # HTMX fragments
  all_bills_tab.html
  meetings_tab.html
static/                     # CSS, JS, images (if not using CDN)
```

### Handler Organization

Group handlers by concern:

- **Page handlers** — render full pages through `base` template (need `Page` key)
- **Fragment handlers** — render HTMX fragments (raw HTML, no layout)
- **API handlers** — return JSON (for mobile apps, external integrations)

Keep API handlers intact during HTMX migration so the React SPA can coexist during transition.

### Middleware Stack Order

```go
var h http.Handler = mux
h = enableCORS(h)           // Outermost — handles preflight
h = recoveryMiddleware(h)   // Catches panics
h = loggingMiddleware(h)    // Logs all requests
h = securityHeaders(h)      // CSP, X-Frame-Options, etc.
h = rateLimitMiddleware(h)  // Per-IP rate limiting
```

---

## Form Handling Patterns

### Multi-Step Forms with HTMX

Each step is a separate HTMX request that returns the next step's HTML:

```html
<!-- Step 1: Location -->
<form hx-post="/email/{{.BillID}}/find-reps" hx-target="#email-step-container" hx-swap="outerHTML">
    <input name="zip" placeholder="ZIP code" required>
    <button type="submit">Find Representatives</button>
</form>
```

Server returns Step 2 (compose) as a fragment that replaces the form:

```go
func (h *Handler) handleFindReps(w http.ResponseWriter, r *http.Request) {
    // ... find reps ...
    h.renderFragment(w, "email_step_compose", data) // Returns next step HTML
}
```

### Form Validation

Return validation errors as HTML fragments, not JSON:

```go
func (h *Handler) handleSubmit(w http.ResponseWriter, r *http.Request) {
    if err := validate(r); err != nil {
        w.Header().Set("HX-Retarget", "#errors")
        w.Header().Set("HX-Reswap", "innerHTML")
        fmt.Fprintf(w, `<div class="text-red-500">%s</div>`, err.Error())
        return
    }
    // ... success ...
}
```

### Flash Messages

For success/error notifications after form submission:

```go
func (h *Handler) handleCreate(w http.ResponseWriter, r *http.Request) {
    // ... create ...
    w.Header().Set("HX-Trigger", "showToast")
    fmt.Fprintf(w, `<div id="toast" hx-swap-oob="true" class="toast success">Created!</div>`)
}
```

Client-side listener:

```html
<div id="toast" hx-on:showToast="this.classList.add('visible'); setTimeout(() => this.remove(), 3000)"></div>
```

---

## Performance

### Template Precompilation

Parse templates once at startup, not per-request:

```go
func main() {
    funcMap := template.FuncMap{ /* ... */ }
    tmpl := template.Must(template.New("").Funcs(funcMap).ParseGlob("templates/*.html"))
    handler.SetTemplates(tmpl)
}
```

### Minimal Memory Allocations

Use `strings.Builder` for HTML fragment generation instead of string concatenation:

```go
// BAD — allocates per concatenation
html := ""
for _, item := range items {
    html += "<li>" + item.Name + "</li>"
}

// GOOD — single allocation
var b strings.Builder
for _, item := range items {
    fmt.Fprintf(&b, "<li>%s</li>", item.Name)
}
```

### Embedded Assets

Embed static files and templates in the binary for single-binary deployment:

```go
//go:embed templates/*.html
var templateFS embed.FS

//go:embed static/*
var staticFS embed.FS
```

This eliminates filesystem reads at runtime and simplifies deployment.

---

## Security

### CSRF Protection

HTMX submits are same-origin by default (browsers enforce CORS). For additional protection:

```go
func csrfMiddleware(next http.Handler) http.Handler {
    return http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
        if r.Method == http.MethodPost || r.Method == http.MethodPut || r.Method == http.MethodDelete {
            token := r.Header.Get("HX-CSRF-Token")
            if token != validateCSRFToken(r) {
                http.Error(w, "Forbidden", http.StatusForbidden)
                return
            }
        }
        next.ServeHTTP(w, r)
    })
}
```

### Content Security Policy

Set CSP headers to prevent XSS:

```go
func securityHeaders(next http.Handler) http.Handler {
    return http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
        w.Header().Set("Content-Security-Policy", "default-src 'self'; script-src 'self' 'unsafe-inline'")
        w.Header().Set("X-Content-Type-Options", "nosniff")
        w.Header().Set("X-Frame-Options", "DENY")
        next.ServeHTTP(w, r)
    })
}
```

### Input Sanitization

`html/template` auto-escapes by default — this is good. But be careful with:
- `template.HTML()` type — bypasses escaping, use only for trusted content
- `url.Path` parameters — validate before using in templates
- User-generated content in `hx-*` attributes — can inject arbitrary attributes

---

## Testing Strategies

### Handler Tests with httptest

Test page handlers by checking both full-page and HTMX fragment responses:

```go
func TestBillList(t *testing.T) {
    req := httptest.NewRequest("GET", "/", nil)
    w := httptest.NewRecorder()

    handler.handleIndexPage(w, req)

    // Full page test
    if !strings.Contains(w.Body.String(), "Michigan Bill Tracker") {
        t.Error("Expected bill list page")
    }

    // HTMX fragment test
    req.Header.Set("HX-Request", "true")
    w = httptest.NewRecorder()
    handler.handleScheduledFragment(w, req)

    if !strings.Contains(w.Body.String(), "Scheduled Votes") {
        t.Error("Expected scheduled tab fragment")
    }
}
```

### Golden File Testing

Save expected HTML output to files and compare on subsequent runs:

```go
func TestBillListHTML(t *testing.T) {
    // ... render ...
    got := w.Body.String()

    if *update {
        os.WriteFile("testdata/bill_list.html", []byte(got), 0644)
    }

    expected, _ := os.ReadFile("testdata/bill_list.html")
    if got != string(expected) {
        t.Errorf("Output mismatch\nGot:\n%s\nExpected:\n%s", got, expected)
    }
}
```

### E2E with Playwright

For full browser testing of HTMX interactions:

```go
func TestBillToEmailFlow(t *testing.T) {
    page := browser.NewPage()
    page.Goto("http://localhost:8080/")

    // Click a bill
    page.Click("text=View Details")
    page.WaitForSelector("text=Contact Your Representatives")

    // Start email flow
    page.Click("text=Contact Your Representatives")
    page.Fill("input[name=zip]", "48226")
    page.Click("text=Find Representatives")

    // Verify reps loaded
    page.WaitForSelector("text=Your Representatives")
}
```

---

## Docker Gotchas

### Static Binaries for Alpine

Alpine uses musl libc. Dynamically linked binaries built on glibc systems (Ubuntu, Kali) won't run. Always build with:

```bash
CGO_ENABLED=0 GOOS=linux GOARCH=amd64 go build -o server ./cmd/server
```

Verify with `file server` — output must say `statically linked`.

### .dockerignore Can Silently Exclude Critical Files

If `server` (the binary) is in `.dockerignore`, `COPY server .` in the Dockerfile will fail with a confusing checksum error. Check `.dockerignore` before debugging build failures.

### Template Hot-Reload

Go parses templates at startup in `main.go`. Swapping template files on disk requires a container restart. If the server crash-loops due to bad templates, you can't fix it by copying new templates — the binary itself needs to match.

**Recovery pattern:** Build the binary locally (`CGO_ENABLED=0 GOOS=linux go build`), copy both binary + templates into the container via `docker cp`, then restart. Or rebuild the entire image.

---

## Architecture Decisions

### When to Use HTMX Over React SPA

Choose HTMX when:
- App is content-heavy or CRUD-heavy (dashboards, admin panels, blogs)
- Team is predominantly backend engineers
- You need fast Time-to-First-Byte (TTFB under 50ms)
- Simple interactivity (form submissions, tab switching, list updates)

Choose React/Next.js when:
- App is state-heavy (collaborative editors, complex visualizations)
- You need offline-first behavior or heavy browser API usage
- You need specific React ecosystem libraries

### Progressive Enhancement

Start with plain HTML forms. Add HTMX attributes incrementally:

1. Basic form submission (works without JS)
2. Add `hx-post` for AJAX submissions
3. Add `hx-target` for partial page updates
4. Add `hx-indicator` for loading states
5. Add SSE for real-time features

Each step is an enhancement, not a requirement.

### The "No-API" Architecture

With HTMX, you don't need a JSON API for your own frontend. Your Go handler returns HTML fragments directly:

```go
func (h *Handler) updateUser(w http.ResponseWriter, r *http.Request) {
    name := r.FormValue("name")
    user, _ := h.db.UpdateUser(name)
    components.UserProfile(user).Render(r.Context(), w) // Returns HTML, not JSON
}
```

Zero JSON. Zero client-side state management. Zero hydration errors.

Keep JSON API endpoints for mobile apps and external integrations, but don't build them for your own HTMX frontend.

---

## Sources

- [htmx.org documentation](https://htmx.org/docs/) — Official HTMX docs
- [htmx 4.0 docs](https://four.htmx.org/docs) — Latest HTMX with fetch-based AJAX
- [Go Frontend Architecture 2026](https://rajnandan.com/posts/go-frontend-architecture-2026/) — Templ vs React analysis
- [ThunderHooks: Go HTMX SaaS Stack](https://thunderhooks.com/blog/go-htmx-saas-stack) — Production patterns with SSE, SQLite
- [Go + HTMX Modern Web Apps](https://dasroot.net/posts/2026/04/go-htmx-modern-web-apps/) — Performance and architecture guide
- [Template Fragments essay](https://four.htmx.org/essays/template-fragments) — HTMX template fragment patterns
