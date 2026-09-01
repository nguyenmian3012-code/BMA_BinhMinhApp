import fs from 'node:fs';
import path from 'node:path';

const repositoryRoot = path.resolve(import.meta.dirname, '..', '..');
const brandRoot = path.join(
  repositoryRoot,
  'assets',
  'brand',
  'binh-minh',
  'app-icon',
);

function assert(condition, message) {
  if (!condition) throw new Error(message);
}

function readPng(relativePath) {
  const absolutePath = path.join(brandRoot, relativePath);
  const bytes = fs.readFileSync(absolutePath);
  assert(
    bytes.subarray(0, 8).equals(Buffer.from([137, 80, 78, 71, 13, 10, 26, 10])),
    `${relativePath} is not a PNG.`,
  );
  assert(bytes.toString('ascii', 12, 16) === 'IHDR', `${relativePath} has no IHDR.`);
  return {
    bytes,
    width: bytes.readUInt32BE(16),
    height: bytes.readUInt32BE(20),
    bitDepth: bytes[24],
    colorType: bytes[25],
  };
}

function expectPng(relativePath, width, height, allowedColorTypes) {
  const png = readPng(relativePath);
  assert(
    png.width === width && png.height === height,
    `${relativePath}: expected ${width}x${height}, found ${png.width}x${png.height}.`,
  );
  assert(
    allowedColorTypes.includes(png.colorType),
    `${relativePath}: unexpected PNG color type ${png.colorType}.`,
  );
  return png;
}

expectPng('source/bm7-original.png', 449, 445, [2]);
expectPng('master/app-icon-rounded-2048.png', 2048, 2048, [6]);
expectPng('master/android-adaptive-tiger-432.png', 432, 432, [4]);

for (const size of [16, 32, 48]) {
  expectPng(`web/favicon-${size}.png`, size, size, [2, 3, 6]);
}
expectPng('web/apple-touch-icon-180.png', 180, 180, [2]);
const web192 = expectPng('web/pwa-icon-192.png', 192, 192, [6]);
expectPng('web/pwa-icon-512.png', 512, 512, [6]);

const densitySizes = {
  mdpi: [48, 108],
  hdpi: [72, 162],
  xhdpi: [96, 216],
  xxhdpi: [144, 324],
  xxxhdpi: [192, 432],
};
for (const [density, [launcherSize, foregroundSize]] of Object.entries(densitySizes)) {
  expectPng(
    `platform/android/res/mipmap-${density}/ic_launcher.png`,
    launcherSize,
    launcherSize,
    [6],
  );
  expectPng(
    `platform/android/res/mipmap-${density}/ic_launcher_foreground.png`,
    foregroundSize,
    foregroundSize,
    [4],
  );
}

for (const api of ['v26', 'v33']) {
  const xml = fs.readFileSync(
    path.join(brandRoot, `platform/android/res/mipmap-anydpi-${api}/ic_launcher.xml`),
    'utf8',
  );
  assert(xml.includes('@mipmap/ic_launcher_foreground'), `${api} foreground is missing.`);
  assert(!xml.includes('ic_launcher_round'), `${api} must use the system mask.`);
}
const themedXml = fs.readFileSync(
  path.join(brandRoot, 'platform/android/res/mipmap-anydpi-v33/ic_launcher.xml'),
  'utf8',
);
assert(themedXml.includes('<monochrome'), 'Android 13 monochrome icon is missing.');

const iosRoot = path.join(brandRoot, 'platform', 'ios', 'AppIcon.appiconset');
const iosContents = JSON.parse(fs.readFileSync(path.join(iosRoot, 'Contents.json'), 'utf8'));
const referencedIosFiles = new Set(iosContents.images.map((image) => image.filename));
assert(referencedIosFiles.size === 15, `Expected 15 unique iOS PNGs, found ${referencedIosFiles.size}.`);
for (const filename of referencedIosFiles) {
  const image = iosContents.images.find((candidate) => candidate.filename === filename);
  const expectedSize = Math.round(Number.parseFloat(image.size) * Number.parseInt(image.scale, 10));
  const relativePath = `platform/ios/AppIcon.appiconset/${filename}`;
  expectPng(relativePath, expectedSize, expectedSize, [2, 3]);
}

const flutterAsset = fs.readFileSync(
  path.join(repositoryRoot, 'mobile', 'assets', 'brand', 'bm7-app-icon.png'),
);
assert(flutterAsset.equals(web192.bytes), 'Flutter logo must match the official 192px export.');

console.log('BM7 official brand assets: PASS');
