#!/usr/bin/env python3
"""ranch secrets import: collect a repo's secrets into an Infisical environment the first time.

One way only: source -> Infisical. Never deletes. Never prints a value. Never overwrites unless asked.

Called by lib/secrets.sh as:
    secrets_import.py <env> <infisical-export.json> <apply.yaml> --root DIR SOURCE [options]

SOURCE (exactly one):
    --from-convex DEPLOYMENT        e.g. prod:agile-bear-515   (runs `npx convex env list` in the `dir:` from .ranch/secrets.yaml)
    --from-file PATH                a .env style file (.env.local, .env.example with values filled in)
    --from-cloudrun SERVICE         a Google Cloud Run service; add --project and --region

Options:
    --overwrite       replace values that already exist in Infisical and differ (default: keep them)
    --skip A,B*       extra names to leave out (globs). CONVEX_DEPLOYMENT and CONVEX_DEPLOY_KEY are always left out.
    --dir DIR         where `npx convex` runs (default: `dir:` in .ranch/secrets.yaml, else the repo root)
    --yes             don't ask

Exit codes: 0 nothing to do or declined, 10 = apply.yaml is ready for the caller to load, 2 error, 3 blocked.
"""
import fnmatch
import json
import os
import re
import subprocess
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from secrets_sync import CONFIG, die, parse_convex_env, read_config  # noqa: E402

ALWAYS_SKIP = ["CONVEX_DEPLOYMENT", "CONVEX_DEPLOY_KEY"]
NAME = re.compile(r"^[A-Za-z_][A-Za-z0-9_]*$")


def one_line(value):
    """Infisical's file loader can't take multi-line values, so keep them on one line with a literal \\n."""
    return value.replace("\r\n", "\n").replace("\n", "\\n")


def parse_dotenv(text):
    out, lines, i = {}, text.split("\n"), 0
    while i < len(lines):
        ln = lines[i].strip()
        i += 1
        if not ln or ln.startswith("#"):
            continue
        if ln.startswith("export "):
            ln = ln[7:].lstrip()
        key, eq, value = ln.partition("=")
        key, value = key.strip(), value.strip()
        if not eq or not NAME.match(key):
            continue
        if value[:1] in ("'", '"'):
            q = value[0]
            buf = value[1:]
            while not re.search(r"(?<!\\)" + q + r"\s*(#.*)?$", buf) and i < len(lines):
                buf += "\n" + lines[i]
                i += 1
            value = re.sub(r"(?<!\\)" + q + r"\s*(#.*)?$", "", buf)
        else:
            value = re.sub(r"\s+#.*$", "", value)
        out[key] = one_line(value)
    return out


def run(cmd, **kw):
    try:
        return subprocess.run(cmd, capture_output=True, text=True, **kw)
    except FileNotFoundError:
        die(f"`{cmd[0]}` isn't installed on this computer.")


def from_convex(deployment, cwd):
    env = dict(os.environ, CONVEX_DEPLOYMENT=deployment)
    env.pop("CONVEX_DEPLOY_KEY", None)  # a deploy key in the shell would override the deployment we asked for
    r = run(["npx", "convex", "env", "list"], cwd=cwd, env=env)
    if r.returncode != 0:
        die(f"couldn't read {deployment}:\n{r.stderr.strip()[:400]}")
    return parse_convex_env(r.stdout)


def from_file(path):
    if not os.path.isfile(path):
        die(f"{path} not found.")
    return parse_dotenv(open(path).read())


def from_cloudrun(service, project, region):
    base = []
    if project:
        base += ["--project", project]
    cmd = ["gcloud", "run", "services", "describe", service, *base, "--format=json"]
    if region:
        cmd += ["--region", region]
    r = run(cmd)
    if r.returncode != 0:
        die(f"couldn't read Cloud Run service {service}:\n{r.stderr.strip()[:400]}")
    containers = json.loads(r.stdout)["spec"]["template"]["spec"].get("containers", [])
    out, volume_secrets = {}, 0
    for c in containers:
        for e in c.get("env", []):
            if "value" in e:
                out[e["name"]] = one_line(e["value"])
                continue
            ref = e.get("valueFrom", {}).get("secretKeyRef")
            if not ref:
                continue
            got = run(["gcloud", "secrets", "versions", "access", ref.get("key", "latest"),
                       "--secret", ref["name"], *base])
            if got.returncode != 0:
                print(f"  \033[33mcouldn't read secret {ref['name']} for {e['name']}\033[0m: {got.stderr.strip()[:160]}")
                continue
            out[e["name"]] = one_line(got.stdout.rstrip("\n"))
        volume_secrets += len(c.get("volumeMounts", []))
    if volume_secrets:
        print("  note: secrets mounted as files are not read; only environment variables are.")
    return out


