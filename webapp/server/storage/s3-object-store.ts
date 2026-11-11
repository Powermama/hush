import {
  DeleteObjectCommand,
  GetObjectCommand,
  PutObjectCommand,
  S3Client,
} from "@aws-sdk/client-s3";
import { getSignedUrl } from "@aws-sdk/s3-request-presigner";
import type { ProofObjectStore, UploadTarget } from "./proof-object-store";

export class S3ProofObjectStore implements ProofObjectStore {
  private readonly client: S3Client;

  constructor(
    private readonly bucket: string,
    options: {
      region: string;
      endpoint?: string;
      accessKeyId?: string;
      secretAccessKey?: string;
    },
  ) {
    this.client = new S3Client({
      region: options.region,
      endpoint: options.endpoint,
      credentials:
        options.accessKeyId && options.secretAccessKey
          ? {
              accessKeyId: options.accessKeyId,
              secretAccessKey: options.secretAccessKey,
            }
          : undefined,
    });
  }

  async createUploadTarget(input: {
    objectKey: string;
    proofId: string;
    uploadToken: string;
    contentLength: number;
    contentType: string;
  }): Promise<UploadTarget> {
    const command = new PutObjectCommand({
      Bucket: this.bucket,
      Key: input.objectKey,
      ContentLength: input.contentLength,
      ContentType: input.contentType,
    });
    return {
      url: await getSignedUrl(this.client, command, { expiresIn: 300 }),
      headers: { "content-type": input.contentType },
    };
  }

  async put(objectKey: string, bytes: Uint8Array): Promise<void> {
    await this.client.send(
      new PutObjectCommand({
        Bucket: this.bucket,
        Key: objectKey,
        Body: bytes,
        ContentType: "application/vnd.hush.proof+encrypted",
      }),
    );
  }

  async get(objectKey: string): Promise<Uint8Array | null> {
    try {
      const result = await this.client.send(
        new GetObjectCommand({ Bucket: this.bucket, Key: objectKey }),
      );
      return result.Body ? await result.Body.transformToByteArray() : null;
    } catch (error) {
      const status = (error as { $metadata?: { httpStatusCode?: number } }).$metadata
        ?.httpStatusCode;
      if (status === 404) return null;
      throw error;
    }
  }

  async delete(objectKey: string): Promise<void> {
    await this.client.send(
      new DeleteObjectCommand({ Bucket: this.bucket, Key: objectKey }),
    );
  }
}
