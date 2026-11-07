import * as path from 'node:path';
import {
  CfnOutput,
  Duration,
  RemovalPolicy,
  Stack,
  type StackProps,
  aws_budgets as budgets,
  aws_cognito as cognito,
  aws_dynamodb as dynamodb,
  aws_iam as iam,
  aws_lambda as lambda,
  aws_lambda_nodejs as nodejs,
  aws_logs as logs,
  aws_certificatemanager as acm,
  aws_cloudfront as cloudfront,
  aws_cloudfront_origins as origins,
  aws_s3 as s3,
  aws_s3_deployment as s3deploy,
} from 'aws-cdk-lib';
import { HttpApi, HttpMethod, CorsHttpMethod } from 'aws-cdk-lib/aws-apigatewayv2';
import { HttpIamAuthorizer } from 'aws-cdk-lib/aws-apigatewayv2-authorizers';
import { HttpLambdaIntegration } from 'aws-cdk-lib/aws-apigatewayv2-integrations';
import type { Construct } from 'constructs';

export type SidekickProps = StackProps & {
  /** OAuth "Web application" client id from Google Cloud. Google ID tokens must be issued for it. */
  googleClientId: string;
  /** Where the sidekick's model runs: 'openrouter' (key in SSM) or 'bedrock' (IAM role). */
  llmProvider: 'openrouter' | 'bedrock';
  /** OpenRouter model id, or Bedrock model / inference profile id. */
  modelId: string;
  /** Comma-separated Cognito identity ids allowed to use the admin screen. */
  adminIds?: string;
  /** SSM SecureString holding the OpenRouter API key. */
  openRouterKeyParam: string;
  /** Region to call Bedrock in (the model must be enabled there). */
  bedrockRegion: string;
  /** Where the monthly budget alert goes. */
  alertEmail?: string;
  /** Monthly AWS budget in USD for the alert. */
  monthlyBudgetUsd: number;
  /** Parallel-run ceiling for the API Lambda (0 = none). New AWS accounts can't reserve any. */
  apiConcurrency?: number;
  /** Comma-separated ISO-3166 alpha-3 country codes to prefer in place search, e.g. MYS. */
  placesCountries: string;
  /** The public site (event links, app-link verification), e.g. sidekick.artifisi.com. */
  siteDomain?: string;
  /** ACM certificate in us-east-1 for siteDomain (CloudFront needs it there). */
  siteCertificateArn?: string;
  /** SHA-256 fingerprint of the Android signing key, for /.well-known/assetlinks.json. */
  androidCertSha256?: string;
  /** GitHub repo (owner/name) allowed to deploy the web app and the stack through OIDC. */
  githubRepo?: string;
  /** ARN of an existing GitHub OIDC provider in this account; one is created when left out. */
  githubOidcProviderArn?: string;
};

