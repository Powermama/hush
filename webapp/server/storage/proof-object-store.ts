export type UploadTarget = {
  url: string;
  headers: Record<string, string>;
};

export interface ProofObjectStore {
  createUploadTarget(input: {
    objectKey: string;
    proofId: string;
    uploadToken: string;
    contentLength: number;
    contentType: string;
  }): Promise<UploadTarget>;
  put(objectKey: string, bytes: Uint8Array): Promise<void>;
  get(objectKey: string): Promise<Uint8Array | null>;
  delete(objectKey: string): Promise<void>;
}

