# Handoff Brief for Claude Code — Golden State Starlight Coalition

Read this file, `GoldenStateStarlight_WebApp_Spec.md`, and `GoldenStateStarlight_seed_data.json`
(all three should be in this same folder) before doing anything. This file is the
"current state + what to do next" briefing; the spec file is the detailed technical
reference; the JSON is the real data to seed the database with.

---

## 1. The Cause (context, not a build spec — for tone/framing only)

This is a California-wide grassroots advocacy effort to get **dark sky policy**
(outdoor lighting ordinances that reduce unnecessary night-time light pollution —
shielded fixtures, warmer color temperatures, lighting curfews) adopted by at least one
city or county government in **all 58 California counties**. Light pollution wastes
energy, disrupts nocturnal wildlife (birds, insects, migration cycles), affects human
sleep/health, and erases night-sky visibility — the coalition is building public
support, partnering with existing environmental orgs, and directly lobbying city
councils/county boards of supervisors.

Founder: Timothy Lee, currently working with a founding team of 4, planning to scale
via trained volunteers organized under partner organizations (Sierra Club chapters,
DarkSky International chapters, Audubon chapters, student/astronomy clubs, plus a
"general public" umbrella org for unaffiliated volunteers). The website is both a
public accountability tool (a map showing real progress, credited to real
organizations) and a private coordination platform for the volunteer network.

Working coalition name: **Golden State Starlight Coalition** (not fully finalized —
if it changes, do a find/replace, nothing else changes).

---

## 2. Current State (as of this handoff)

**Installed/set up locally:**
- Node.js ✅
- Claude Code ✅
- Project folder created, contains this file + the spec + the seed data JSON

**Accounts:**
- GitHub — account exists. **A repository for this specific project has NOT been
  confirmed created yet** — do this first (see §4).
- Netlify — account created/logged in via GitHub. **No site has been created/deployed
  yet.**
- Supabase — project already created:
  - Project URL: `https://tpjugbazpmcepiaqvjtx.supabase.co`
  - Publishable (anon) key: already obtained by the user — ask them to paste it when
    you set up the `.env` file, don't assume you have it.
  - **Important security note**: earlier in setup, the user accidentally pasted their
    *secret* key (prefix `sb_secret_`, the admin/bypass-RLS key) into a chat instead of
    the publishable key. They were told to regenerate/roll it in the Supabase dashboard.
    **Before using any secret key for anything, confirm with the user that it has
    already been rotated, and never write a secret key into any client-side/browser
    bundle code — publishable key only for the frontend.**
- Domain: not purchased yet. No rush — site can run on the free `*.netlify.app` URL
  until the coalition name is fully locked in.

---

## 3. What To Do Next (in order)

1. **Set up GitHub repo.** `git init` if not already, create a GitHub repository for
   this project (via `gh repo create` or by walking the user through it), and get an
   initial commit pushed.
2. **Scaffold the frontend.** React (Vite is a reasonable default) — this is a
   recommendation from earlier planning, not a hard requirement; use your judgment if
   something else fits better.
3. **Wire up Supabase.** Create a `.env` file (git-ignored) for the Project URL +
   publishable key. Ask the user directly for the publishable key value rather than
   assuming — do not use the secret key in this file.
4. **Write the database schema** (as SQL migrations) for: counties, cities,
   organizations, users, org roles/membership, chat channels, chat messages, and an
   audit-log/events table (see spec §3, §4, §6 for the exact fields these need to
   support). Apply via Supabase's SQL editor or CLI.
5. **Enable Row Level Security on every table**, with policies matching the role
   ladder in spec §3 (Super Admin → Sub-Admin → Org President → Org Officer → Org
   Member → Public). This is not optional — flag it to the user explicitly if you're
   tempted to defer it, since the publishable key is exposed client-side by design and
   RLS is the only thing standing between that and open read/write access to everything.
6. **Seed the database** from `GoldenStateStarlight_seed_data.json` — this has the full
   58-county / 482-city list, priority tiers, selected priority cities, sourced
   professional + student org contacts, and email templates already researched and
   fact-checked. Use it instead of starting from empty tables.
7. **Build the public map** — see spec §4 for full detail: Census TIGER/Line county +
   city boundary data, all-white/neutral default coloring with status-based color
   overlay, hover popup (county name, status, participating orgs w/ hyperlinks, button
   to county page).
8. **Build county pages** (one per county) — city sub-map, per-city progress pipeline
   (Not Started → Contacted → Meeting Scheduled → Ordinance Drafted → Passed →
   Enforced), ordinance summary + linked legal text, org credit list, running
   timeline/news feed backed by the audit-log table.
9. **Build accounts/auth** via Supabase Auth, enforcing the role ladder, with an
   explicit "Transfer Presidency" action for Org Presidents and a Sub-Admin approval
   step for a *new* org's first President.
10. **Build chat** — one statewide channel + one channel per county (58), powered by
    Supabase Realtime (not a separate chat service), no 1:1 DMs, bot + admin
    moderation on the statewide channel, 1-year message retention with scheduled
    auto-delete after that.
11. **Deploy to Netlify** — connect the GitHub repo, add the same Supabase URL +
    publishable key as Netlify environment variables (separately from the local
    `.env`), deploy. Confirm the live `*.netlify.app` URL works end-to-end before
    telling the user it's done.
12. **Custom domain** — once the coalition name is fully finalized and a domain
    purchased, connect it under Netlify's Domain settings. Not urgent.

---

## 4. Full Technical Spec

See `GoldenStateStarlight_WebApp_Spec.md` in this same folder for the complete detail
behind every item above — tech stack rationale, full role/permission model, exact map
and county-page requirements, chat architecture, content governance rules, and
succession-planning requirements. Treat that file as the source of truth for anything
this brief only summarizes.

## 5. Data

See `GoldenStateStarlight_seed_data.json` in this same folder — structured data ready
to seed the initial database tables (§3/§6 above), already researched and fact-checked
across all 58 California counties.
