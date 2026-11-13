export class ServiceError extends Error {
  constructor(
    readonly code: string,
    message: string,
    readonly status: 400 | 401 | 403 | 404 | 409 | 410 | 413 | 422 | 500 | 503,
  ) {
    super(message);
    this.name = "ServiceError";
  }
}
