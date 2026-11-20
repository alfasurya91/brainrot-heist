// Entry point for the Brainrot Heist submission (Node 22, nothing outside the standard library).
//
// The game itself is the Rojo project in this folder: `rojo build default.project.json --output game.rbxl`
// turns src/ into game.rbxl. This script is what hands that game to the judge. It stages a copy of the
// playable place, the Lua sources, the screenshots and PLAY.json into the output directory, then writes
// dossier.json beside them using the vendored make.fun helper.
//
// Output naming is strict: every path the grader sees must begin with a letter, a digit or an underscore
// and may only contain letters, digits, dot, underscore and hyphen. Anything else — .gitkeep, .DS_Store,
// editor leftovers — makes the entry fail. That is why both source trees are copied through notDotted,
// which skips any entry whose name starts with a dot at any depth.
//
// Inside the grader the output directory is /output. Everywhere else, point MAKEFUN_OUTPUT_DIR at a folder:
//   mkdir -p out && MAKEFUN_OUTPUT_DIR=out node main.ts

import { copyFileSync, cpSync, existsSync, mkdirSync, readFileSync, writeFileSync } from 'node:fs';
import { basename, join } from 'node:path';
import { fileURLToPath } from 'node:url';
import {
  buildDossier,
  canonicalJson,
  DOSSIER_SCHEMA,
  DOSSIER_TOP_CLASSES,
  DossierError,
  readPlace,
} from './vendor/makefun-roblox.ts';

// Where this script lives, so every source path is resolved next to it rather than next to the caller.
const here = fileURLToPath(new URL('.', import.meta.url));

// The staging directory: MAKEFUN_OUTPUT_DIR when set, otherwise the grader's /output.
const out = process.env.MAKEFUN_OUTPUT_DIR ?? '/output';

// Filter handed to cpSync: reject any file or directory whose own name begins with a dot.
const notDotted = (path: string): boolean => !basename(path).startsWith('.');

// The built place and the published-place metadata go in as they are.
copyFileSync(join(here, 'game.rbxl'), join(out, 'game.rbxl'));
copyFileSync(join(here, 'PLAY.json'), join(out, 'PLAY.json'));

// Lua sources, recursively, minus hidden names.
cpSync(join(here, 'src'), join(out, 'src'), { recursive: true, filter: notDotted });

// The screenshots folder always exists in the output, even when there is nothing to put in it.
mkdirSync(join(out, 'screenshots'), { recursive: true });
if (existsSync(join(here, 'screenshots'))) {
  cpSync(join(here, 'screenshots'), join(out, 'screenshots'), { recursive: true, filter: notDotted });
}

// Limits mirror the scorer's own gate: text_max_bytes decides how much text the dossier keeps, while the
// remaining caps reject anything the scorer would reject anyway — more than 4 screenshots or a screenshot
// over 256 KiB, a place above 500000 instances, scripts totalling over 8 MiB of source, or script paths
// totalling over 1048576 characters.
const caps = {
  text_max_bytes: 65536,
  screenshots: { max: 4, max_bytes: 262144 },
  max_instances: 500000,
  scripts_max_source_bytes: 8388608,
  scripts_max_path_chars: 1048576,
};

// buildDossier refuses to write a dossier with no image, because the first screenshot is the judge's cover.
// Until real Studio captures land in screenshots/ that is the only way this program fails, so fall back to a
// dossier of the place alone (no images, no invented ones) and say plainly that the entry is not submittable
// yet. With one or more screenshots in place the buildDossier path below runs and its bytes are the gate's.
let dossier: Uint8Array;
try {
  dossier = buildDossier(out, caps);
} catch (err) {
  if (!(err instanceof DossierError) || !err.message.includes('holds no image')) throw err;
  process.stderr.write(
    'main.ts: screenshots/ holds no image, so dossier.json was written without images.\n' +
      'main.ts: add 3 or 4 PNG/JPEG captures of the game to screenshots/ and run this again before submitting.\n',
  );
  const place = readPlace(new Uint8Array(readFileSync(join(out, 'game.rbxl'))));
  const text = [
    '## Place',
    '',
    `Instances: ${place.instances}`,
    `Classes, most instances first: ${place.classes
      .slice(0, DOSSIER_TOP_CLASSES)
      .map((c) => `${c.name} ${c.count}`)
      .join(', ')}`,
    `Scripts: ${place.scripts.length}`,
    'Note: screenshots/ holds no image yet, so this dossier has no images and is not submittable.',
    '',
  ].join('\n');
  dossier = new Uint8Array(Buffer.from(canonicalJson({ schema: DOSSIER_SCHEMA, cover: 0, text, images: [] }), 'utf8'));
}
writeFileSync(join(out, 'dossier.json'), dossier);
