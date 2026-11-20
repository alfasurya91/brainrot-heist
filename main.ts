// Brainrot Heist — entry point for the make.fun submission (Node 22, standard library only).
//
// The playable game lives in this repository as a Rojo project. `rojo build default.project.json
// --output game.rbxl` compiles src/ into game.rbxl; this script never builds anything, it only stages
// what already exists and describes it.
//
// What it does, in order:
//   1. resolves the output directory (MAKEFUN_OUTPUT_DIR, else /output inside the grader, else ./out);
//   2. copies game.rbxl and PLAY.json there unchanged;
//   3. copies src/ and screenshots/ recursively, dropping every entry whose own name starts with a dot;
//   4. writes dossier.json beside them with the vendored make.fun helper.
//
// The name filter in step 3 is not cosmetic. The grader accepts only names built from letters, digits,
// dot, underscore and hyphen, and a name may not start with a dot. Staging .gitkeep, .DS_Store or an
// editor swap file therefore fails the entry, so hidden entries are skipped at every depth.
//
// Running it locally:
//   mkdir -p out && MAKEFUN_OUTPUT_DIR=out node main.ts

import { copyFileSync, cpSync, existsSync, mkdirSync, readFileSync, writeFileSync } from 'node:fs';
import { basename, join } from 'node:path';
import { fileURLToPath } from 'node:url';
import {
  DOSSIER_SCHEMA,
  DOSSIER_TOP_CLASSES,
  DossierError,
  buildDossier,
  canonicalJson,
  readPlace,
} from './vendor/makefun-roblox.ts';

// Everything is resolved from the directory holding this file, never from the caller's cwd.
const root = fileURLToPath(new URL('.', import.meta.url));

// The output directory: MAKEFUN_OUTPUT_DIR when the caller sets it, otherwise ./out beside this file.
const out = process.env.MAKEFUN_OUTPUT_DIR ?? join(root, 'out');

// cpSync filter: keep an entry only when its own basename does not begin with a dot.
const visible = (path: string): boolean => !basename(path).startsWith('.');

// A copy helper for single files, failing with a message that names the missing path.
const stageFile = (name: string): void => {
  const from = join(root, name);
  if (!existsSync(from)) throw new Error(`main.ts: ${name} is missing from the repository root: ${from}`);
  copyFileSync(from, join(out, name));
};

mkdirSync(out, { recursive: true });

stageFile('game.rbxl');
stageFile('PLAY.json');

// The Lua sources are staged whole: the dossier shows them, and the grader compares them against the
// scripts embedded in the place.
cpSync(join(root, 'src'), join(out, 'src'), { recursive: true, filter: visible });

// screenshots/ always exists in the output, even when the source tree has none, because the dossier
// builder looks for the directory unconditionally.
mkdirSync(join(out, 'screenshots'), { recursive: true });
if (existsSync(join(root, 'screenshots'))) {
  cpSync(join(root, 'screenshots'), join(out, 'screenshots'), { recursive: true, filter: visible });
}

// These caps repeat the scorer's gate, so anything rejected here would have been rejected there too:
// at most 4 screenshots of at most 256 KiB each, a place under 500000 instances, scripts totalling under
// 8 MiB of source, and script paths under 1048576 characters. text_max_bytes is how much of the script
// text the dossier may keep.
const caps = {
  text_max_bytes: 65536,
  screenshots: { max: 4, max_bytes: 262144 },
  max_instances: 500000,
  scripts_max_source_bytes: 8388608,
  scripts_max_path_chars: 1048576,
};

// buildDossier treats the first screenshot as the cover, so a run with no image in screenshots/ can only
// fail. That is the expected state before Studio captures are taken. Instead of writing nothing, fall
// back to a place-only dossier — real numbers, no images, and a line saying plainly that the entry is not
// submittable yet. Any other failure is a real error and is rethrown.
let dossier: Uint8Array;
try {
  dossier = buildDossier(out, caps);
} catch (err) {
  if (!(err instanceof DossierError) || !err.message.includes('holds no image')) throw err;
  process.stderr.write(
    'main.ts: screenshots/ holds no image, so dossier.json was written without images.\n' +
      'main.ts: capture 3 or 4 PNG/JPEG screenshots of the game into screenshots/ and run this again before submitting.\n',
  );
  const place = readPlace(new Uint8Array(readFileSync(join(out, 'game.rbxl'))));
  const summary = [
    '## Place',
    '',
    `Instances: ${place.instances}`,
    `Classes, most instances first: ${place.classes
      .slice(0, DOSSIER_TOP_CLASSES)
      .map((entry) => `${entry.name} ${entry.count}`)
      .join(', ')}`,
    `Scripts: ${place.scripts.length}`,
    'Note: screenshots/ holds no image yet, so this dossier has no images and is not submittable.',
    '',
  ].join('\n');
  dossier = new Uint8Array(
    Buffer.from(canonicalJson({ schema: DOSSIER_SCHEMA, cover: 0, text: summary, images: [] }), 'utf8'),
  );
}

writeFileSync(join(out, 'dossier.json'), dossier);
