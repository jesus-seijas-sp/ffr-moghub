// "1.10.2" vs "1.9": -1, 0 or 1, comparing number parts in order. Missing parts count as 0 (1.0 = 1.0.0); a letter
// part counts as newer than none (1.0b > 1.0), as mod authors mostly use letters for hotfixes.
function compareVersions(a, b) {
  const parts = (v) => String(v || '').replace(/^v/i, '').split(/[^0-9a-z]+|(?<=\d)(?=[a-z])/i).filter(Boolean);
  const pa = parts(a), pb = parts(b);
  for (let i = 0; i < Math.max(pa.length, pb.length); i++) {
    let x = pa[i], y = pb[i];
    if (x === undefined) x = /^\d+$/.test(y) ? '0' : '';
    if (y === undefined) y = /^\d+$/.test(x) ? '0' : '';
    const nx = /^\d+$/.test(x), ny = /^\d+$/.test(y);
    if (nx && ny) { if (+x !== +y) return +x < +y ? -1 : 1; continue; }
    if (x !== y) return x < y ? -1 : 1;
  }
  return 0;
}

module.exports = { compareVersions };