export class SidekickStack extends Stack {
  constructor(scope: Construct, id: string, props: SidekickProps) {
    super(scope, id, props);

    // ---------- Data ----------
    const table = new dynamodb.TableV2(this, 'Table', {
      partitionKey: { name: 'pk', type: dynamodb.AttributeType.STRING },
      sortKey: { name: 'sk', type: dynamodb.AttributeType.STRING },
      billing: dynamodb.Billing.onDemand(),
      timeToLiveAttribute: 'ttl',
      pointInTimeRecoverySpecification: { pointInTimeRecoveryEnabled: true },
      deletionProtection: true,
      removalPolicy: RemovalPolicy.RETAIN,
      globalSecondaryIndexes: [
        {
          indexName: 'gsi1',
          partitionKey: { name: 'gsi1pk', type: dynamodb.AttributeType.STRING },
          sortKey: { name: 'gsi1sk', type: dynamodb.AttributeType.STRING },
        },
      ],
    });

    // ---------- Identity: guests, and Google sign-in ----------
    // A guest gets an unauthenticated identity. Signing in with Google later links Google to that
    // same identity, so the guest's profile and check-ins carry over.
    const pool = new cognito.CfnIdentityPool(this, 'Identities', {
      identityPoolName: 'sidekick',
      allowUnauthenticatedIdentities: true,
      allowClassicFlow: false,
      supportedLoginProviders: { 'accounts.google.com': props.googleClientId },
    });

    // ---------- API ----------
    const fn = new nodejs.NodejsFunction(this, 'Api', {
      entry: path.join(__dirname, '../src/handler.ts'),
      runtime: lambda.Runtime.NODEJS_22_X,
      architecture: lambda.Architecture.ARM_64,
      memorySize: 512,
      timeout: Duration.seconds(29),
      // Optional hard ceiling on parallel runs. New accounts have only 10 in total and can't reserve
      // any, so it's off by default; the API's own throttle below caps abuse either way.
      reservedConcurrentExecutions: props.apiConcurrency || undefined,
      logGroup: new logs.LogGroup(this, 'ApiLogs', { retention: logs.RetentionDays.ONE_MONTH }),
      environment: {
        TABLE_NAME: table.tableName,
        IDENTITY_POOL_ID: pool.ref,
        LLM_PROVIDER: props.llmProvider,
        MODEL_ID: props.modelId,
        OPENROUTER_KEY_PARAM: props.openRouterKeyParam,
        BEDROCK_REGION: props.bedrockRegion,
        PLACES_COUNTRIES: props.placesCountries,
        ADMIN_IDS: props.adminIds ?? '',
      },
      bundling: { minify: true, sourceMap: true, target: 'node22' },
    });
    table.grantReadWriteData(fn);
    fn.addToRolePolicy(
      new iam.PolicyStatement({
        actions: ['bedrock:InvokeModel', 'bedrock:InvokeModelWithResponseStream'],
        resources: [
          'arn:aws:bedrock:*::foundation-model/anthropic.*',
          'arn:aws:bedrock:::foundation-model/anthropic.*',
          'arn:aws:bedrock:*::foundation-model/amazon.nova*',
          'arn:aws:bedrock:::foundation-model/amazon.nova*',
          `arn:aws:bedrock:*:${this.account}:inference-profile/*`,
        ],
      }),
    );
    fn.addToRolePolicy(
      new iam.PolicyStatement({
        actions: ['ssm:GetParameter'],
        resources: [`arn:aws:ssm:${this.region}:${this.account}:parameter${props.openRouterKeyParam}`],
      }),
    );
    fn.addToRolePolicy(
      new iam.PolicyStatement({
        actions: ['geo-places:Suggest', 'geo-places:Autocomplete', 'geo-places:GetPlace', 'geo-places:SearchNearby'],
        resources: [`arn:aws:geo-places:${this.region}::provider/default`],
      }),
    );

    const api = new HttpApi(this, 'Http', {
      apiName: 'sidekick',
      defaultAuthorizer: new HttpIamAuthorizer(),
      corsPreflight: {
        // Every request is SigV4-signed with the caller's own short-lived credentials and no cookies
        // are involved, so any origin may call it (the site domain, the CloudFront URL, local dev).
        allowOrigins: ['*'],
        allowMethods: [CorsHttpMethod.GET, CorsHttpMethod.POST, CorsHttpMethod.PUT, CorsHttpMethod.DELETE],
        allowHeaders: [
          'authorization',
          'content-type',
          'x-amz-date',
          'x-amz-security-token',
          'x-amz-content-sha256',
          // The Dart SigV4 signer adds and signs this one.
          'x-amz-user-agent',
        ],
        maxAge: Duration.days(1),
      },
    });
    api.addRoutes({
      path: '/{proxy+}',
      methods: [HttpMethod.GET, HttpMethod.POST, HttpMethod.PUT, HttpMethod.DELETE],
      integration: new HttpLambdaIntegration('ApiIntegration', fn),
    });
    // Throttle the whole API: plenty for a pilot, and a cap on what abuse can cost.
    const stage = api.defaultStage!.node.defaultChild as import('aws-cdk-lib').aws_apigatewayv2.CfnStage;
    stage.defaultRouteSettings = { throttlingBurstLimit: 50, throttlingRateLimit: 25 };

    // ---------- Roles for the identities: they may call the API and nothing else ----------
    const invoke = new iam.PolicyStatement({
      actions: ['execute-api:Invoke'],
      resources: [`arn:aws:execute-api:${this.region}:${this.account}:${api.apiId}/*`],
    });
    const role = (name: string, amr: string) => {
      const r = new iam.Role(this, name, {
        assumedBy: new iam.FederatedPrincipal(
          'cognito-identity.amazonaws.com',
          {
            StringEquals: { 'cognito-identity.amazonaws.com:aud': pool.ref },
            'ForAnyValue:StringLike': { 'cognito-identity.amazonaws.com:amr': amr },
          },
          'sts:AssumeRoleWithWebIdentity',
        ),
        maxSessionDuration: Duration.hours(1),
      });
      r.addToPolicy(invoke);
      return r;
    };
    new cognito.CfnIdentityPoolRoleAttachment(this, 'Roles', {
      identityPoolId: pool.ref,
      roles: {
        authenticated: role('SignedInRole', 'authenticated').roleArn,
        unauthenticated: role('GuestRole', 'unauthenticated').roleArn,
      },
    });

    // ---------- Cost guard ----------
    if (props.alertEmail) {
      new budgets.CfnBudget(this, 'Budget', {
        budget: {
          budgetName: 'sidekick-monthly',
          budgetType: 'COST',
          timeUnit: 'MONTHLY',
          budgetLimit: { amount: props.monthlyBudgetUsd, unit: 'USD' },
        },
        notificationsWithSubscribers: [50, 100].map((threshold) => ({
          notification: {
            comparisonOperator: 'GREATER_THAN',
            notificationType: threshold === 100 ? 'FORECASTED' : 'ACTUAL',
            threshold,
            thresholdType: 'PERCENTAGE',
          },
          subscribers: [{ subscriptionType: 'EMAIL', address: props.alertEmail! }],
        })),
      });
    }

    // ---------- Website: the Flutter app itself, plus Android app-link verification ----------
    // The web build is uploaded by the "Deploy web" GitHub workflow (it needs Flutter to build);
    // this stack only creates the bucket and CDN, and writes /.well-known/assetlinks.json.
    const bucket = new s3.Bucket(this, 'Site', {
      blockPublicAccess: s3.BlockPublicAccess.BLOCK_ALL,
      enforceSSL: true,
      removalPolicy: RemovalPolicy.DESTROY,
      autoDeleteObjects: true,
    });
    // A single-page app: any path that isn't a file (/e/<id>, /me, ...) gets index.html and the
    // app's router takes it from there.
    const spa = new cloudfront.Function(this, 'AppRoutes', {
      code: cloudfront.FunctionCode.fromInline(
        "function handler(e){var r=e.request;var u=r.uri;if(u.indexOf('/.well-known/')===0)return r;" +
          "var last=u.substring(u.lastIndexOf('/')+1);if(last.indexOf('.')===-1){r.uri='/index.html';}return r;}",
      ),
      runtime: cloudfront.FunctionRuntime.JS_2_0,
    });
    const cdn = new cloudfront.Distribution(this, 'SiteCdn', {
      defaultBehavior: {
        origin: origins.S3BucketOrigin.withOriginAccessControl(bucket),
        viewerProtocolPolicy: cloudfront.ViewerProtocolPolicy.REDIRECT_TO_HTTPS,
        functionAssociations: [{ function: spa, eventType: cloudfront.FunctionEventType.VIEWER_REQUEST }],
      },
      defaultRootObject: 'index.html',
      priceClass: cloudfront.PriceClass.PRICE_CLASS_200,
      ...(props.siteDomain && props.siteCertificateArn
        ? {
            domainNames: [props.siteDomain],
            certificate: acm.Certificate.fromCertificateArn(this, 'SiteCert', props.siteCertificateArn),
          }
        : {}),
    });
    const assetLinks = props.androidCertSha256
      ? [
          {
            relation: ['delegate_permission/common.handle_all_urls'],
            target: {
              namespace: 'android_app',
              package_name: 'com.artifisi.sidekick',
              sha256_cert_fingerprints: props.androidCertSha256.split(',').map((s) => s.trim()),
            },
          },
        ]
      : [];
    new s3deploy.BucketDeployment(this, 'AppLinks', {
      destinationBucket: bucket,
      distribution: cdn,
      distributionPaths: ['/.well-known/*'],
      prune: false, // leave the web app's files alone
      sources: [s3deploy.Source.jsonData('.well-known/assetlinks.json', assetLinks)],
    });

    // ---------- GitHub deploys (OIDC, no stored AWS keys) ----------
    if (props.githubRepo) {
      const provider = props.githubOidcProviderArn
        ? iam.OpenIdConnectProvider.fromOpenIdConnectProviderArn(this, 'GitHubOidc', props.githubOidcProviderArn)
        : new iam.OpenIdConnectProvider(this, 'GitHubOidc', {
            url: 'https://token.actions.githubusercontent.com',
            clientIds: ['sts.amazonaws.com'],
          });
      const deployRole = new iam.Role(this, 'GitHubDeploy', {
        description: `Lets GitHub Actions in ${props.githubRepo} deploy Sidekick`,
        maxSessionDuration: Duration.hours(1),
        assumedBy: new iam.WebIdentityPrincipal(provider.openIdConnectProviderArn, {
          StringEquals: { 'token.actions.githubusercontent.com:aud': 'sts.amazonaws.com' },
          StringLike: { 'token.actions.githubusercontent.com:sub': `repo:${props.githubRepo}:*` },
        }),
      });
      // The web app: upload files and refresh the CDN.
      bucket.grantReadWrite(deployRole);
      bucket.grantDelete(deployRole);
      deployRole.addToPolicy(
        new iam.PolicyStatement({
          actions: ['cloudfront:CreateInvalidation'],
          resources: [`arn:aws:cloudfront::${this.account}:distribution/${cdn.distributionId}`],
        }),
      );
      // The stack: `cdk deploy` works through the roles `cdk bootstrap` made.
      deployRole.addToPolicy(
        new iam.PolicyStatement({
          actions: ['sts:AssumeRole'],
          resources: [`arn:aws:iam::${this.account}:role/cdk-*`],
        }),
      );
      new CfnOutput(this, 'DeployRoleArn', { value: deployRole.roleArn });
    }

    // ---------- What the app needs ----------
    new CfnOutput(this, 'ApiUrl', { value: api.apiEndpoint });
    new CfnOutput(this, 'IdentityPoolId', { value: pool.ref });
    new CfnOutput(this, 'Region', { value: this.region });
    new CfnOutput(this, 'SiteUrl', { value: `https://${cdn.distributionDomainName}` });
    new CfnOutput(this, 'SiteBucket', { value: bucket.bucketName });
    new CfnOutput(this, 'SiteDistributionId', { value: cdn.distributionId });
  }
}
