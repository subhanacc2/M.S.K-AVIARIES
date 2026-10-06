# Aviary: Parrot Breeding Program Website

A free, public-facing record of your birds, pairings and lineage, with a private admin panel for prices and buyer/seller contacts.

## Files
| File | Purpose |
|---|---|
| `parrot_schema.sql` | Database: birds, pairings, clutches, photos, private data, automation, security |
| `parrot_schema_part2.sql` | Focused public lineage, origin story, breeder history, lines carried |
| `index.html` | The whole website (single file) |
| `README.md` | This guide |

## Free stack
Supabase free plan (database, login, photo storage) plus Cloudflare Pages or Vercel free tier (hosting). The free Supabase plan pauses a project after about 7 days of inactivity (data is kept). Open the admin page at least weekly, or restore the project from the dashboard.

## Setup (about 15 minutes)
1. Create a free project at supabase.com.
2. SQL Editor: run `parrot_schema.sql`, then `parrot_schema_part2.sql`, then `parrot_schema_part3_privacy.sql` (hides ring numbers from the public site). Or run `npm run db:apply` with `DATABASE_URL` set. Optional legacy step if you skipped part 1 video column:
   ```sql
   alter table birds add column video_url text;
   create or replace view public_birds as
     select id, name, species, sex, ring_number, hatch_date, phenotype, genotype, status,
            origin_description, bred_by, line_name, video_url from birds;
   ```
3. Authentication > Users: add your own admin user (email + password). Then Authentication > Sign In / Providers: **turn off "Allow new users to sign up"**. This keeps you the only admin.
4. Project Settings > API: copy the **Project URL** and the **anon public key**.
5. Open `index.html` and paste them into `C` at the top of the script (`SUPABASE_URL`, `SUPABASE_KEY` — use the **publishable/anon** key only, never the secret key). Also set `NAME`, `TAGLINE`, and optionally `LIVE_URL` (a YouTube live or video link) for a "Live now" section.

**M.S.K Aviaries:** Admin sign-in uses username `admin` (stored as `admin@mskaviaries.com` in Supabase Auth). To re-run schema on the hosted database: set `DATABASE_URL` and run `npm run db:apply`.
6. Upload `index.html` to Cloudflare Pages or Vercel (drag and drop). Done.

With the URL left empty the site runs in **demo mode** with sample cockatiels, so you can preview the look first.

## What the site does
**Public**
- Animated shader background and a 3D orb (three.js), responsive and reduced-motion friendly.
- Searchable gallery of birds with photos; tilt-on-hover cards.
- Bird page: photo gallery, video (YouTube or mp4), species, ring, phenotype, genotype, bred-by, auto-written description, lines carried, breeders before.
- Lineage diagrams (clickable nodes): **Origin** (the bird's parents and its siblings from that pairing only) and **Current pairing** (partner plus chicks of that pair only), grouped by clutch.

**Admin (login at `#/admin`)**
- Add, edit and delete birds, pairings, clutches, breeder history and private details.
- Upload photos (auto-resized, about 200 to 300 KB each) and add video links.
- Export every table to CSV (your backup).

## Automation built into the database
- Pairing a bird with a new partner automatically ends its old pairing.
- A bird can be in only one active pairing; sexes are validated.
- A chick saved with a clutch gets its father and mother filled in from that pairing, permanently.
- Siblings, half siblings and children are derived, never typed by hand.
- Lines carried are inherited from ancestors (up to 4 generations) unless you type one.

## Privacy model
- Public visitors cannot read the raw tables. They only receive what `public_bird_profile` returns: the bird (without ring number), line names, its own origin pair and siblings, its current pair and chicks (with **lines crossed** on each pairing), and past pairings you tick "show after end" on.
- **Ring numbers** are admin-only (full `birds` table when logged in). Public listings and lineage diagrams show **line names** instead.
- Prices, buyer/seller names and phone numbers live in `bird_private`, readable only when logged in.
- A chick's own page always shows its two parents, so a past pairing is visible on that pair's chicks.

## Daily use
1. Add each bird (species, genotype, phenotype and ring are free text; write "no ring" if none).
2. Create a pairing (male + female). Re-pairing later closes the old one automatically.
3. Add a clutch to the pairing, then add chicks and pick that clutch. Parents fill in themselves.
4. Add breeder history and private contact details as needed.

## Not included yet
Sale pages, a genetics outcome calculator, and a full-family (all pairings) diagram in the admin panel. The database already supports the last one through `family_tree()`.

## Troubleshooting
- **Blank bird page:** check the SQL files ran in order, and that the video_url step was run.
- **Cannot save:** the red message shows the database's reason (for example, wrong sex for a pairing).
- **Photos not showing:** confirm the `bird-photos` bucket exists and is public.
