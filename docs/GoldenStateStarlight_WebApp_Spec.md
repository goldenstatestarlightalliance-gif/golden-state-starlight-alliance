# Golden State Starlight Coalition — Web App Build Spec
*(working name — swap throughout if you land on something else)*

Target launch: **live by August 2026**. Handoff target: Claude Code.

---

## 1. Mission & Scope Recap

A public-facing California dark sky policy tracker + a private member coordination
platform, serving one coalition made up of partner organizations (Sierra Club chapters,
DarkSky International chapters, Audubon chapters, student/astronomy clubs, and a
"general public" umbrella org for people not affiliated with any named partner).

Two halves:
- **Public side**: interactive CA county map, per-county pages, ordinance tracking, org credit.
- **Private side**: accounts, org-based roles, statewide + per-county group chat.

---

## 2. Recommended Tech Stack

| Layer | Tool | Why |
|---|---|---|
| Hosting | **Netlify** | Free tier, instant deploys, custom domain support |
| Backend / DB / Auth | **Supabase** | Postgres + built-in Auth + **Realtime** (use Supabase Realtime/Postgres changefeeds to power chat — avoids building raw WebSocket infra from scratch, which is the highest-risk part of a custom build) |
| Map rendering | Leaflet or Mapbox GL JS with GeoJSON | Both handle hover states, click-through, and dynamic per-feature coloring well |
| Frontend | Whatever framework Claude Code defaults to (React is a safe, well-supported choice given Supabase's SDK support) | |

**Domain**: not yet owned. Suggest checking availability on: `goldenstatestarlight.org`,
`gsstarlight.org`, `calstarlightcoalition.org` (once the name is fully locked in — this
doc uses the working name throughout, update once decided).

**Budget**: founder can self-fund some costs; also pursue in-kind or funding support from
DarkSky International, Audubon, and Sierra Club chapter contacts already in the outreach
list. Flag for Claude Code: at "hundreds–thousands of users" scale with custom-built,
1-year-retained chat, you will likely outgrow Supabase's free tier (database size +
concurrent realtime connections) — budget for a paid tier before launch, not after
something breaks.

---

## 3. Roles & Permissions

```
Super Admin (founder)
 └── Sub-Admins (3 — see suggested titles below)
      └── Org President (one per participating org, incl. the coalition's own
           "general public" umbrella org)
           └── Org Officers (titled by that President — see suggested titles below)
                └── Org Member (general)
Public / Unverified visitor — can view all public pages, can create a basic account
 to join the umbrella "general public" org for participating in coordinated public
 comment campaigns without being tied to a named partner org.
```

