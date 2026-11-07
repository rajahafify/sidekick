// Lambda entry point behind API Gateway (HTTP API, payload v2, IAM auth).
// API Gateway has already verified the SigV4 signature from the caller's Cognito identity pool
// credentials, and passes the identity id and how they signed in.
import type { APIGatewayProxyEventV2, APIGatewayProxyResultV2 } from 'aws-lambda';

/** The IAM authorizer's view of a Cognito identity (missing from @types/aws-lambda). */
type IamEvent = APIGatewayProxyEventV2 & {
  requestContext: {
    authorizer?: {
      iam?: { cognitoIdentity?: { identityId?: string; identityPoolId?: string; amr?: string[] } | null };
    };
  };
};
import { App, type Identity } from './app';
import { bedrockModel, openRouterModel, ssmSecret, type Model } from './model';
import { locationPlaces } from './places';
import { DynamoStore } from './store';

const env = process.env;

function pickModel(): Model | null {
  if (!env.MODEL_ID) return null;
  if (env.LLM_PROVIDER === 'openrouter') {
    return openRouterModel(env.MODEL_ID, ssmSecret(env.OPENROUTER_KEY_PARAM || '/sidekick/openrouter-api-key', env.AWS_REGION!));
  }
  return bedrockModel(env.MODEL_ID, env.BEDROCK_REGION || env.AWS_REGION!);
}

const app = new App({
  store: new DynamoStore(env.TABLE_NAME!),
  model: pickModel(),
  modelName: env.MODEL_ID ? `${env.LLM_PROVIDER === 'openrouter' ? 'OpenRouter' : 'Bedrock'} ${env.MODEL_ID}` : undefined,
  places: env.PLACES === 'off' ? null : locationPlaces(env.AWS_REGION!, (env.PLACES_COUNTRIES ?? '').split(',').filter(Boolean)),
  fetch,
  now: () => Date.now(),
  adminIds: (env.ADMIN_IDS ?? '').split(',').map((s) => s.trim()).filter(Boolean),
});

/** Who's calling. `amr` lists "unauthenticated" for guests, "authenticated" once they've signed in. */
export function identityOf(event: IamEvent): Identity | null {
  const c = event.requestContext.authorizer?.iam?.cognitoIdentity;
  if (!c?.identityId || c.identityPoolId !== env.IDENTITY_POOL_ID) return null;
  const amr = (c.amr ?? []).map(String);
  return { id: c.identityId, guest: !amr.includes('authenticated') };
}

export async function handler(event: IamEvent): Promise<APIGatewayProxyResultV2> {
  const identity = identityOf(event);
  const headers = { 'content-type': 'application/json', 'cache-control': 'no-store' };
  if (!identity) return { statusCode: 401, headers, body: JSON.stringify({ error: 'Sign in first.' }) };
  let body: unknown = undefined;
  if (event.body) {
    try {
      body = JSON.parse(event.isBase64Encoded ? Buffer.from(event.body, 'base64').toString('utf8') : event.body);
    } catch {
      return { statusCode: 400, headers, body: JSON.stringify({ error: 'Invalid request.' }) };
    }
  }
  const res = await app.handle({ method: event.requestContext.http.method, path: event.rawPath, body, identity });
  return { statusCode: res.status, headers, body: JSON.stringify(res.body) };
}
