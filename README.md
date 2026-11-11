# Sidekick

**Stay in the talk. Your sidekick works the room.** At every event you have to choose between the main event and networking. Sidekick sends your sidekick in for you: check in to an event (or a place, like a coworking space), and it scouts everyone there and ranks who is worth meeting, based on what each person is looking for and can offer. You swipe **Connect** or **Pass**. When you both connect, it's a match: you swap contact details and get an opener for the break. Nobody sees who passed, or who connected with them before it's mutual.

**Guests** can fill in a profile, check in and see who their sidekick picks without signing in, on Android or on the web. To swipe, they sign in with Google, and everything they did as a guest carries over.

## Stack

Everything runs on AWS, in one CDK stack.

| Part | Where | What |
|---|---|---|
| App | `app/` | Flutter: the same app is the Android app and the website at sidekick.artifisi.com. Light is Pine green on warm paper, dark is Oat on deep Pine (each person picks, the admin sets the default). Signal orange is the accent. |
| Identity | Cognito identity pool | A guest gets an unauthenticated identity. Google sign-in is linked to that same identity, so a guest keeps their data. Both get short-lived AWS credentials that can only call the API. |
| API | API Gateway (HTTP API, IAM auth) → Lambda (`backend/src`) | One Node 22 Lambda. API Gateway checks each request's signature and tells the Lambda who is calling and whether they're a guest. |
| Data | DynamoDB (one table, on demand) | Profiles, events, attendee cards, swipes, matches, the agents' exchange for each match (kept with the match), notes for the Alerts and Messages tabs, messages, and connections (the people you've connected with, across events). Layout in `backend/src/store.ts`. |
| Photos | S3 (private bucket) behind CloudFront | Profile photos uploaded from the app, checked to be JPEG, PNG or WebP, at most 2 MB. Served from their own CDN address (`PhotoBaseUrl` in the stack outputs). |
| Sidekick | OpenRouter free models for now (`openrouter/free`), Amazon Bedrock Claude Haiku 5.5 later | The OpenRouter key lives in SSM Parameter Store, never in the app. Bedrock uses the Lambda's IAM role. Cached, rate limited per person, with a template fallback (`backend/src/sidekick.ts`). |
| Places | Amazon Location Service (Places) | Place suggestions and "near me" for check-ins. Also IAM, no key. |
| Website | Cloudflare Pages | The Flutter web build, built by Cloudflare from this repo (`app/cloudflare-build.sh`) on every push, at sidekick.artifisi.com. Event links (`/e/<id>`) open the app: on Android the installed app, elsewhere the web app. Also serves Android app-link verification. |
| Cost guard | AWS Budgets, Lambda concurrency cap, API throttling | Email alert at 50% of the monthly budget and when the forecast passes 100%. |

### Privacy rules (enforced in `backend/src/app.ts`, tested in `backend/test/app.test.ts`)
- A profile is only returned to its owner.
- Attendee cards are only shown to people checked in to the same event. Contact details are never on a card; they're returned only to someone you matched with.
- Swipes are only ever returned to the swiper.
- A match needs two Connects. Blocks hide people both ways.
- Connections (the Connected tab) are only shown to the two people in them. They're kept across events, so a later event doesn't ask you to connect again, and they go when the event they were made at is deleted or either account is deleted.
- Guests can't swipe or see matches.
- Messages go only between two people who matched, and not once either side has blocked the other. Alerts and the message list go only to the person they're about.
- A match's agent exchange is made once, on first view, and kept with the match.
- Prototype: places and events don't check where anyone is. Anyone can check in or join from anywhere. A real presence check (a rotating venue code, or stricter location) is an open decision before the first real event.

## Local development

Needs Node 22 and Flutter 3.47.

```sh
cd backend && npm ci
npm test                 # API tests
npm run dev -- --seed    # the real API on an in-memory store at http://localhost:8787, with a demo event

cd ../app && flutter pub get
flutter test
flutter run -d chrome --dart-define=DEV_API=http://localhost:8787
```

