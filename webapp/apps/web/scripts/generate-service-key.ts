import { createEphemeralServiceKey } from "../server/crypto/p256";

const generatedKey = await createEphemeralServiceKey();
const privateJwk = await crypto.subtle.exportKey("jwk", generatedKey.privateKey);
const keyId = process.argv[2] ?? generatedKey.id;

console.log(`HUSH_SERVICE_KEY_ID=${keyId}`);
console.log(`HUSH_SERVICE_PRIVATE_JWK=${JSON.stringify(privateJwk)}`);
