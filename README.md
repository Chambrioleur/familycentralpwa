# Familienzentrale

A self-hosted family organization PWA — calendar, tasks, shopping, finances,
school, documents, recipes, meal plan, and more.
Designed as a "tablet in the kitchen" hub, but works just as well on
iPhone, iPad, and desktop.

<a href="https://www.paypal.com/paypalme/cpoutdooradventure" target="_blank"><img src="https://img.shields.io/badge/PayPal-Donate-blue.svg?logo=paypal" alt="Donate via PayPal" height="28"></a>

## Features

- **Calendar** with bidirectional Apple sync (CalDAV), week/day/month views
- **Tasks** (Kanban) with priorities, recurring tasks
- **Shopping list** with autocomplete (learns new items permanently)
- **Finances** with CSV import (DKB-compatible), pie chart, category management
- **School** (timetable, grades, exams → automatically added to the calendar)
- **Recipes** + **Meal plan** (weekly grid, automatic calendar entries)
- **Documents**, **Knowledge**, **Health**, **Contacts**
- **Ideas & decisions** (voting with for/neutral/against)
- **Push notifications** (for due tasks/reminders + on creation)
- **Permission management** (configurable per person, including children)
- **Dark/light theme** (saved per person)
- **Language selector** (German/English, saved per person — German is the
  in-app default, switch anytime in Settings → General)
- **PWA** — no App Store needed, usable directly from the home screen

## Architecture

```
Frontend:  Single-file index.html (React + Supabase-JS via ESM/CDN)
Backend:   Supabase (PostgreSQL + Auth + Storage + Edge Functions)
Hosting:   Netlify (drag & drop, static files)
Sync:      Apple CalDAV (bidirectional)
```

## Requirements

