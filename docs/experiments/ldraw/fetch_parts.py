"""Download a bounded official-library subset and pack every model dependency.

Research utility, not an app asset pipeline. Run from any working directory.
Refuse missing geometry, unsafe paths, textures, and unresolved references.
"""
from datetime import datetime, timezone
import hashlib
import json
import time
from pathlib import Path, PurePosixPath
import urllib.error
import urllib.request

ROOT = Path(__file__).resolve().parent
BASE = "https://library.ldraw.org/library/official/"
LIBRARY = ROOT / "library"
PACKED = ROOT / "packed"
LIBRARY.mkdir(exist_ok=True)
PACKED.mkdir(exist_ok=True)
examples = json.loads((ROOT / "examples.json").read_text())


def safe_name(name):
    name = name.replace("\\", "/").lower()
    path = PurePosixPath(name)
    if path.is_absolute() or ".." in path.parts or ":" in name or not name.endswith(".dat"):
        raise ValueError(f"Unsupported reference: {name}")
    return name


def download(relative):
    target = LIBRARY / relative
    if target.exists():
        return target.read_text(encoding="utf-8-sig")
    request = urllib.request.Request(BASE + relative, headers={"User-Agent": "BrickByBrick-LDraw-research/1.0"})
    for attempt in range(3):
        time.sleep(0.75)
        try:
            with urllib.request.urlopen(request, timeout=30) as response:
                data = response.read(5_000_001)
            break
        except urllib.error.HTTPError as error:
            if error.code != 429 or attempt == 2:
                raise
            delay = max(60, int(error.headers.get("Retry-After", "60")))
            print(f"Library rate limit; waiting {delay}s", flush=True)
            time.sleep(delay)
    if len(data) > 5_000_000:
        raise ValueError(f"Unexpectedly large file: {relative}")
    text = data.decode("utf-8-sig")
    if not text.lstrip().startswith("0 ") or "<html" in text.lower():
        raise ValueError(f"Not an LDraw text file: {relative}")
    target.parent.mkdir(parents=True, exist_ok=True)
    target.write_text(text, encoding="utf-8")
    return text


def resolve(name):
    name = safe_name(name)
    prefixes = sorted(("parts/", "p/"), key=lambda prefix: not (LIBRARY / (prefix + name)).exists())
    for prefix in prefixes:
        relative = prefix + name
        try:
            text = download(relative)
            references = set()
            for line in text.splitlines():
                if line.lstrip().startswith("0 !TEXMAP"):
                    raise ValueError(f"Texture-mapped part requires a different renderer: {name}")
                tokens = line.split(maxsplit=14)
                if tokens and tokens[0] == "1":
                    if len(tokens) != 15:
                        raise ValueError(f"Invalid subfile reference in {name}")
                    references.add(safe_name(tokens[14]))
            return name, {"path": relative, "text": text, "references": sorted(references)}
        except urllib.error.HTTPError as error:
            if error.code != 404:
                raise
    raise FileNotFoundError(f"Missing official geometry: {name}")


files = {}
pending = {safe_name(example["part"]) for example in examples}
while pending:
    if len(files) + len(pending) > 1000:
        raise ValueError("Experiment dependency limit exceeded")
    resolved = list(map(resolve, sorted(pending)))
    files.update(resolved)
    pending = {ref for _, file in resolved for ref in file["references"]} - files.keys()
    print(f"Resolved {len(files)} files; {len(pending)} dependencies remain", flush=True)

materials = download("LDConfig.ldr")
for example in examples:
    closure = set()

    def visit(name, ancestors=()):
        if name in ancestors:
            raise ValueError(f"Circular geometry reference: {name}")
        if name in closure:
            return
        closure.add(name)
        for ref in files[name]["references"]:
            visit(ref, ancestors + (name,))

    visit(example["part"])
    # An explicit parent color preserves fixed-color decoration within the part.
    chunks = [f"0 FILE preview.ldr\n0 Research preview\n1 {example['color']} 0 0 0 1 0 0 0 1 0 0 0 1 {example['part']}\n"]
    for name in sorted(closure):
        chunks.append(f"0 FILE {name}\n{files[name]['text']}\n")
    packed = "\n".join(chunks)
    (PACKED / f"{example['id']}.mpd").write_text(packed, encoding="utf-8")
    example.update({"dependencyFiles": len(closure), "packedBytes": len(packed.encode()),
                    "sha256": hashlib.sha256(packed.encode()).hexdigest(),
                    "sourceTitle": files[example['part']]['text'].splitlines()[0][2:],
                    "catalogMapping": "Manually selected LDraw example; Rebrickable mapping not tested"})

manifest = {
    "retrievedAt": datetime.now(timezone.utc).isoformat(),
    "source": BASE,
    "renderer": "three@0.181.0 LDrawLoader",
    "examples": examples,
    "files": [{"name": name, "url": BASE + file["path"],
               "sha256": hashlib.sha256(file["text"].encode()).hexdigest(),
               "bytes": len(file["text"].encode()),
               "authors": [line[2:] for line in file["text"].splitlines() if line.startswith("0 Author:")],
               "license": [line[11:] for line in file["text"].splitlines() if line.startswith("0 !LICENSE ")]}
              for name, file in sorted(files.items())],
    "materials": {"url": BASE + "LDConfig.ldr", "sha256": hashlib.sha256(materials.encode()).hexdigest()}
}
(ROOT / "manifest.json").write_text(json.dumps(manifest, indent=2) + "\n")
print(f"Packed {len(examples)} examples from {len(files)} unique geometry files.")
