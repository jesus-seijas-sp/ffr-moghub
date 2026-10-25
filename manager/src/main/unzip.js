// A small zip reader (stored and deflated entries), enough for GitHub archives and release zips: no dependencies.
const zlib = require('zlib');

// entries of a zip held in a Buffer: [{ name, isDir, data() }]
function entries(buf) {
  // the end-of-central-directory record: its signature, searched from the end (a comment can follow it)
  let eocd = -1;
  for (let i = buf.length - 22; i >= Math.max(0, buf.length - 22 - 65535); i--) {
    if (buf.readUInt32LE(i) === 0x06054b50) { eocd = i; break; }
  }
  if (eocd < 0) throw new Error('not a zip file');
  const count = buf.readUInt16LE(eocd + 10);
  let p = buf.readUInt32LE(eocd + 16);
  const out = [];
  for (let n = 0; n < count; n++) {
    if (buf.readUInt32LE(p) !== 0x02014b50) throw new Error('broken zip directory');
    const method = buf.readUInt16LE(p + 10);
    const compressed = buf.readUInt32LE(p + 20);
    const nameLen = buf.readUInt16LE(p + 28), extraLen = buf.readUInt16LE(p + 30), commentLen = buf.readUInt16LE(p + 32);
    const local = buf.readUInt32LE(p + 42);
    const name = buf.toString('utf8', p + 46, p + 46 + nameLen).replace(/\\/g, '/');
    p += 46 + nameLen + extraLen + commentLen;
    const isDir = name.endsWith('/');
    out.push({
      name, isDir,
      data() {
        const lnameLen = buf.readUInt16LE(local + 26), lextraLen = buf.readUInt16LE(local + 28);
        const start = local + 30 + lnameLen + lextraLen;
        const raw = buf.subarray(start, start + compressed);
        if (method === 0) return Buffer.from(raw);
        if (method === 8) return zlib.inflateRawSync(raw);
        throw new Error(`unsupported compression in ${name}`);
      },
    });
  }
  return out;
}

module.exports = { entries };
