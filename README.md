# GPS Gap Backfill & Billable Distance Reconstruction

**Author: Rakesh Prasad** | MoveInSync SDE case study | Python / FastAPI

I implemented a service that cleans unreliable GPS evidence, inserts justified rider and
office anchors, routes genuine gaps, and explains every segment of the resulting distance.
Calculations are versioned. Provider outages produce provisional estimates and durable
recovery work. Late evidence after invoice closure produces a signed adjustment ledger.

**Default road distances are synthetic.** The mock uses an L-shaped grid for reproducible
tests and the demo. An OSRM HTTP adapter is supplied and HTTP-contract tested with mock
responses; no live OSRM/map-dataset validation is claimed. A reconstructed route is not
proof of the exact route driven.

## Start on Windows - no Docker required

1. Install Python **3.12** from [python.org](https://www.python.org/downloads/windows/).
   Select **Add Python to PATH**. The Python 3.12.10 Windows installer is one available
   3.12 installer; the recorded Linux measurements used 3.12.14.
2. Extract the ZIP. Open the folder containing `app`, `README.md` and `start-windows.bat`.
3. Double-click **start-windows.bat**. The first run creates `.venv` and installs dependencies.
   Internet access is needed for that installation, not for the mock routing demo.
4. Leave the terminal open. Visit **http://127.0.0.1:8000/docs**.
5. Use `POST /auth/token`, click **Try it out**, and submit:

```json
{"username":"admin-a","password":"DemoPass123!"}
```

6. Copy only the `access_token` value. Click **Authorize** near the top of Swagger and
   paste the token. Do not paste the surrounding quotation marks.
7. Use `POST /api/trips`, paste the contents of **fixtures/trip.json**, and click Execute.
8. Use `POST /api/trips/{trip_id}/calculate` with **DEMO-01**. Inspect the returned
   `qualityStatus`, `calculatedTotalKm`, `segments`, `rejectedPoints` and `routing`.

The sample produces **10.87 km**, using the shipped synthetic provider and default rules.
Repeated calculation returns the same calculation ID. This is a measured fixture result,
not the assignment's separate 30.6 km example.

To run the full demonstration, open a **second PowerShell window** in this folder and run:

```powershell
.\.venv\Scripts\python.exe -m scripts.demo
```

The script creates uniquely named demo trips, checks all responses, injects a provider
failure, restores it, waits for automatic recovery, and saves a token-free transcript.
Do not run it against a non-demo deployment.

## One-command Docker startup

Install Docker Desktop, start it, and run from this folder:

```bash
docker compose up --build
```

Visit http://localhost:8000/docs. SQLite is stored in the `gps-data` Docker volume,
so ordinary container restarts preserve evidence. `docker compose down` stops the app;
do not add `-v` unless you intentionally want to delete demo data.

The Docker configuration is provided but was **not executed in the build environment**,
which had no Docker daemon. Local Python startup, HTTP flows and persistence were executed.

## Manual setup on Linux / macOS

```bash
python3.12 -m venv .venv
source .venv/bin/activate
python -m pip install -r requirements.txt
python -m uvicorn app.main:app --host 127.0.0.1 --port 8000 --no-access-log
```

Run one API process for this prototype. The cache and breaker are process-local; SQLite
is a single-writer database. Do not claim horizontal scaling by adding multiple workers.

## Demonstration and design

- [Recorded API demonstration](docs/demo.mp4) - rendered from captured, asserted live HTTP responses.
- [Exact demo transcript](docs/demo-transcript.json) - tokens redacted; only synthetic coordinates.
- [Concise design note](docs/design-note.pdf) - architecture, sequence and failure modes, two pages.
- [Design note source](docs/design-note.md).
- [Implemented case study report](docs/case-study.pdf).
- [Beginner's run and GitHub guide](docs/START_HERE.md).

The supplied `fixtures/postman_collection.json` can also be imported into Postman. It contains login, calculation, billing, outage and recovery requests.

## API surface and accounts

| Endpoint | Role | Purpose |
|---|---|---|
| `GET /health` | Public | Readiness summary without trip data |
| `POST /auth/token` | Public | 30-minute signed JWT; login rate limit |
| `POST /api/trips` | Operator/admin | Create or submit a revised full snapshot |
| `POST /api/trips/{id}/pings` | Operator/admin | Append late pings idempotently |
| `POST /api/trips/{id}/calculate` | Operator/admin | Calculate or replay the immutable current result |
| `GET /api/trips/{id}/result` | Authorized user | Current result; optional `calculation_id` for history |
| `POST /api/trips/{id}/invoice` | Admin | Close an eligible current calculation |
| `GET /api/trips/{id}/invoice` | Operator/admin | Original invoice plus signed distance adjustments |
| `GET /api/metrics` | Admin | Pending work, lag, errors, latency, provider and cache counters |
| `POST /api/demo/provider` | Demo admin only | Inject/restore a synthetic provider outage |

Demo accounts: `admin-a`, `operator-a`, `employee-a` (tenant A), and `admin-b` (tenant B).
All use `DemoPass123!`. Employee A can read only trips listing `employee-a` in `employeeIds`,
and receives a restricted summary rather than other riders' evidence. Tenant is derived
from verified JWT claims plus the stored user, never a caller-supplied tenant parameter.
Known demo passwords and the demo JWT key must not be exposed as production credentials.
`DEMO_MODE=false` disables demo controls and user seeding and requires a private JWT key;
full production user provisioning, TLS termination and secret rotation remain outside scope.

## Core rules and assumptions

1. Retain immutable raw snapshots. Normalize timestamps to UTC, deduplicate and sort.
2. Drop invalid coordinates, missing/negative accuracy, accuracy above **50 m** (configurable),
   and device jumps above **120 km/h**. Stable IDs make duplicate selection deterministic.
3. Use actual rider event coordinates/time; otherwise planned location/time for planned riders,
   or profile home/sign-in time for ad-hoc riders. No-show anchors are configurable, OFF by default.
4. Use actual trip-end location within **400 m inclusive** of the office; otherwise planned office.
   This prototype explicitly implements **OFFICE_TERMINAL** trips. The brief's logout example
   requires direction clarification before general home-bound trips can be supported safely.
5. For `elapsed < 70 seconds` and plausible speed, use aerial distance. For longer gaps whose
   endpoint speed is `< 5 km/h`, use PARKED. This heuristic can miss loops.
6. Otherwise route. Reject distance `>100 km`, or when **both** routed speed and
   `1.4 * aerial` speed exceed the limit. A high-route-speed-only exception is retained but flagged
   for billing review. Equality boundaries are tested.
7. Provider failure uses `1.4 * aerial`, marks DEGRADED and schedules recovery. Impossible
   fallback values are held for review. No-route/invalid route is not disguised as zero distance.
8. Store integer millimetres, round every distance to that precision with HALF_UP, sum integers,
   then display two-decimal kilometres. Signed displayed deltas reconcile to invoice totals.

The first GPS fix can be unreliable if no valid start anchor exists. The last-accepted-point
filter is deliberately simple; missing start coverage and timestamp conflicts block automatic billing.
Profile/planned snapshots and synthetic routing cannot prove actual driving behavior.

## Cost, failure and determinism

Directional cache keys contain tenant, provider/map epoch, snapping version and start/end cells.
The grid is 0.0001 degrees, with exact decimal rounding to canonical centres. Explicit aerial
connectors restore endpoint offsets. Nearby parallel roads can still be ambiguous. OSRM waypoint
snap offsets above 50 m are rejected. Use an explicit map epoch with a real provider.

The cache has 20,000 entries, LRU eviction and 24-hour TTL. Route outcomes selected for a
calculation are frozen in its segment records and result; hot-cache expiry does not change old
results. Up to 64 unique misses per calculation are budgeted, with batches of 25 for providers
that support pair batches. Mock batches count as **simulated** requests. OSRM uses individual
Route requests; it does not pretend that an N*N matrix is a cheap pair batch.

The breaker opens after five failed batches. Production-style reset is 30 seconds; demo reset
is five seconds. OSRM calls time out after two seconds and retry once; retries are counted.
The single-process lock prevents a routing stampede but serializes routing and limits throughput.

SQLite transactions atomically save evidence plus a work flag. Workers acquire expiring,
300-second leases with increasing fencing tokens, call the provider outside transactions,
then publish only under the current fence. Newer input cannot be overwritten by older work.
An abrupt process crash leaves durable work, reclaimed after lease expiry. A normal exception
releases the lease and schedules a retry. Repeated requests reuse completed calculations.

Recovery creates a new route-evidence generation. The original fallback result remains available.
A closed invoice's base is immutable; new eligible results append a unique plus/minus distance
delta relative to the effective recorded distance. This is an audit ledger, not money transfer.
Exactly-once publication does not guarantee exactly-once external provider charging after a crash.

## Tests

On Windows, double-click `run-tests-windows.bat`, or run:

```powershell
.\.venv\Scripts\python.exe -m pytest -q --junitxml=docs/test-results.xml --cov=app --cov-report=term-missing
```

On an activated environment use `python -m pytest -q`. The repository contains exact test output
and coverage data. Tests cover threshold boundaries, cleaning, anchor fallbacks, no-shows, the
office rule, replay, concurrent workers using real SQLite transactions, lease fencing, crash
rollback, partial provider failure, recovery, signed deltas and tenant/role isolation.
An upstream Starlette/httpx deprecation warning does not affect the passing assertions.

## Benchmarks

```powershell
.\.venv\Scripts\python.exe -m bench.run --trips 10000 --pings 1500
```

This performs **two 15-million-ping runs**: healthy and provider failure after trip 5,000.
It also measures cache-disabled/cold/warm routing lookup counts. The generator is deterministic,
uses twelve repeat corridors and injects duplicates, bad accuracy, a teleport and two gaps per trip.
The core run includes full segment-output generation. It excludes HTTP, JWT and database work.
The breaker clock in that benchmark is virtual (10 ms/trip, one-second open interval), while
reported runtimes and latencies use the actual wall clock. Provider latency is zero in the mock.

For an independent real HTTP + persistent-database run with the app running:

```powershell
.\.venv\Scripts\python.exe -m bench.http_run --trips 100
```

Or `python -m scripts.validate_live --http-trips 100` starts its own temporary localhost server,
runs the asserted demo, benchmarks it and shuts it down. See **bench/results/** for exact results,
machine details and method. Do not compare core-only latency to end-to-end latency as if identical.
The recorded runs are single-run observations on a shared Linux environment, not production SLAs.

### Recorded results (31 October 2026)

| Run | Trips / pings | Wall time | p50 / p99 per-trip calculation | Peak RSS / errors |
|---|---:|---:|---:|---:|
| Healthy core | 10,000 / 15,000,000 | 153.25 s | 13.102 / 34.762 ms | 23.25 MiB |
| Halfway-outage core | 10,000 / 15,000,000 | 140.212 s | 12.61 / 26.843 ms | 23.25 MiB |
| HTTP + SQLite | 100 / 150,000 | 11.711 s | 61.559 / 218.395 ms | 0 errors |

Automated suite: **45 passed**, **96.17%** statement coverage. Core throughput:
**65.25 trips/s**. Halfway-outage status counts: 5,000 COMPLETE,
5,000 DEGRADED. Cache component: 10,000 lookups require 10,000 simulated requests disabled,
12 cold, and 0 warm. RSS uses the OS process high-water mark and includes prior work within
that process. CPU: INTEL(R) XEON(R) PLATINUM 8573C; reported logical CPUs: 9;
reported memory: 9.73 GiB; Python 3.12.14.



## Complexity and scale limits

For n pings and a anchors: O((n+a) log(n+a)) time for sorting and O(n+a) memory. The remaining
cleaning/segment work is linear; routing cost depends on unique uncached pairs. Streaming trips
keeps memory independent of the number of trips, apart from the bounded cache and small metrics.
Database storage grows with evidence and calculation revisions. SQLite write serialization,
JSON snapshot volume, synchronous HTTP response size and serial provider batches limit scale.
I would migrate the repository layer to PostgreSQL and introduce a dedicated distributed work
queue/cache only after measuring those bottlenecks. Full-trip snapshot retention is not optimized.

## Failure and privacy notes

Logs contain trace IDs, route templates, status and timings, not request bodies, coordinates,
tokens or employee contact information. Error responses omit raw input values. All checked-in
fixtures are synthetic. Metrics expose pending work, oldest pending age, expired leases,
error rate, rejections, cache activity, provider requests/retries and recent HTTP p50/p99.
Application-side tenant filtering is tested; SQLite has no PostgreSQL-style row-level security.
The app is bound to localhost in the documented demo and Docker port mapping.

## Submission

The included local Git repository contains incremental commits from design through tests,
benchmarking and documentation. Push the extracted repository using Git (see START_HERE);
uploading all files through GitHub's browser UI loses that local history. Use a public repository
as requested by the assessment, verify the demo/report links, and submit the repository URL.
The code is meant to be read and defended: run the demo and tests on your own computer before
the interview and understand the assumptions above.
