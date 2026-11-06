#!/usr/bin/env node
import { App } from 'aws-cdk-lib';
import { SidekickStack } from '../lib/stack';

// Settings come from cdk.json "context", or `-c key=value` on the command line.
const app = new App();
const ctx = (k: string, fallback = '') => String(app.node.tryGetContext(k) ?? fallback);

const googleClientId = ctx('googleClientId');
if (!googleClientId) throw new Error('Set googleClientId: npx cdk deploy -c googleClientId=<web client id>.apps.googleusercontent.com');

new SidekickStack(app, 'Sidekick', {
  env: { account: process.env.CDK_DEFAULT_ACCOUNT, region: ctx('region', process.env.CDK_DEFAULT_REGION || 'ap-southeast-1') },
  googleClientId,
  // OpenRouter's free router for now; switch to Bedrock with -c llmProvider=bedrock -c modelId=global.anthropic.claude-haiku-5-5
  llmProvider: ctx('llmProvider', 'openrouter') === 'bedrock' ? 'bedrock' : 'openrouter',
  modelId: ctx('modelId', ctx('llmProvider', 'openrouter') === 'bedrock' ? 'global.anthropic.claude-haiku-5-5' : 'openrouter/free'),
  openRouterKeyParam: ctx('openRouterKeyParam', '/sidekick/openrouter-api-key'),
  bedrockRegion: ctx('bedrockRegion', 'us-east-1'),
  alertEmail: ctx('alertEmail') || undefined,
  monthlyBudgetUsd: Number(ctx('monthlyBudgetUsd', '25')),
  apiConcurrency: Number(ctx('apiConcurrency', '0')),
  placesCountries: ctx('placesCountries', 'MYS'),
  siteDomain: ctx('siteDomain') || undefined,
  siteCertificateArn: ctx('siteCertificateArn') || undefined,
  androidCertSha256: ctx('androidCertSha256') || undefined,
  githubRepo: ctx('githubRepo', 'rajahafify/sidekick') || undefined,
  githubOidcProviderArn: ctx('githubOidcProviderArn') || undefined,
  description: 'Sidekick: guest + Google identities, API, data and the sidekick on Bedrock',
});