- A [Supabase](https://supabase.com) project (free tier is enough)
- A [Netlify](https://netlify.com) account (free tier is enough)
- For Apple sync: an Apple ID with an [app-specific password](https://appleid.apple.com/account/manage)

---

## Setup (step by step)

### 1. Create a Supabase project

1. [supabase.com](https://supabase.com) → New Project
2. Region: pick whichever is closest to you
3. Note down:
   - **Project URL** (e.g. `https://abcdefgh.supabase.co`)
   - **anon public key** (Project Settings → API)
   - **service_role key** (Project Settings → API) — keep secret!

### 2. Set up the database

Open the SQL Editor and run the migration files **in numerical order**:

```
supabase/migrations/001_base_schema.sql
supabase/migrations/002_rls_policies.sql
supabase/migrations/003_schema_updates_base.sql
...
supabase/migrations/026_language.sql
```

> **Important:** keep the order! Each file builds on the previous ones.
> Files 023–024 (cron jobs) contain placeholders and are handled
> separately in step 8.

### 3. Create the storage bucket and enable Realtime

Two Supabase settings that aren't covered by the SQL migrations and are
easy to miss:

1. **Storage → New bucket** → name it `avatars`, mark it **public**. The
   migrations only set up the *access policies* for this bucket — without
   creating the bucket itself, profile picture uploads fail with a
   "bucket not found" error.
2. **Database → Replication** → enable Realtime for at least these tables:
   `calendar_events`, `tasks`, `shopping_items`, `reminders`, `members`.
   Without this, the app works fine but cross-device live updates don't —
   changes only show up after a manual reload.

### 4. Configure the frontend

The credentials don't live in `index.html` — they go in a separate
`config.js`, which is excluded from the repo via `.gitignore` so that no
project-specific values get committed.

```bash
cp frontend/config.example.js frontend/config.js
```

Then fill in your values in `frontend/config.js`:

```javascript
window.FZ_CONFIG = {
  SUPABASE_URL: "https://YOUR-PROJECT-ID.supabase.co",
  SUPABASE_ANON_KEY: "YOUR_ANON_KEY",
  VAPID_PUBLIC_KEY: "YOUR_VAPID_PUBLIC_KEY",   // see step 7
};
```

> If `config.js` is missing, the app shows a corresponding notice instead
> of the login screen.

### 5. Deploy to Netlify

1. [app.netlify.com](https://app.netlify.com) → Add new site → Deploy manually
2. Upload all four files from `frontend/` together:
   - `index.html`
   - `config.js` ← **don't forget this one**, it's not in the repo
   - `sw.js`
   - `_headers`
3. Note down your site's URL (e.g. `https://my-family.netlify.app`)

### 6. Deploy the Edge Functions

Deploy each function individually via the Supabase dashboard:

Dashboard → Edge Functions → Create new function → paste the code from:

| Function | File | Secrets needed |
|---|---|---|
| `manage-member` | `supabase/functions/manage-member/index.ts` | (none extra) |
| `reset-password` | `supabase/functions/reset-password/index.ts` | (none extra) |
| `send-push` | `supabase/functions/send-push/index.ts` | `VAPID_PUBLIC_KEY`, `VAPID_PRIVATE_KEY`, `VAPID_SUBJECT` |
| `check-due-notifications` | `supabase/functions/check-due-notifications/index.ts` | `VAPID_PUBLIC_KEY`, `VAPID_PRIVATE_KEY`, `VAPID_SUBJECT`, `CRON_SECRET` |
| `caldav-sync` | `supabase/functions/caldav-sync/index.ts` | `APPLE_ID`, `APPLE_APP_PASSWORD`, `APPLE_CALENDAR_NAME`, `CRON_SECRET` |
| `push-event` | `supabase/functions/push-event/index.ts` | `APPLE_ID`, `APPLE_APP_PASSWORD`, `APPLE_CALENDAR_NAME` |

> `SUPABASE_URL` and `SUPABASE_SERVICE_ROLE_KEY` are set automatically by
> Supabase — don't enter them manually.

### 7. VAPID keys (push notifications)

Push notifications need a VAPID key pair. Generate one once (e.g. via
[web-push-codelab.glitch.me](https://web-push-codelab.glitch.me)):

1. Public key → enter as the `VAPID_PUBLIC_KEY` secret on `send-push` and
   `check-due-notifications`
2. Private key → enter as the `VAPID_PRIVATE_KEY` secret
3. `VAPID_SUBJECT` → e.g. `mailto:your-email@example.com`
4. Also enter the **public key** in `frontend/config.js` under `VAPID_PUBLIC_KEY`

### 8. Set up cron jobs

Files 023–024 in `supabase/migrations/` contain placeholders. Before
running them, replace:

- `DEIN_ANON_KEY` → your anon public key
- `DEIN_CRON_SECRET` / `HIER_DEIN_CRON_SECRET_EINTRAGEN` → the same secret
  you entered as the `CRON_SECRET` secret on the functions
- the project URL → your actual Supabase URL

Then run them in the SQL Editor. To verify:

```sql
select jobname, schedule, active from cron.job;
```

### 9. Apple calendar sync (optional)

1. On [appleid.apple.com](https://appleid.apple.com), generate an
   **app-specific password**
2. Enter as secrets on `caldav-sync` and `push-event`:
   - `APPLE_ID`: your Apple ID (email)
   - `APPLE_APP_PASSWORD`: the generated password
   - `APPLE_CALENDAR_NAME`: the name of the shared calendar in Apple (e.g. "Family")

### 10. Create the first person

1. Open the app in a browser → the bootstrap form appears
2. Enter name, email, password → the first person is created as **master**
3. Add further people via Settings → People
   - Adults: email + password
   - Children: name + PIN (a synthetic email is generated automatically)

---

## Directory structure

```
familycentralpwa/
├── README.md
├── LICENSE
├── .gitignore
├── bank-import-example.csv  # Sample file for the Finances CSV import
├── frontend/
│   ├── index.html          # Complete app (single-file React)
│   ├── config.example.js   # Credentials template
│   ├── config.js           # Real credentials (not in the repo)
│   ├── sw.js               # Service worker (push notifications)
│   └── _headers            # Netlify cache control (no caching)
├── icons/
│   ├── icon-180.png        # Apple touch icon
│   ├── icon-192.png        # Android PWA icon
│   └── icon-512.png        # Splash screen / high-res
└── supabase/
    ├── migrations/
    │   ├── 001_base_schema.sql
    │   ├── 002_rls_policies.sql
    │   ├── ...
    │   └── 026_language.sql
    └── functions/
        ├── caldav-sync/index.ts
        ├── push-event/index.ts
        ├── check-due-notifications/index.ts
        ├── send-push/index.ts
        ├── manage-member/index.ts
        └── reset-password/index.ts
```

## Responsive breakpoints

| Device | Width | Navigation |
|---|---|---|
| iPhone | < 768 px | Mobile top bar + bottom tab bar |
| iPad | 768–1023 px | Compact icon rail |
| Desktop | ≥ 1024 px | Full sidebar |

## Known limitations

- Push on iPhone/iPad: only as a home-screen app, iOS 16.4+
- Recurring Apple events: imported as individual occurrences
- Single-file architecture: the entire app is one HTML file — works well,
  but doesn't scale indefinitely

## iOS PWA quirks

A few hard-won details, in case you're modifying the app:

- The PWA `status-bar-style` meta tag **must** be `"black"`, not
  `black-translucent`
- `100vh`/`100dvh` are unreliable in standalone mode, especially right
  after a cold start and when the keyboard shows/hides — the app measures
  the actual visible height in JS and exposes it as the `--app-height` CSS
  variable, re-measuring a few times in the first seconds after load
- Bottom tab bar: `position: fixed`, padding via `calc(64px + safe-area)`
- `body`/`html`: `overflow: hidden`, `height: 100%`

## Bank CSV import format

The Finances module's CSV import is tuned for German bank exports (built
against DKB's format) — see [bank-import-example.csv](bank-import-example.csv)
for a realistic example with fake data. It auto-detects:

- the delimiter (`;` or `,`)
- the header row, by skipping up to 15 leading meta lines (account name,
  date range, balance) until it finds a line matching known column names
- column meaning by matching header text against known German terms
  (`Buchungsdatum`/`Wertstellung`/`Datum`, `Betrag`/`Umsatz`,
  `Zahlungsempfänger*in`/`Auftraggeber`/`Verwendungszweck`,
  `Zahlungspflichtige*r`, `Umsatztyp`)
- German number format (`1.234,56` → `1234.56`) and flexible date formats
  (`DD.MM.YYYY` or `YYYY-MM-DD`)

For incoming payments, it prefers the `Zahlungspflichtige*r` (payer)
column over `Zahlungsempfänger*in` (payee) — otherwise you'd just see your
own name on every salary deposit. A bank export in a different format
will likely need adjustments to the `guessColumn()` candidate lists in
`frontend/index.html`.

## Internationalization (i18n)

UI strings live in the `TRANSLATIONS` object in `frontend/index.html`
(German is the source language and also the lookup key). Adding a new
module: wrap its strings in `t("German text")`; for sentences with
embedded values (numbers, names, dates), use
`tf("German {template}", { template: value })`. Database column names
stay German regardless of UI language — no schema change involved.
Deliberately not database-backed: this app has no build step and renders
synchronously, so a translations table would add a network round-trip
before the first render for no real benefit while only two languages
exist and the same person tends to maintain both code and copy.

## License

MIT — see [LICENSE](LICENSE).
