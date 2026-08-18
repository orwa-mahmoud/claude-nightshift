# Example — an overnight webapp punch list

A filled, real-shaped `.nightshift/punch-list.md` for a small TypeScript web app, part-way through a
shift. It shows item anatomy: one top-level checkbox per task, plain sub-bullets, and every item
carrying its own **Verify** and **Commit**. The contract header is abbreviated here — `setup`
writes the full one.

---

> Contract (abbreviated): work items top to bottom, one at a time; run the item gate before each
> commit; tick only when the work is real; pushing is the owner's; park owner decisions; deletion
> is not completion; history is append-only on shift.

## Gates

- **Item gate:** `npm run lint && npx tsc --noEmit && npm test`
- **Site inspection (every 5 items):** `npm run test:coverage` — coverage is a tripwire, not a target.

## Items

- [x] **1. Scaffold the API server and health check.**
  - Express app, `/healthz` returns 200, wired into the dev script.
  - Verify: `npm test` covers the health route; item gate green.
  - Commit: `feat(api): server bootstrap + health check`

- [x] **2. User model + migrations.**
  - Prisma schema for `User`, first migration, seed script.
  - Verify: `npx prisma migrate deploy` on a scratch DB; item gate green.
  - Commit: `feat(db): user model and initial migration`

- [ ] **3. Signup + login endpoints.**
  - `POST /auth/signup`, `POST /auth/login`, bcrypt hashing, JWT issue. Rate-limit login.
  - Decision parked: token TTL — chose 24h access + 30d refresh as a sensible default; see
    `parking-lot.md`.
  - Verify: unit tests for happy path + wrong-password + duplicate-email; item gate green.
  - Commit: `feat(auth): signup and login with hashed passwords + jwt`

- [ ] **4. Session middleware + protected route.**
  - Verify JWT, attach user, guard `/me`.
  - Verify: tests for valid, expired, and missing tokens; item gate green.
  - Commit: `feat(auth): session middleware and protected /me`

- [ ] **5. Defect hunt — review, fix, re-review until it converges.**
  - Each cycle: review for defects; dedupe every finding against `snag-log.md` (all seen — fixed
    and rejected); fix each behind the item gate; append dispositions; re-review.
  - Stop at the first valid ending: a full pass finds nothing new (converged), or quitting time.
  - Verify: the item gate is green at every commit; snag-log dispositions are current.
