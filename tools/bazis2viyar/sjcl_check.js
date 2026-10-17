// Checks src/ocl_viyar/sjcl.rb against the SJCL library bundled in a decoded Bazis2Viyar script.
//
// Usage: node sjcl_check.js <decoded.js>
// Encrypts the same text with the same salt/IV in Ruby and in SJCL and compares, then decrypts a
// ViyarWriter-style file with SJCL. Run from the repository root (needs `ruby`).
const fs = require('fs');
const path = require('path');
const { execFileSync } = require('child_process');

const decoded = fs.readFileSync(process.argv[2], 'utf8');
// SJCL is the minified block between "var DEBUG = ..." and the first "if ((DEBUG" line
const lines = decoded.split(/\r?\n/);
const end = lines.findIndex((l) => l.startsWith('if ((DEBUG'));
const sjcl = new Function('module', 'require', lines.slice(1, end).join('\n') + '\nreturn sjcl;')({ exports: {} }, require);
const password = (decoded.match(/const PASSWORD = '([^']+)'/) || [])[1];
if (!password) throw new Error('PASSWORD constant not found');

const rubyPassword = execFileSync('ruby', ['-I', 'src', '-r', 'ocl_viyar/sjcl', '-r', 'ocl_viyar/viyar_writer',
  '-e', 'print OclViyar::ViyarWriter::PASSWORD']).toString();
console.log(password === rubyPassword ? 'password: same' : `password: CHANGED, update ViyarWriter::PASSWORD to ${password}`);

const salt = '0011223344556677';
const iv = '000102030405060708090a0b0c0d0e0f';
let ok = true;
for (const n of [5, 300, 70000]) {   // 70000 bytes exercises CCM's 3-byte length field
  const text = 'Деталь <detail/> '.repeat(Math.ceil(n / 17)).slice(0, n);
  const expected = sjcl.encrypt(password, text, { salt: sjcl.codec.hex.toBits(salt), iv: sjcl.codec.hex.toBits(iv) });
  const actual = execFileSync('ruby', ['-I', 'src', '-r', 'ocl_viyar/sjcl', '-e',
    'print OclViyar::Sjcl.encrypt(ARGV[0], STDIN.read.force_encoding("UTF-8"), salt: [ARGV[1]].pack("H*"), iv: [ARGV[2]].pack("H*"))',
    password, salt, iv], { input: text }).toString();
  const same = actual === expected;
  ok = ok && same;
  console.log(`length ${n}: ${same ? 'identical' : 'DIFFERENT'}`);
}
const roundTrip = sjcl.decrypt(password, execFileSync('ruby', ['-I', 'src', '-r', 'ocl_viyar/sjcl', '-e',
  'print OclViyar::Sjcl.encrypt(ARGV[0], "<project/>")', password]).toString());
console.log(`decrypt with SJCL: ${roundTrip === '<project/>' ? 'ok' : 'FAILED'}`);
process.exit(ok && roundTrip === '<project/>' ? 0 : 1);
