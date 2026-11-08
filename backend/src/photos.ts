// Profile photos in S3. The API writes and deletes them; the CDN in lib/stack.ts serves them.
import { DeleteObjectCommand, PutObjectCommand, S3Client } from '@aws-sdk/client-s3';
import type { Photos } from './app';

export function s3Photos(bucket: string, client = new S3Client({})): Photos {
  return {
    async put(key, bytes, contentType) {
      await client.send(
        new PutObjectCommand({
          Bucket: bucket,
          Key: key,
          Body: bytes,
          ContentType: contentType,
          // The key is random and never reused, so a cached copy can never be out of date.
          CacheControl: 'public, max-age=31536000, immutable',
        }),
      );
    },
    async remove(key) {
      await client.send(new DeleteObjectCommand({ Bucket: bucket, Key: key }));
    },
  };
}
