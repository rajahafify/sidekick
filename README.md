# Sidekick

**Stay in the talk. Your sidekick works the room.** At every event you have to choose between the main event and networking. Sidekick sends your sidekick in for you: check in to an event (or a place, like a coworking space), and it scouts everyone there and ranks who is worth meeting, based on what each person is looking for and can offer. You swipe **Connect** or **Pass**. When you both connect, it's a match: you swap contact details and get an opener for the break. Nobody sees who passed, or who connected with them before it's mutual.

**Guests** can fill in a profile, check in and see who their sidekick picks without signing in, on Android or on the web. To swipe, they sign in with Google, and everything they did as a guest carries over.

## Stack

Everything runs on AWS, in one CDK stack.

| Part | Where | What |
|---|---|---|
| App | `app/` | Flutter: the same app is the Android app and the website at sidekick.artifisi.com. White on black, halftone dots, Signal orange. |
| Identity | Cognito identity pool | A guest gets an unauthenticated identity. Google sign-in is linked to that same identity, so a guest keeps their data. Both get short-lived AWS credentials that can only call the API. |
| API | API Gateway (HTTP API, IAM auth) → Lambda (`backend/src`) | One Node 22 Lambda. API Gateway checks each request's signature and tells the Lambda who is calling and whether they're a guest. |
| Data | DynamoDB (one table, on demand) | Profiles, events, attendee cards, swipes, matches. Layout in `backend/src/store.ts`. |
| Sidekick | OpenRouter free models for now (`openrouter/free`), Amazon Bedrock Claude Haiku 5.5 later | The OpenRouter key lives in SSM Parameter Store, never in the app. Bedrock uses the Lambda's IAM role. Cached, rate limited per person, with a template fallback (`backend/src/sidekick.ts`). |
| Places | Amazon Location Service (Places) | Place suggestions and "near me" for check-ins. Also IAM, no key. |
| Website | GitHub Pages | The Flutter web build, published by the **Deploy** workflow at sidekick.artifisi.com. Event links (`/e/<id>`) open the app: on Android the installed app, elsewhere the web app. Also serves Android app-link verification. |
| Cost guard | AWS Budgets, Lambda concurrency cap, API throttling | Email alert at 50% of the monthly budget and when the forecast passes 100%. |

### Privacy rules (enforced in `backend/src/app.ts`, tested in `backend/test/app.test.ts`)
- A profile is only returned to its owner.
- Attendee cards are only shown to people checked in to the same event. Contact details are never on a card; they're returned only to someone you matched with.
- Swipes are only ever returned to the swiper.
- A match needs two Connects. Blocks hide people both ways.
- Guests can't swipe or see matches.
- When an event has a location, you have to be within 500 m to check in (checked on the server).

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
4. Create another client → **Android**: package `com.artifisi.sidekick`, and the **SHA-1** of your release key (step 5). Add a second Android client with the debug key's SHA-1 if you want sign-in in debug builds (`cd app/android && ./gradlew signingReport`).

### 2. The sidekick's model
**Now: OpenRouter (free).** Make a key at https://openrouter.ai/settings/keys. It goes in GitHub as the `OPENROUTER_API_KEY` secret (step 3), and the deploy stores it in AWS SSM Parameter Store, never in the app. Without it the sidekick uses its template, so nothing breaks. Free models are rate limited and may log prompts, so this is for the pilot only.

**Later: Bedrock.** Once AWS enables Bedrock on the account, open **Claude Haiku 5.5** in the Bedrock playground (us-east-1), fill in Anthropic's one-time form, then set the repo variable `LLM_PROVIDER` to `bedrock` and deploy again.

### 3. Deploy from GitHub
1. **An AWS access key.** AWS console → IAM → Users → Create user `github-deploy` → Attach policies directly → `AdministratorAccess` → Create. Open the user → Security credentials → Create access key → "Third-party service" → copy both values.
2. **Repo settings.** GitHub repo → Settings → Secrets and variables → Actions:
   - Secrets: `AWS_ACCESS_KEY_ID`, `AWS_SECRET_ACCESS_KEY`, `OPENROUTER_API_KEY`.
   - Variables: `GOOGLE_WEB_CLIENT_ID` (step 1.3) and `ALERT_EMAIL` (for the budget alert).
3. **Run it.** Actions → **Deploy** → Run workflow. It bootstraps CDK on the first run, deploys the backend in ap-southeast-1, builds the Flutter web app with the new API settings and publishes it. The run summary lists the outputs, including `DeployRoleArn`. Confirm the AWS Budgets email it sends.

After that, every push to main that touches `app/` or `backend/` deploys again.

**Optional, safer:** add `DeployRoleArn` as the secret `AWS_DEPLOY_ROLE_ARN`. The workflow then signs in with that role (GitHub OIDC, nothing stored) instead of the key, and you can delete the access key and the `github-deploy` user.

Other settings, as repo variables: `MODEL_ID`, `SITE_DOMAIN`, `SITE_CERTIFICATE_ARN`, `ANDROID_CERT_SHA256`. For a manual deploy, `cd backend && npx cdk deploy -c googleClientId=...` also works (context keys: `monthlyBudgetUsd`, `apiConcurrency` (off by default; new accounts cannot reserve Lambda concurrency), `llmProvider`, `modelId`, `bedrockRegion`, `placesCountries`, `githubRepo`, `githubOidcProviderArn`).

### 4. Android builds
CI builds the APK on every push (Actions → CI → `sidekick-apk` artifact). For a local build, copy `app/env.example.json` to `app/env.json`, fill it in with the deploy outputs, and run `cd app && flutter build apk --release --dart-define-from-file=env.json`.

### 5. Release signing key (Android)
```sh
keytool -genkeypair -v -keystore sidekick-release.jks -alias sidekick -keyalg RSA -keysize 2048 -validity 10000
keytool -list -v -keystore sidekick-release.jks -alias sidekick   # shows the SHA-1 and SHA-256
```
Keep the `.jks` file safe and out of git. For CI add the secrets `ANDROID_KEYSTORE_BASE64` (`base64 -w0 sidekick-release.jks`), `ANDROID_KEYSTORE_PASSWORD`, `ANDROID_KEY_ALIAS` and `ANDROID_KEY_PASSWORD`. For local builds, write `app/android/key.properties` with `storeFile`, `storePassword`, `keyAlias`, `keyPassword`. Put the SHA-1 on the Android OAuth client (step 1.4).

### 6. sidekick.artifisi.com (GitHub Pages)
1. Repo → Settings → **Pages** → Source: **GitHub Actions**. Under Custom domain enter `sidekick.artifisi.com` and save.
2. In your DNS, point `sidekick` (CNAME) at `rajahafify.github.io`. On Cloudflare, set it to **DNS only** (grey cloud) so GitHub can issue the HTTPS certificate, then tick **Enforce HTTPS** in Pages once it's offered.
3. Run **Deploy** (or push to main). For Android app links, also set the repo variable `ANDROID_CERT_SHA256` (step 5); the workflow writes `/.well-known/assetlinks.json`.

The web app is then live at https://sidekick.artifisi.com, and Android opens `https://sidekick.artifisi.com/e/<id>` links straight in the installed app. (The stack also still creates a CloudFront site, `SiteUrl`; it's unused and costs next to nothing.)

## Costs
On demand everywhere, so an idle pilot costs close to nothing: DynamoDB, Lambda, API Gateway and CloudFront are cents at pilot scale, Location Service has a free tier, and Bedrock is pay per call (Haiku, cached, at most 15 scouts and 40 openers per person per event). The budget alert emails you before anything surprising happens.
