function base64ToBytes(base64: string): Uint8Array {
  const binaryString = atob(base64);
  const len = binaryString.length;
  const bytes = new Uint8Array(len);
  for (let i = 0; i < len; i++) {
    bytes[i] = binaryString.charCodeAt(i);
  }
  return bytes;
}

function bytesToBase64(bytes: Uint8Array): string {
  let binary = '';
  const len = bytes.byteLength;
  for (let i = 0; i < len; i++) {
    binary += String.fromCharCode(bytes[i]);
  }
  return btoa(binary);
}

async function deriveCompatibilityKey(
  chatId: string,
  myUserId: string,
  partnerUserId: string
): Promise<CryptoKey> {
  const encoder = new TextEncoder();
  const participants = [myUserId, partnerUserId].sort();
  const seedStr = `xapzap-compat-chat:${participants.join(':')}:${chatId}`;
  const seedMaterial = encoder.encode(seedStr);
  const salt = encoder.encode(chatId);
  const info = encoder.encode('xapzap-compat-session-v1');

  const baseKey = await window.crypto.subtle.importKey(
    'raw',
    seedMaterial,
    { name: 'HKDF' },
    false,
    ['deriveKey']
  );

  return await window.crypto.subtle.deriveKey(
    {
      name: 'HKDF',
      hash: 'SHA-256',
      salt: salt,
      info: info
    },
    baseKey,
    {
      name: 'AES-GCM',
      length: 256
    },
    false,
    ['encrypt', 'decrypt']
  );
}

export async function decryptMessage(
  chatId: string,
  myUserId: string,
  partnerUserId: string,
  ciphertextB64: string,
  nonceB64: string,
  macB64: string
): Promise<string | null> {
  try {
    if (!ciphertextB64 || !nonceB64 || !macB64) return null;

    const key = await deriveCompatibilityKey(chatId, myUserId, partnerUserId);
    const ciphertextBytes = base64ToBytes(ciphertextB64);
    const nonceBytes = base64ToBytes(nonceB64);
    const macBytes = base64ToBytes(macB64);

    const encryptedData = new Uint8Array(ciphertextBytes.length + macBytes.length);
    encryptedData.set(ciphertextBytes, 0);
    encryptedData.set(macBytes, ciphertextBytes.length);

    const decrypted = await window.crypto.subtle.decrypt(
      {
        name: 'AES-GCM',
        iv: nonceBytes as any,
        tagLength: 128
      },
      key,
      encryptedData as any
    );

    return new TextDecoder().decode(decrypted);
  } catch (error) {
    console.error('Decryption failed:', error);
    return null;
  }
}

export async function encryptMessage(
  chatId: string,
  myUserId: string,
  partnerUserId: string,
  plaintext: string
): Promise<{ ciphertext: string; nonce: string; mac: string } | null> {
  try {
    const key = await deriveCompatibilityKey(chatId, myUserId, partnerUserId);
    const plaintextBytes = new TextEncoder().encode(plaintext);

    const nonceBytes = window.crypto.getRandomValues(new Uint8Array(12));

    const encrypted = await window.crypto.subtle.encrypt(
      {
        name: 'AES-GCM',
        iv: nonceBytes as any,
        tagLength: 128
      },
      key,
      plaintextBytes as any
    );

    const encryptedBytes = new Uint8Array(encrypted);
    const ciphertextBytes = encryptedBytes.slice(0, -16);
    const macBytes = encryptedBytes.slice(-16);

    return {
      ciphertext: bytesToBase64(ciphertextBytes),
      nonce: bytesToBase64(nonceBytes),
      mac: bytesToBase64(macBytes)
    };
  } catch (error) {
    console.error('Encryption failed:', error);
    return null;
  }
}