**Suggested Sub-Admin titles** (3, matching the coalition's actual workload):
1. **Sub-Admin, Technology & Platform** — owns the website/map/data accuracy, bug triage, county boundary data updates.
2. **Sub-Admin, Partnerships & Outreach** — owns relationships with DarkSky/Sierra Club/Audubon chapters, recruits new partner orgs, approves new Org Presidents.
3. **Sub-Admin, Policy & Research** — owns ordinance-tracking accuracy, verifies county progress-stage claims, maintains the pipeline definitions.

**Suggested Org Officer titles** (Org President can rename/add, this is a starting template):
- Lead Researcher
- Outreach Coordinator
- Communications Lead
- County Liaison (point person for one specific assigned county)
- Secretary (notes/record-keeping)

**Org President verification**: manual approval by a Sub-Admin the first time an
organization joins. After that, the sitting President can transfer the title to a
successor within their own org (self-service, no re-approval needed) — build this as
an explicit "Transfer Presidency" action, not a hardcoded single owner.

**The "one big California organization"**: build this as a real Org record like any
other (not a special case in the data model), so general public members can join it and
its channel/comment campaigns exactly like members of a named partner org.

---

## 4. Map & County Pages

**Boundary data**: pull from the **US Census Bureau TIGER/Line or Cartographic Boundary
Files** (census.gov/geographies/mapping-files) — this is the most authoritative, free,
public-domain source, available for both counties and incorporated places (cities).
Filter to California's 58 counties + the ~482 incorporated cities. This satisfies "most
specific public source possible."

**Statewide map**:
- All counties rendered in **white/neutral by default** (per your instruction — color
  is applied dynamically based on status, not baked in).
- Color-per-status palette (proposed, since none was specified beyond "white for now"):
  - Not Started → white/light gray
  - Contacted → pale yellow
  - Meeting Scheduled → orange
  - Ordinance Drafted → light green
  - Passed → dark green
  - Enforced → deep teal/blue-green (a distinct "done and verified" tier)
- **Hover interaction**: hovering a county shows a popup with county name, current
  status, and the list of actively participating orgs for that county, each hyperlinked
  (website and/or email), plus a button through to the full county page.

**County page** (one per county, ~58 total):
- Sub-map of that county's cities, same status-pipeline coloring, using the Census
  Places boundary data.
- Per-city progress using the fixed pipeline: **Not Started → Contacted → Meeting
  Scheduled → Ordinance Drafted → Passed → Enforced.**
- Ordinance section: **both** a summary (date passed, plain-language description) *and*
  a link to the actual legal text/PDF.
- Full org credit list for that county, each org hyperlinked.
- **Running timeline/news feed** of updates for that county (not just a current
  snapshot) — model this as an append-only events table (timestamp, actor, change
  description) so the timeline view and the audit log (below) can share the same data.

**Access**: map and all county pages are **fully public**, no login required to view.
Editing requires an account with the right org/role permission (see §3, §6).

---

## 5. Chat / Messaging (custom-built, engineered for scale from day one)

- **Channel structure**: one statewide "California" channel (giant, all members) + one
  channel per county (58 total). *(Your original ask also mentioned org-internal
  messaging — if you still want a private channel per organization in addition to the
  county channels, flag it; otherwise county channels double as the collaboration space
  for orgs working that county.)*
- **No direct messages (1:1) built into the platform** — group/channel-based only, per
  your answer. If two members want to talk privately, that happens outside the platform.
- **Moderation**: automated bot moderation (spam/profanity filtering) on the statewide
  channel, plus human moderation by Sub-Admins or an assignable Moderator role.
- **Retention**: 1 year of message history, then scheduled auto-delete (build this as a
  recurring job, not a manual task).
- Build on Supabase Realtime (Postgres-backed) rather than a separate chat service —
  it's designed for exactly this and avoids standing up independent WebSocket
  infrastructure.

---

## 6. Content Governance

- **No approval step** for an org editing their own county contributions — full
  trust-based editing once someone has the role.
- **Full audit log required**: every edit (who, what, when, before/after) logged and
  viewable by Sub-Admins+, both for accountability and to power the county timeline/news
  feed (§4).
- Process note (not a build item): founder will run periodic small trust-based check-ins
  (e.g., 1-on-4 meetings) with people granted edit access, rather than a formal review
  workflow — the audit log is what makes that light-touch approach safe.

---

## 7. Succession Planning

- Super Admin role must be **explicitly transferable** in the data model (not hardcoded
  to one account) — same pattern as Org President transfer in §3.
- Founder's stated intent: when stepping back (e.g., graduating), hand off to trusted
  people already identified, potentially formalized via an **in-platform leadership
  poll** conducted in the statewide channel. Worth building a lightweight poll/voting
  feature to support this if time allows — not core MVP, but flag it as a
  near-term-post-launch feature so the data model doesn't have to be reworked later to
  support it.

---

## 8. Open Items / Still Needs a Decision

- Final coalition name (currently placeholder "Golden State Starlight Coalition").
- Domain registration (pick + purchase once name is locked).
- Confirm whether per-organization private channels are wanted *in addition to* the
  county channels (see §5 note).
- Exact wording/design of the status color palette beyond the proposed defaults in §4.

---

## 9. What's Already Built (hand these to Claude Code alongside this spec)

- Full 58-county / 482-city list.
- Priority tiers (1–5) and rationale per county.
- Selected priority city/cities per county.
- Sourced professional-org and student-org contacts per county (with corrections
  applied — e.g., defunct/misnamed chapters already caught and fixed).
- Email outreach draft templates per county.
- All of the above as structured data (JSON) that can seed the initial Supabase tables
  for counties, cities, orgs, and progress status rather than starting from a blank
  database.
