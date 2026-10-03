#!/usr/bin/env bash
# Re-vendors the marketplace pack ash-ex4pm-evidence-pack into this repo
# (file-level vendoring with a sha256 lock, mirroring
# ~/ex4pm/priv/ggen/vendor/sync.sh) and applies the pack's own documented
# consumer adaptation deterministically:
#
#   1. byte-identical copies of ontology.ttl / gates/*.rq / templates/*.tmpl
#      (all sha256-locked in PACKS.lock.json; re-run refuses on drift)
#   2. a CONSUMER RENDER-PACK at priv/ggen/render/ash-ex4pm-evidence-pack/
#      produced deterministically from the locked bytes:
#        - ontology.ttl: the specimen Emitter row (MyApp.Fulfillment/ship)
#          replaced by this consumer's real Emitter row
#          (AshEx4pm.EngineRun / :conform, namespace AshEx4pm.Evidence,
#          app :ash_ex4pm) -- the pack README's consumer integration step 1
#        - templates: the D6 specimen `to:` path prefix
#          `tmp/d6/consumer/lib/...` / `.../test/...` rewritten to this
#          consumer's own paths (lib/ash_ex4pm/evidence/, test/ash_ex4pm/)
#
# Same pack bytes + same source git sha => byte-identical lock, render-pack
# and provenance.ttl (no timestamps anywhere). Run from anywhere:
#
#   priv/ggen/vendor/sync.sh [path-to-ggen-marketplace]   # default ~/ggen-marketplace
#
# Render (from the repo root, ash_pplan's ggen_igniter 0abed8a toolchain --
# the hex 26.9.9 dep in this repo's mix.exs renders EEx only, these pack
# templates are Tera):
#
#   cd ~/ash_pplan && MIX_BUILD_ROOT=_build-d6 mix run priv/.../render -- see
#   priv/ggen/render/README.md
set -euo pipefail

here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
market="${1:-$HOME/ggen-marketplace}"
pack="ash-ex4pm-evidence-pack"

[ -d "$market/packs/$pack" ] || { echo "sync.sh: no pack at $market/packs/$pack" >&2; exit 2; }

