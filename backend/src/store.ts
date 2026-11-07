// The data layer: one DynamoDB table, keyed pk/sk. MemoryStore mirrors it for tests.
//
//   pk               sk                    what
//   USER#<id>        PROFILE               private profile (only its owner reads it)
//   USER#<id>        EVENT#<eventId>       an event I've joined, for my home screen
//   USER#<id>        BLOCK#<otherId>       someone I've blocked
//   EVENT#<id>       META                  the event (gsi1pk = EVENTS, gsi1sk = createdAt, for the list)
//   EVENT#<id>       ATT#<uid>             attendee card + contact (contact is only ever sent to matches)
//   EVENT#<id>       SWIPE#<from>#<to>     Connect or Pass; never sent to anyone but the swiper
//   EVENT#<id>       MATCH#<a>#<b>         a mutual Connect (a < b)
//   QUOTA#<key>      QUOTA                 counts model calls; expires with ttl
//   CACHE#<key>      CACHE                 cached model answers; expires with ttl
//   REPORT#<id>      REPORT                a report about someone
//   SETTINGS#app     SETTINGS              app-wide settings: the default theme (the admin sets it)
import { ConditionalCheckFailedException, DynamoDBClient } from '@aws-sdk/client-dynamodb';
import {
  DeleteCommand,
  DynamoDBDocumentClient,
  GetCommand,
  PutCommand,
  QueryCommand,
  ScanCommand,
  UpdateCommand,
} from '@aws-sdk/lib-dynamodb';

export type Item = Record<string, any> & { pk: string; sk: string };

export interface Store {
  get(pk: string, sk: string): Promise<Item | null>;
  put(item: Item): Promise<void>;
  /** Puts only if the key doesn't exist yet. Returns false if it did. */
  create(item: Item): Promise<boolean>;
  delete(pk: string, sk: string): Promise<void>;
  /** Items under pk whose sk starts with prefix. */
  query(pk: string, prefix: string, limit?: number): Promise<Item[]>;
  /** Newest items in the gsi1 list (e.g. EVENTS). */
  recent(gsi1pk: string, limit: number): Promise<Item[]>;
  /** Adds 1 to a counter and returns the new value. */
  increment(pk: string, sk: string, ttl: number): Promise<number>;
  /** Every item with this sk, across the whole table. Admin only: it reads the table. */
  scanBySk(sk: string, limit?: number): Promise<Item[]>;
}

export class DynamoStore implements Store {
  constructor(
    private table: string,
    private db = DynamoDBDocumentClient.from(new DynamoDBClient({}), {
      marshallOptions: { removeUndefinedValues: true },
    }),
  ) {}

  async get(pk: string, sk: string) {
    const r = await this.db.send(new GetCommand({ TableName: this.table, Key: { pk, sk } }));
    return (r.Item as Item) ?? null;
  }

  async put(item: Item) {
    await this.db.send(new PutCommand({ TableName: this.table, Item: item }));
  }

  async create(item: Item) {
    try {
      await this.db.send(
        new PutCommand({ TableName: this.table, Item: item, ConditionExpression: 'attribute_not_exists(pk)' }),
      );
      return true;
    } catch (e) {
      if (e instanceof ConditionalCheckFailedException) return false;
      throw e;
    }
  }

  async delete(pk: string, sk: string) {
    await this.db.send(new DeleteCommand({ TableName: this.table, Key: { pk, sk } }));
  }

  async query(pk: string, prefix: string, limit = 1000) {
    const out: Item[] = [];
    let start: Record<string, any> | undefined;
    do {
      const r = await this.db.send(
        new QueryCommand({
          TableName: this.table,
          // DynamoDB rejects begins_with on an empty string, so an empty prefix means "the whole item".
          KeyConditionExpression: prefix ? 'pk = :pk AND begins_with(sk, :p)' : 'pk = :pk',
          ExpressionAttributeValues: prefix ? { ':pk': pk, ':p': prefix } : { ':pk': pk },
          ExclusiveStartKey: start,
          Limit: limit - out.length,
        }),
      );
      out.push(...((r.Items as Item[]) ?? []));
      start = r.LastEvaluatedKey;
    } while (start && out.length < limit);
    return out;
  }

  async recent(gsi1pk: string, limit: number) {
    const r = await this.db.send(
      new QueryCommand({
        TableName: this.table,
        IndexName: 'gsi1',
        KeyConditionExpression: 'gsi1pk = :g',
        ExpressionAttributeValues: { ':g': gsi1pk },
        ScanIndexForward: false,
        Limit: limit,
      }),
    );
    return (r.Items as Item[]) ?? [];
  }

  async increment(pk: string, sk: string, ttl: number) {
    const r = await this.db.send(
      new UpdateCommand({
        TableName: this.table,
        Key: { pk, sk },
        UpdateExpression: 'ADD #n :one SET #t = if_not_exists(#t, :ttl)',
        ExpressionAttributeNames: { '#n': 'n', '#t': 'ttl' },
        ExpressionAttributeValues: { ':one': 1, ':ttl': ttl },
        ReturnValues: 'UPDATED_NEW',
      }),
    );
    return Number(r.Attributes?.n ?? 1);
  }

  async scanBySk(sk: string, limit = 2000) {
    const out: Item[] = [];
    let start: Record<string, any> | undefined;
    do {
      const r = await this.db.send(
        new ScanCommand({
          TableName: this.table,
          FilterExpression: 'sk = :sk',
          ExpressionAttributeValues: { ':sk': sk },
          ExclusiveStartKey: start,
        }),
      );
      out.push(...((r.Items as Item[]) ?? []));
      start = r.LastEvaluatedKey;
    } while (start && out.length < limit);
    return out.slice(0, limit);
  }
}

/** In-memory Store for tests and local runs. */
export class MemoryStore implements Store {
  items = new Map<string, Item>();
  private k = (pk: string, sk: string) => `${pk}\u0000${sk}`;
  private copy = <T>(v: T): T => (v == null ? v : structuredClone(v));

  async get(pk: string, sk: string) {
    return this.copy(this.items.get(this.k(pk, sk)) ?? null);
  }
  async put(item: Item) {
    this.items.set(this.k(item.pk, item.sk), this.copy(item));
  }
  async create(item: Item) {
    if (this.items.has(this.k(item.pk, item.sk))) return false;
    await this.put(item);
    return true;
  }
  async delete(pk: string, sk: string) {
    this.items.delete(this.k(pk, sk));
  }
  async query(pk: string, prefix: string, limit = 1000) {
    return [...this.items.values()]
      .filter((i) => i.pk === pk && i.sk.startsWith(prefix))
      .sort((a, b) => (a.sk < b.sk ? -1 : 1))
      .slice(0, limit)
      .map(this.copy);
  }
  async recent(gsi1pk: string, limit: number) {
    return [...this.items.values()]
      .filter((i) => i.gsi1pk === gsi1pk)
      .sort((a, b) => (a.gsi1sk < b.gsi1sk ? 1 : -1))
      .slice(0, limit)
      .map(this.copy);
  }
  async increment(pk: string, sk: string) {
    const cur = this.items.get(this.k(pk, sk));
    const n = Number(cur?.n ?? 0) + 1;
    this.items.set(this.k(pk, sk), { ...(cur ?? { pk, sk }), n });
    return n;
  }
  async scanBySk(sk: string, limit = 2000) {
    return [...this.items.values()].filter((i) => i.sk === sk).slice(0, limit).map(this.copy);
  }
}
