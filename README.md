# CreaseOne — Flutter mobile app

Cricket scoring app for Android/iOS, built on the same backend as the `cricketTicker` web app
(`crickDbModule`, Cloud Run). Everything from the web app except the broadcast/ticker graphics console.

- **Package / application ID:** `com.creaseone.cticker`
- **API:** `https://crickdbmodule-api-144271912366.asia-south1.run.app/api` (override with `--dart-define=API_BASE=...`)
- **Live updates:** WebSocket `wss://<api-host>/live`

## Modules

| Area | What's included |
|---|---|
| Auth | Google Sign-In (native account picker), email sign-in / sign-up, first-login role + profile completion, match-scoped scorer login |
| Matches | Live / Upcoming / Results feed, open by Match #, create / edit / delete match, share score |
| Match centre | Live score, crease, this over, last wicket, full scorecard (FOW, extras, yet to bat), ball-by-ball commentary, insights (worm, manhattan, run rate, partnerships, scoring breakdown, dismissals, wagon wheel, fastest 50/100), info & Playing XIs |
| Scoring console | Playing XI (C / WK / batting order) → toss → openers; runs 0–6 + custom, wide / no-ball (bat/bye/LB) / bye / leg-bye, overthrows, all dismissal types incl. multi-fielder run outs and retirements, new batter & strike choice, end-of-over bowler pick with quota, swap strike, undo, wagon-wheel capture, change bowler mid-over, replace batter, end innings / declare, follow-on, 2nd/3rd/4th innings, reduce overs (pro-rata / DLS / VJD / manual target), intervals, penalty & bonus runs, impact player, concussion sub, DRS, captain/WK change, score note, super over / tie, abandon / walkover / delay, scorer access sharing, scoring lock |
| Tournaments | List, create / edit (format, ball, pitch, points, playing conditions), teams, schedule, points table (groups + NRR), stats & leaderboards |
| Teams | List, create / edit (logo, colour), squads per tournament, add players from registry, captain / WK |
| Players | Search by name / mobile / email / ID, create / edit with photo, career & per-tournament batting/bowling stats |
| Profile | Edit name/mobile, plan, link to own player stats, sign out |

Scoring is server-authoritative: the app posts each delivery to `POST /balls` (same payload as the web
ControlPanel) and re-reads `GET /matches/:id/snapshot`, so web and mobile can score/follow the same match.

## Google Sign-In setup

The backend verifies Google ID tokens against the **Web** client ID
(`144271912366-iumk5ougdp8ub5g2cqv5beu58ifid7qj...`). The app requests tokens for that audience via
`serverClientId`; the **Android** OAuth client (`144271912366-6ppg3st38oslpev4i21cr6jta9ornbjd...`) is
matched by Google Play services using package name + signing-certificate SHA-1. No client secret is used
or needed on Android.

In Google Cloud Console → APIs & Services → Credentials → the Android client, make sure:

- Package name: `com.creaseone.cticker`
- SHA-1: the certificate that signs the build you install
  - Debug keystore on this machine: `F7:32:50:64:DC:04:5C:E5:B3:91:18:6B:83:55:56:17:5A:92:B2:F9`
  - Add your release / Play App Signing SHA-1 too before publishing.

If sign-in returns `ApiException: 10` / DEVELOPER_ERROR, the SHA-1 or package does not match.

## Run

```bash
flutter pub get
flutter run
```

Against a local backend from the Android emulator:

```bash
flutter run --dart-define=API_BASE=http://10.0.2.2:8080/api
```

Release build (configure a release signing key in `android/app/build.gradle.kts` first):

```bash
flutter build appbundle
```

## Code layout

```
lib/
  core/        config, theme, cricket rules & formatting
  data/        Dio client, CreaseApi (all endpoints), JSON view models (Snapshot, MatchView…)
  services/    auth (Google / email / scorer), live WebSocket
  widgets/     shared UI (match card, avatars, pickers, image upload)
  features/    auth, home, tournaments, teams, players, matches (centre, scorecard, commentary, insights),
               scoring (setup, console, wicket/wagon sheets, match-control actions), profile
```