# -- 1. byte-identical vendored copies ----------------------------------------
cp "$market/packs/$pack/ontology.ttl" "$here/$pack.ontology.ttl"
rm -rf "$here/gates/$pack"
mkdir -p "$here/gates/$pack"
for g in "$market/packs/$pack"/gates/*.rq; do cp "$g" "$here/gates/$pack/"; done
rm -rf "$here/templates-src"
mkdir -p "$here/templates-src"
for t in "$market/packs/$pack"/templates/*.tmpl; do cp "$t" "$here/templates-src/"; done

# -- 2. deterministic consumer render-pack ------------------------------------
rm -rf "$here/render/$pack"
mkdir -p "$here/render/$pack/templates" "$here/render/$pack/gates"
cp "$here/gates/$pack"/*.rq "$here/render/$pack/gates/"
python3 - "$here" "$market" "$pack" <<'PY'
import hashlib, json, os, re, subprocess, sys

here, market, pack = sys.argv[1:4]

def sha256(path):
    return hashlib.sha256(open(path, "rb").read()).hexdigest()

def git(*args):
    return subprocess.check_output(["git", "-C", market, *args], text=True).strip()

head = git("rev-parse", "HEAD")

# ---- consumer render-pack: ontology emitter row + template to: paths ----
onto = open(os.path.join(here, pack + ".ontology.ttl")).read()

specimen = '''ex4ev:emitter-fulfillment a ex4ev:Emitter ;
  ex4ev:emitterResource "MyApp.Fulfillment" ;
  ex4ev:emitterAction "ship" ;
  ex4ev:emitterNamespace "MyApp.Evidence" ;
  ex4ev:emitterApp "my_app" ;
  rdfs:comment "Specimen consumer emitter: MyApp.Fulfillment ship action, rendering into the MyApp.Evidence namespace of the my_app OTP app." .'''

consumer = '''ex4ev:emitter-ash-ex4pm-engine-run a ex4ev:Emitter ;
  ex4ev:emitterResource "AshEx4pm.EngineRun" ;
  ex4ev:emitterAction "conform" ;
  ex4ev:emitterNamespace "AshEx4pm.Evidence" ;
  ex4ev:emitterNamespace "AshEx4pm.Evidence" ;
  ex4ev:emitterApp "ash_ex4pm" ;
  rdfs:comment "Consumer emitter: this repo's real AshEx4pm.EngineRun resource (conform action), rendering into the AshEx4pm.Evidence namespace of the ash_ex4pm OTP app. Replaces the pack's MyApp.Fulfillment specimen row." .'''

assert specimen in onto, "specimen Emitter row not found in ontology -- pack changed upstream"
consumer_onto = onto.replace(specimen, consumer)
open(os.path.join(here, "render", pack, "ontology.ttl"), "w").write(consumer_onto)

consumed_paths = []

for t in sorted(os.listdir(os.path.join(here, "templates-src"))):
    body = open(os.path.join(here, "templates-src", t)).read()
    orig = body
    root = os.path.abspath(os.path.join(here, "..", "..", ".."))
    if t == "evidence_court.exs.tmpl":
        body = body.replace(
            'to: "tmp/d6/consumer/test/{{ emitter_namespace | replace(from=\'.\', to=\'/\') }}/evidence_court.exs"',
            'to: "' + root + '/test/ash_ex4pm/evidence_court.exs"')
        body = body.replace(
            'consumer_lib = Path.expand("../../../lib", __DIR__)',
            'consumer_lib = Path.expand("../../lib/ash_ex4pm/evidence", __DIR__)')
        body = body.replace(
            'Path.join([consumer_lib, "{{ emitter_namespace | replace(from=\'.\', to=\'/\') }}", f])',
            'Path.join(consumer_lib, f)')
    else:
        body = body.replace('tmp/d6/consumer/lib/{{ emitter_namespace | replace(from=\'.\', to=\'/\') }}',
                            root + '/lib/ash_ex4pm/evidence')
    assert body != orig, "template to: path rewrite did not apply for " + t
    open(os.path.join(here, "render", pack, "templates", t), "w").write(body)

# ---- lock over the byte-identical vendored files ----
toml = open(os.path.join(market, "packs", pack, "pack.toml")).read()
version = re.search(r'^version\s*=\s*"([^"]+)"', toml, re.M).group(1)
dirty = git("status", "--porcelain", "--", f"packs/{pack}") != ""
entries = [(f"{pack}.ontology.ttl", f"packs/{pack}/ontology.ttl")]
for g in sorted(os.listdir(os.path.join(here, "gates", pack))):
    entries.append((f"gates/{pack}/{g}", f"packs/{pack}/gates/{g}"))
for t in sorted(os.listdir(os.path.join(here, "templates-src"))):
    entries.append((f"templates-src/{t}", f"packs/{pack}/templates/{t}"))

files = [{"path": rel, "source_path": srcrel, "sha256": sha256(os.path.join(here, rel))}
         for rel, srcrel in entries]
lock = {"schema": "ash_ex4pm.ggen.vendor-lock/v1", "source_repo": "ggen-marketplace",
        "source_git_sha": head, "packs": [{"name": pack, "version": version,
        "source_tree_dirty": dirty, "files": files}]}

ttl = ["# GENERATED by priv/ggen/vendor/sync.sh from PACKS.lock.json. Do not edit.",
       "@prefix ex4al: <https://chatman.ai/ash_ex4pm/algorithm-registry#> .",
       "@prefix prov: <http://www.w3.org/ns/prov#> .",
       "@prefix xsd: <http://www.w3.org/2001/XMLSchema#> .", ""]
onto_sha = files[0]["sha256"]
ttl += [f"ex4al:pack_ash_ex4pm_evidence a prov:Entity ;",
        f'    ex4al:packName "{pack}" ;',
        f'    ex4al:packVersion "{version}" ;',
        f'    ex4al:packOntologySha256 "{onto_sha}" ;',
        f'    ex4al:sourceGitSha "{head}" ;',
        f'    ex4al:sourceTreeDirty "{str(dirty).lower()}"^^xsd:boolean .', ""]
open(os.path.join(here, "provenance.ttl"), "w").write("\n".join(ttl))

lock["generated"] = [{"path": "provenance.ttl", "sha256": sha256(os.path.join(here, "provenance.ttl"))}]
with open(os.path.join(here, "PACKS.lock.json"), "w") as f:
    json.dump(lock, f, indent=2)
    f.write("\n")

print("sync.sh: vendored", pack, "from", market, "@", head)
PY
echo "sync.sh: consumer render-pack at priv/ggen/render/$pack"
