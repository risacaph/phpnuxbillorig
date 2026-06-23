# Customer Password Hardening — Design Proposal (needs sign-off before code)

Status: **proposal only, no code.** Awaiting approval on scope (Phase A / B / C).

## 1. The problem

`tbl_customers.password` is stored in **plaintext**. Worse, that one column is
overloaded for two very different jobs:

1. **Portal login** — `Password::_uverify()` compares the typed password to the
   stored plaintext.
2. **Network credential** — the same value is pushed to the router and to
   RADIUS so the customer's device can authenticate:
   - `system/devices/MikrotikHotspot.php` and `MikrotikPppoe.php` set it as the
     hotspot/PPPoE user password via the Mikrotik API.
   - `system/devices/Radius.php` writes it to `radcheck` as
     **`Cleartext-Password`** (for PAP/CHAP/MS-CHAP).

A naive "just `password_hash()` it" **breaks job #2**: RADIUS CHAP/MS-CHAP needs
the cleartext (or a specific hash), and the Mikrotik API needs the cleartext to
provision the user on the router. So hashing must be done carefully, splitting
the two jobs apart.

Note: a `pppoe_password` column already exists and is preferred when set — the
architecture already half-separates the network secret.

## 2. Constraints (why this isn't a one-liner)

| Deployment | Where the password lives | Can we avoid cleartext at rest? |
|---|---|---|
| Mikrotik API (Hotspot/PPPoE devices) | On the router; app must send cleartext at provision time | Not fully — app needs recoverable secret → **encrypt at rest** |
| RADIUS (Radius/RadiusRest devices) | `radcheck` table | Partly — PAP/CHAP need cleartext; **MS-CHAPv2 can use `NT-Password` (a hash)** |

## 3. Proposed design — three phases

### Phase A — Hash the portal login (low risk, do first)
- Add column `tbl_customers.password_hash VARCHAR(255) NULL`.
- **Login:** if `password_hash` is set, verify with `password_verify()`; else
  fall back to the legacy plaintext compare **and** backfill `password_hash`
  (lazy migration), exactly like the admin bcrypt upgrade already shipped.
- **Password set/change** (`register.php`, `customers.php`, `accounts.php`,
  `forgot.php`): also write `password_hash`.
- `password` (plaintext) is **left untouched** so Mikrotik/RADIUS provisioning
  keeps working unchanged.
- **Result:** portal authentication no longer depends on plaintext. Zero RADIUS
  impact. This is the bulk of the security win at minimal risk.

### Phase B — Encrypt the network secret at rest (medium risk)
- Add column `password_enc` (AES‑256‑GCM ciphertext) and stop storing the
  network secret in plaintext.
- Add a small `Crypto` helper (`sodium_crypto_*` / `openssl` AES‑256‑GCM) keyed
  by a **dedicated key stored in `config.php`** (not the DB), so a DB-only leak
  cannot decrypt.
- Decrypt only at the point of use: the three device drivers above and any
  controller that needs the cleartext (voucher print, "show password", etc.).
- **Result:** a database dump alone no longer exposes network credentials.
- Cost: every read of `$customer['password']` as a *network secret* must route
  through decrypt; every write through encrypt. Requires an exhaustive sweep of
  `system/devices/*` and the credential-display paths, plus a one-time backfill.

### Phase C — Remove `radcheck` cleartext (deployment-specific, optional)
- For RADIUS deployments using **MS-CHAPv2/PEAP**, store `NT-Password` (MD4)
  instead of `Cleartext-Password`, so the radius DB holds no cleartext.
- **Breaks** PAP/CHAP and EAP methods that need cleartext — opt-in per install.

## 4. Migration & rollback
- Schema changes go through the existing mechanism: add the `ALTER TABLE`
  statements to `system/updates.json` (applied by `update.php` step 4, keyed by
  version) — **flagged as a schema migration** per the guardrails.
- Phase A keeps `password` populated, so rollback is trivial (just stop reading
  `password_hash`).
- Only after Phase B is verified in production would `password` be dropped.
- A one-time backfill command migrates existing rows.

## 5. Risks
- **Key management (Phase B):** if the `config.php` key is lost, network secrets
  are unrecoverable and customers must reset. Document key backup.
- **Driver coverage (Phase B):** missing a single decrypt site = auth failures
  for those customers. Needs careful review + a staging test against a real
  router/RADIUS before rollout.
- **Phase C** changes the RADIUS auth method — only for MS-CHAP installs.

## 6. Recommendation
Do **Phase A now** — it removes plaintext from the portal-login path with
effectively no RADIUS/Mikrotik risk, mirroring the admin bcrypt upgrade already
shipped. Schedule **Phase B** as its own carefully-tested change (it touches the
core network-provisioning path and the DB schema). Treat **Phase C** as an
opt-in for MS-CHAP RADIUS deployments only.

**Decision needed:** approve Phase A implementation (and whether to scope B/C in
now or later).