With `DEV_API` the app skips AWS and Google: "Continue with Google" just marks you as signed in. For an Android emulator use `DEV_API=http://10.0.2.2:8787`.

## Setting it up

Do these once. Nothing here needs a Google Cloud billing account.

### 1. Google sign-in (Google Cloud, free, no billing)
1. In [Google Cloud console](https://console.cloud.google.com/), create a new project (for example `sidekick-auth`). **Don't link a billing account** and don't enable any APIs: sign-in doesn't need them.
2. Google Auth Platform → Branding: app name **Sidekick** and your support email. Leave the logo off for now: a logo starts Google's brand verification. Audience: External. While the app is in **Testing**, add yourself and testers under Test users (up to 100).
3. Clients → Create client → **Web application**, name "Sidekick". Under **Authorized JavaScript origins** add `https://sidekick.artifisi.com` (plus `http://localhost:8080` for local testing). No redirect URIs. Copy the **client ID**: this is `GOOGLE_WEB_CLIENT_ID`. Android uses the same ID.
4. Later, after the first Android build (step 4): create another client → **Android** with package `com.artifisi.sidekick` and the SHA-1 from that run's summary.

### 2. The sidekick's model
**Now: OpenRouter (free).** Make a key at https://openrouter.ai/settings/keys. It goes in GitHub as the `OPENROUTER_API_KEY` secret (step 3), and the deploy stores it in AWS SSM Parameter Store, never in the app. Without it the sidekick uses its template, so nothing breaks. Free models are rate limited and may log prompts, so this is for the pilot only.

**Later: Bedrock.** Once AWS enables Bedrock on the account, open **Claude Haiku 5.5** in the Bedrock playground (us-east-1), fill in Anthropic's one-time form, then set the repo variable `LLM_PROVIDER` to `bedrock` and deploy again.

### 3. Deploy from GitHub
1. **An AWS access key.** AWS console → IAM → Users → Create user `github-deploy` → Attach policies directly → `AdministratorAccess` → Create. Open the user → Security credentials → Create access key → "Third-party service" → copy both values.
2. **Repo settings.** GitHub repo → Settings → Secrets and variables → Actions:
   - Secrets: `AWS_ACCESS_KEY_ID`, `AWS_SECRET_ACCESS_KEY`, `OPENROUTER_API_KEY`.
   - Variables: `GOOGLE_WEB_CLIENT_ID` (step 1.3) and `ALERT_EMAIL` (for the budget alert).
3. **Run it.** Actions → **Deploy** → Run workflow. It bootstraps CDK on the first run, deploys the backend in ap-southeast-1. The run summary lists the outputs, including `DeployRoleArn`. Confirm the AWS Budgets email it sends.

After that, every push to main that touches `app/` or `backend/` deploys again.

**Optional, safer:** add `DeployRoleArn` as the secret `AWS_DEPLOY_ROLE_ARN`. The workflow then signs in with that role (GitHub OIDC, nothing stored) instead of the key, and you can delete the access key and the `github-deploy` user.

Other settings, as repo variables: `MODEL_ID`, `SITE_DOMAIN`, `SITE_CERTIFICATE_ARN`, `ANDROID_CERT_SHA256`. For a manual deploy, `cd backend && npx cdk deploy -c googleClientId=...` also works (context keys: `monthlyBudgetUsd`, `apiConcurrency` (off by default; new accounts cannot reserve Lambda concurrency), `llmProvider`, `modelId`, `bedrockRegion`, `placesCountries`, `githubRepo`, `githubOidcProviderArn`).

### 4. Android app
Actions → **Android app** → Run workflow (or push a version tag like `v0.3.0` to also publish a GitHub release). It needs nothing beyond the Deploy settings:
- It reads the API and sign-in settings from the deployed stack.
- On its first run it makes the release signing key and keeps it in AWS SSM (`/sidekick/android/keystore` and `/sidekick/android/keystore-password`), so every build is signed with the same key. Don't delete those: an app signed with another key can't update the installed one.
- It commits the key's SHA-256 to `app/web/.well-known/assetlinks.json`, so event links open the app.
- The run summary shows the key's SHA-1. **Once**, paste it into Google Cloud → Clients → Create client → **Android**, package `com.artifisi.sidekick`. Without it Google sign-in fails in the app (guest still works). Then copy that Android client's **client ID** into the repo variable `GOOGLE_ANDROID_CLIENT_ID` and re-run Deploy, so the sign-in pool accepts the app's tokens.

Download `sidekick-android` from the run: `sidekick.apk` installs directly, the `.aab` is for the Play Store.

For a local build, copy `app/env.example.json` to `app/env.json`, fill it in with the deploy outputs, and run `cd app && flutter build apk --release --dart-define-from-file=env.json`. It's signed with the debug key unless you write `app/android/key.properties` (`storeFile`, `storePassword`, `keyAlias`, `keyPassword`); Google sign-in in debug builds needs a second Android client with the debug SHA-1 (`cd app/android && ./gradlew signingReport`).

### 5. Your own signing key (optional)
To use a key you made yourself instead, add the secrets `ANDROID_KEYSTORE_BASE64` (`base64 -w0 sidekick-release.jks`), `ANDROID_KEYSTORE_PASSWORD`, `ANDROID_KEY_ALIAS` and `ANDROID_KEY_PASSWORD`. They win over the key in SSM.

### 6. The website: Cloudflare Pages + sidekick.artifisi.com
1. Cloudflare dashboard → Workers & Pages → Create → Pages → **Connect to Git** → pick `rajahafify/sidekick`.
2. Build settings: Framework preset **None**, Root directory `app`, Build command `bash cloudflare-build.sh`, Build output directory `build/web`.
3. Environment variables (Production, and Preview if you want PR previews), from the Deploy run's outputs:
   - `API_URL` = `ApiUrl`, `IDENTITY_POOL_ID` = `IdentityPoolId`, `GOOGLE_WEB_CLIENT_ID` = your Web client ID.
   - Optional: `ANDROID_CERT_SHA256` overrides the committed Android app-link fingerprint (step 4).
4. Save and Deploy. The first build takes a few minutes (it downloads Flutter).
5. The project → Custom domains → add `sidekick.artifisi.com`. If the old Sidekick Pages project still owns that domain, remove it there first.

After that, every push to main rebuilds the site, and every PR gets a preview link. Add the `*.pages.dev` address as a JavaScript origin on the Google Web client if you want sign-in on previews. (The AWS stack also still creates a CloudFront site, `SiteUrl`; it's unused and costs next to nothing.)

### 7. Admin site: admin-sidekick.artifisi.com
The admin screen lists open reports, every event and everyone, and can delete them. It also sets the default theme (system, light or dark) for people who haven't picked their own. It is the same web build: on a host name starting with `admin-` the app shows only the admin screen (elsewhere it's at `/admin`).
1. The Pages project → Custom domains → add `admin-sidekick.artifisi.com`.
2. Google Web client → Authorized JavaScript origins → add `https://admin-sidekick.artifisi.com`.
3. Open the admin site and sign in with Google. It shows your account id. Add it to the repo variable `ADMIN_IDENTITY_IDS` (comma-separated for several admins), then run **Deploy** again.

Only accounts in that list, signed in with Google, can call the `/admin` API. A guest never can.

## CI
CI (tests and the web build) runs only on demand (Actions → CI → Run workflow) or when you push a version tag such as `v0.3.0`. Deploys don't wait for it.

**Full suite** (Actions → Full suite → Run workflow) runs CI, then Deploy, then the Android app, one after another. It stops at the first failure, so a failing CI run never deploys.

## Costs
On demand everywhere, so an idle pilot costs close to nothing: DynamoDB, Lambda, API Gateway and CloudFront are cents at pilot scale, Location Service has a free tier, and Bedrock is pay per call (Haiku, cached, at most 15 scouts and 40 openers per person per event). The budget alert emails you before anything surprising happens.
