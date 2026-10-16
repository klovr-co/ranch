#!/usr/bin/env python3
"""ranch secrets push / status: make a Convex deployment match an Infisical environment.

One way only: Infisical -> Convex. Never deletes anything in Convex. Never prints a value.

Called by lib/secrets.sh as:  secrets_sync.py <push|status> <env> <infisical-export.json> [--to DEPLOYMENT] [--yes]
Run from the repo root. Reads .ranch/secrets.yaml:

    dir: apps/backend            # where `npx convex` runs (the folder with convex.json)
    skip: CONVEX_HTTP_URL, NEXT_PUBLIC_*, CLERK_SECRET_KEY   # in Infisical but not for Convex
    prod:
      convex: prod:agile-bear-515
    dev:
      convex: prod:handsome-snail-393
"""
import fnmatch
import json
import os
import re
import subprocess
import sys

CONFIG = ".ranch/secrets.yaml"


def die(msg):
    print(f"\033[31merror:\033[0m {msg}", file=sys.stderr)
    sys.exit(2)


def read_config(path):
    """Tiny parser for the file above: `key: value` lines and one level of indented blocks."""
    if not os.path.isfile(path):
        die(f"{path} not found. Create it in the repo root, for example:\n\n"
            "    dir: apps/backend\n    skip: NEXT_PUBLIC_*\n    prod:\n      convex: prod:your-deployment\n"
            "    dev:\n      convex: prod:your-staging-deployment\n")
    cfg, block = {}, None
    for raw in open(path):
        line = raw.split("#", 1)[0].rstrip()
        if not line.strip():
            continue
        indented = line[0] in " \t"
        key, _, value = line.strip().partition(":")
        value = value.strip().strip("\"'")
        if indented:
            if block is None:
                die(f"{path}: indented line outside a section: {raw.strip()}")
            cfg[block][key] = value
        elif value == "":
            block = key
            cfg[block] = {}
        else:
            block = None
            cfg[key] = value
    return cfg


def parse_convex_env(text):
    """`npx convex env list` output -> {name: value}, joining multi-line quoted values with literal \\n."""
    lines, out, i = text.split("\n"), {}, 0
    while i < len(lines):
        ln = lines[i]
        if not ln.strip():
            i += 1
            continue
        key, _, value = ln.partition("=")
        if value.startswith("'"):
            buf = value[1:]
            while not buf.endswith("'") and i + 1 < len(lines):
                i += 1
                buf += "\n" + lines[i]
            value = buf[:-1]
        out[key] = value.replace("\n", "\\n")
        i += 1
    return out


def convex(args, cwd, deployment, stdin=None):
    env = dict(os.environ, CONVEX_DEPLOYMENT=deployment)
    # A deploy key in the shell would override the deployment we asked for.
    env.pop("CONVEX_DEPLOY_KEY", None)
    return subprocess.run(["npx", "convex", *args], cwd=cwd, env=env, input=stdin,
                          capture_output=True, text=True)


def guard(env_name, deployment, to_push):
    """Refuse the mix-ups that would hurt: dev things in prod."""
    problems = []
    if env_name == "prod":
        if deployment.startswith("dev:") or "local" in deployment:
            problems.append(f"prod would be pushed to a dev/local deployment ({deployment})")
        for name, value in to_push.items():
            if re.match(r"^(pk|sk)_test_", value):
                problems.append(f"{name} is a Clerk TEST key and this is prod")
    return problems


def main():
    args = sys.argv[1:]
    if len(args) < 3:
        die("usage: secrets_sync.py <push|status> <env> <infisical-export.json> [--to DEPLOYMENT] [--yes]")
    mode, env_name, export_path = args[:3]
    rest = args[3:]
    yes = "--yes" in rest
    to = rest[rest.index("--to") + 1] if "--to" in rest else None

    cfg = read_config(CONFIG)
    section = cfg.get(env_name)
    deployment = to or (section or {}).get("convex")
    if not deployment:
        die(f"{CONFIG} has no `{env_name}:` section with a `convex:` deployment (or pass --to).")
    cwd = cfg.get("dir", ".")
    skip = [p.strip() for p in cfg.get("skip", "").split(",") if p.strip()]

    inf = {x["key"]: x["value"] for x in json.load(open(export_path))}
    skipped = sorted(k for k in inf if any(fnmatch.fnmatch(k, p) for p in skip))
    want = {k: v for k, v in inf.items() if k not in skipped}

    listed = convex(["env", "list"], cwd, deployment)
    if listed.returncode != 0:
        die(f"couldn't read {deployment}:\n{listed.stderr.strip()[:400]}")
    have = parse_convex_env(listed.stdout)

    add = sorted(k for k in want if k not in have)
    change = sorted(k for k in want if k in have and have[k] != want[k])
    same = len(want) - len(add) - len(change)
    extra = sorted(k for k in have if k not in want)

    print(f"\nConvex {deployment}  <-  Infisical {env_name}")
    for k in add:
        print(f"  + add     {k}")
    for k in change:
        print(f"  ~ change  {k}")
    print(f"  = {same} unchanged")
    if extra:
        print(f"  ? only in Convex (left alone): {', '.join(extra)}")
    if skipped:
        print(f"  - not for Convex (skip list): {len(skipped)}")

    todo = {k: want[k] for k in add + change}
    problems = guard(env_name, deployment, todo)
    if problems:
        print()
        for p in problems:
            print(f"\033[31m  blocked:\033[0m {p}")
        sys.exit(3)

    if not todo:
        print("\nIn sync.")
        sys.exit(0)
    if mode == "status":
        print(f"\n{len(todo)} secret(s) differ. Run: ranch secrets push {env_name}")
        sys.exit(1)

    if not yes:
        if not sys.stdin.isatty():
            die("not a terminal; pass --yes to apply.")
        if input(f"\nApply {len(todo)} change(s) to {deployment}? [y/N] ").strip().lower() != "y":
            print("Nothing changed.")
            sys.exit(1)

    failed = []
    for name, value in todo.items():
        r = convex(["env", "set", name], cwd, deployment, stdin=value)
        if r.returncode != 0:
            failed.append(name)
            print(f"  \033[31mfailed\033[0m {name}: {r.stderr.strip()[:200]}")
    print(f"\nApplied {len(todo) - len(failed)} of {len(todo)}.")
    sys.exit(1 if failed else 0)


if __name__ == "__main__":
    main()
