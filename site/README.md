# Desktop Buddy website

Next.js (App Router), exported as plain static files. No CSS framework.

- `npm install` once, then `npm run dev` to preview at http://localhost:3100
- `npm run build` writes the finished site to `out/`. Upload that folder to any static host.

Pages: `app/page.tsx` (home), `app/get-started/`, `app/privacy/` (the app's own privacy notice).
Links, version and contact email live in `lib/site.ts`. Screenshots are in `public/shots/`.