def guard(env_name, source_label, found):
    problems = []
    if env_name == "prod":
        if source_label.startswith("dev:") or "local" in source_label:
            problems.append(f"prod would be filled from a dev/local source ({source_label})")
        for name, value in found.items():
            if re.match(r"^(pk|sk)_test_", value):
                problems.append(f"{name} is a Clerk TEST key and this is prod")
    return problems


def option(rest, flag):
    return rest[rest.index(flag) + 1] if flag in rest and rest.index(flag) + 1 < len(rest) else None


def main():
    args = sys.argv[1:]
    if len(args) < 3:
        die("usage: secrets_import.py <env> <infisical-export.json> <apply.yaml> --root DIR --from-convex|--from-file|--from-cloudrun …")
    env_name, export_path, apply_path = args[:3]
    rest = args[3:]
    root = option(rest, "--root") or "."
    yes, overwrite = "--yes" in rest, "--overwrite" in rest

    cfg = read_config(os.path.join(root, CONFIG)) if os.path.isfile(os.path.join(root, CONFIG)) else {}
    cwd = os.path.join(root, option(rest, "--dir") or cfg.get("dir", "."))

    sources = [f for f in ("--from-convex", "--from-file", "--from-cloudrun") if f in rest]
    if len(sources) != 1:
        die("choose one source: --from-convex DEPLOYMENT, --from-file PATH or --from-cloudrun SERVICE")
    flag = sources[0]
    arg = option(rest, flag)
    if not arg:
        die(f"{flag} needs a value.")

    if env_name == "prod" and flag == "--from-convex" and (arg.startswith("dev:") or "local" in arg):
        print(f"\n\033[31m  blocked:\033[0m prod would be filled from a dev/local source ({arg})")
        sys.exit(3)

    if flag == "--from-convex":
        found, label = from_convex(arg, cwd), arg
    elif flag == "--from-file":
        found, label = from_file(arg), arg
    else:
        found, label = from_cloudrun(arg, option(rest, "--project"), option(rest, "--region")), f"Cloud Run {arg}"

    skip = ALWAYS_SKIP + [p.strip() for p in (option(rest, "--skip") or "").split(",") if p.strip()]
    skipped = sorted(k for k in found if any(fnmatch.fnmatch(k, p) for p in skip))
    empty = sorted(k for k, v in found.items() if v == "" and k not in skipped)
    want = {k: v for k, v in found.items() if k not in skipped and k not in empty}

    have = {x["key"]: x["value"] for x in json.load(open(export_path))}
    add = sorted(k for k in want if k not in have)
    differ = sorted(k for k in want if k in have and have[k] != want[k])
    same = len(want) - len(add) - len(differ)

    print(f"\nInfisical {env_name}  <-  {label}")
    for k in add:
        print(f"  + add     {k}")
    for k in differ:
        print(f"  {'~ replace' if overwrite else '! differs'} {k}" + ("" if overwrite else "  (kept; --overwrite to replace)"))
    print(f"  = {same} already the same")
    if skipped:
        print(f"  - left out: {', '.join(skipped)}")
    if empty:
        print(f"  - empty, not imported: {', '.join(empty)}")

    todo = {k: want[k] for k in add + (differ if overwrite else [])}
    problems = guard(env_name, label, todo)
    if problems:
        print()
        for p in problems:
            print(f"\033[31m  blocked:\033[0m {p}")
        sys.exit(3)
    if not todo:
        print("\nNothing to import.")
        sys.exit(0)

    if not yes:
        if not sys.stdin.isatty():
            die("not a terminal; pass --yes to apply.")
        try:
            answer = input(f"\nLoad {len(todo)} secret(s) into Infisical {env_name}? [y/N] ").strip().lower()
        except EOFError:
            answer = ""
        if answer != "y":
            print("Nothing changed.")
            sys.exit(0)

    fd = os.open(apply_path, os.O_WRONLY | os.O_CREAT | os.O_TRUNC, 0o600)
    with os.fdopen(fd, "w") as f:
        for k, v in todo.items():
            f.write(f"{k}: {json.dumps(v)}\n")  # JSON strings are valid YAML, whatever the value contains
    sys.exit(10)


if __name__ == "__main__":
    main()
