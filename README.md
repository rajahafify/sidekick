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
| Sidekick | Amazon Bedrock, Claude Haiku 5.5 | Called with the Lambda's IAM role, so there's no API key to leak. Cached, rate limited per person, with a template fallback (`backend/src/sidekick.ts`). |
| Places | Amazon Location Service (Places) | Place suggestions and "near me" for check-ins. Also IAM, no key. |
| Website | S3 + CloudFront | The Flutter web build, published by the **Deploy web** workflow. Event links (`/e/<id>`) open the app: on Android the installed app, elsewhere the web app. Also serves Android app-link verification. |
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
3. Clients → Create client → **Web application**, name "Sidekick". Under **Authorized JavaScript origins** add `https://sidekick.artifisi.com` (and the `SiteUrl` from step 3 once you have it, plus `http://localhost:8080` for local testing). No redirect URIs. Copy the **client ID**: this is `GOOGLE_WEB_CLIENT_ID`. Android uses the same ID.
4. Create another client → **Android**: package `com.artifisi.sidekick`, and the **SHA-1** of your release key (step 5). Add a second Android client with the debug key's SHA-1 if you want sign-in in debug builds (`cd app/android && ./gradlew signingReport`).

### 2. Bedrock model access (AWS console)
In the Bedrock console in **us-east-1** → Model access, enable **Anthropic Claude Haiku 5.5** (Anthropic asks for a short use-case form the first time). Until it's enabled the sidekick uses its template, so nothing breaks.

### 3. Deploy the backend (once, from CloudShell)
Open **AWS CloudShell** (the `>_` icon in the AWS console), signed in as an admin of your account, in region **Asia Pacific (Singapore) ap-southeast-1**:

```sh
git clone https://github.com/rajahafify/sidekick && cd sidekick/backend
npm ci
npx cdk bootstrap
npx cdk deploy -c googleClientId=<GOOGLE_WEB_CLIENT_ID> -c alertEmail=<your email>
```

It prints `ApiUrl`, `IdentityPoolId`, `Region`, `SiteUrl`, `SiteBucket`, `SiteDistributionId` and `DeployRoleArn`. Confirm the AWS Budgets email it sends. Other settings (`cdk.json` or `-c`): `monthlyBudgetUsd` (default 25), `modelId` (default `global.anthropic.claude-haiku-5-5`), `bedrockRegion` (us-east-1), `placesCountries` (MYS), `githubRepo` (rajahafify/sidekick), and `githubOidcProviderArn` if your account already has a GitHub OIDC provider.

After this, GitHub can deploy for you: `DeployRoleArn` is a role only this repo's workflows can use, with no stored AWS keys.

### 4. Connect GitHub
In the repo → Settings → Secrets and variables → Actions:
- **Secret** `AWS_DEPLOY_ROLE_ARN` = `DeployRoleArn`.
- **Variables** `AWS_REGION`, `IDENTITY_POOL_ID`, `API_URL`, `SITE_BUCKET`, `SITE_DISTRIBUTION_ID` (from the deploy output) and `GOOGLE_WEB_CLIENT_ID`. For the **Deploy backend** workflow also `ALERT_EMAIL`.

Then:
- **Website:** Actions → **Deploy web** → Run workflow. It builds the Flutter web app and publishes it at `SiteUrl` (and at sidekick.artifisi.com after step 6). It also runs on every push to main that changes the app.
- **Android:** CI builds the APK on every push (Actions → CI → `sidekick-apk` artifact). For a local build, copy `app/env.example.json` to `app/env.json`, fill it in, and run `cd app && flutter build apk --release --dart-define-from-file=env.json`.
- **Backend changes later:** Actions → **Deploy backend**, or `cdk deploy` again from CloudShell.

### 5. Release signing key (Android)
```sh
keytool -genkeypair -v -keystore sidekick-release.jks -alias sidekick -keyalg RSA -keysize 2048 -validity 10000
keytool -list -v -keystore sidekick-release.jks -alias sidekick   # shows the SHA-1 and SHA-256
```
Keep the `.jks` file safe and out of git. For CI add the secrets `ANDROID_KEYSTORE_BASE64` (`base64 -w0 sidekick-release.jks`), `ANDROID_KEYSTORE_PASSWORD`, `ANDROID_KEY_ALIAS` and `ANDROID_KEY_PASSWORD`. For local builds, write `app/android/key.properties` with `storeFile`, `storePassword`, `keyAlias`, `keyPassword`. Put the SHA-1 on the Android OAuth client (step 1.4).

### 6. sidekick.artifisi.com
1. ACM in **us-east-1**: request a certificate for `sidekick.artifisi.com` and validate it with the DNS record it gives you.
2. Deploy again with `-c siteDomain=sidekick.artifisi.com -c siteCertificateArn=<arn> -c androidCertSha256=<SHA-256 from step 5>`.
3. In your DNS, point `sidekick.artifisi.com` (CNAME) at the CloudFront domain from `SiteUrl`.

The web app is then live at https://sidekick.artifisi.com, and Android opens `https://sidekick.artifisi.com/e/<id>` links straight in the installed app.

## Costs
On demand everywhere, so an idle pilot costs close to nothing: DynamoDB, Lambda, API Gateway and CloudFront are cents at pilot scale, Location Service has a free tier, and Bedrock is pay per call (Haiku, cached, at most 15 scouts and 40 openers per person per event). The budget alert emails you before anything surprising happens.
