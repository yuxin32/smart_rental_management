import jpeg from 'jpeg-js';
import { PNG } from 'pngjs';
import { Buffer } from 'node:buffer';

export const MAX_BYTES = 5 * 1024 * 1024;
export const VERSION = 'pixels-v1';
const MAX_EDGE = 1600, MAX_PIXELS = 1600 * 1600;
export class PhotoRejected extends Error {
  constructor() { super('PHOTO_REJECTED'); }
}
const reject = () => { throw new PhotoRejected(); };
const dimensions = (width, height) => {
  if (width < 1 || height < 1 || width > MAX_EDGE || height > MAX_EDGE ||
      width * height > MAX_PIXELS) reject();
};

// Header bounds are a pre-allocation guard, NOT a substitute for decoding.
function inspectPng(bytes) {
  if (bytes.length < 45 || bytes.subarray(0, 8).toString('hex') !== '89504e470d0a1a0a') reject();
  let offset = 8, header = false, data = false, end = false;
  while (offset < bytes.length) {
    if (offset + 12 > bytes.length) reject();
    const length = bytes.readUInt32BE(offset), type = bytes.toString('ascii', offset + 4, offset + 8);
    if (length > MAX_BYTES || offset + length + 12 > bytes.length) reject();
    if (!header && type !== 'IHDR') reject();
    if (type === 'IHDR') {
      if (header || length !== 13) reject();
      dimensions(bytes.readUInt32BE(offset + 8), bytes.readUInt32BE(offset + 12));
      // Still, non-interlaced 8-bit RGB/RGBA only; matches app-prepared inputs.
      if (bytes[offset + 16] !== 8 || ![2, 6].includes(bytes[offset + 17]) ||
          bytes[offset + 18] !== 0 || bytes[offset + 19] !== 0 || bytes[offset + 20] !== 0) reject();
      header = true;
    } else if (['acTL', 'fcTL', 'fdAT'].includes(type)) reject();
    else if (type === 'IDAT') data = true;
    else if (type === 'IEND') {
      if (length !== 0 || !data || offset + 12 !== bytes.length) reject();
      end = true;
    } else if ((bytes[offset + 4] & 32) === 0 && type !== 'PLTE') reject();
    offset += length + 12;
  }
  if (!header || !data || !end) reject();
}
function inspectJpeg(bytes) {
  if (bytes.length < 4 || bytes[0] !== 255 || bytes[1] !== 216 ||
      bytes.at(-2) !== 255 || bytes.at(-1) !== 217) reject();
  let offset = 2, frame = false;
  while (offset < bytes.length - 2) {
    if (bytes[offset++] !== 255) reject();
    while (bytes[offset] === 255) offset++;
    const marker = bytes[offset++];
    if (marker === 218) break; // Decode all entropy-coded scans below.
    if (offset + 2 > bytes.length) reject();
    const length = bytes.readUInt16BE(offset);
    if (length < 2 || offset + length > bytes.length) reject();
    if ([192, 193, 194].includes(marker)) {
      if (frame || length < 8 || bytes[offset + 2] !== 8) reject();
      dimensions(bytes.readUInt16BE(offset + 5), bytes.readUInt16BE(offset + 3));
      frame = true;
    } else if (marker >= 195 && marker <= 207 && ![196, 200, 204].includes(marker)) reject();
    offset += length;
  }
  if (!frame) reject();
}
export async function digest(bytes) {
  return Buffer.from(await crypto.subtle.digest('SHA-256', bytes)).toString('hex');
}
export function canonicalize(source, extension) {
  try {
    if (!(source instanceof Uint8Array) || !source.length || source.length > MAX_BYTES) reject();
    const bytes = Buffer.from(source.buffer, source.byteOffset, source.byteLength);
    let pixels, encoded, mime;
    if (extension === 'jpg') {
      inspectJpeg(bytes);
      pixels = jpeg.decode(bytes, { useTArray: true, formatAsRGBA: true,
        tolerantDecoding: false, maxResolutionInMP: 2.56, maxMemoryUsageInMB: 64 });
      dimensions(pixels.width, pixels.height);
      // Copy only pixels/dimensions, NEVER decoder EXIF, comments or thumbnails.
      encoded = jpeg.encode({ width: pixels.width, height: pixels.height, data: pixels.data }, 80).data;
      mime = 'image/jpeg';
    } else if (extension === 'png') {
      inspectPng(bytes);
      pixels = PNG.sync.read(bytes, { checkCRC: true, skipRescale: false });
      dimensions(pixels.width, pixels.height);
      encoded = PNG.sync.write({ width: pixels.width, height: pixels.height, data: pixels.data },
        { colorType: 6, inputColorType: 6, bitDepth: 8, deflateLevel: 6 });
      mime = 'image/png';
    } else reject();
    if (!encoded.length || encoded.length > MAX_BYTES) reject();
    return { bytes: new Uint8Array(encoded), width: pixels.width, height: pixels.height, mime };
  } catch (_) { throw new PhotoRejected(); }
}
