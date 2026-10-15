"""Pseudonymise GitHub logins in the replication data, or restore them.

    python tools/anonymize.py anonymize                        # data/actor_repo.csv, in place
    python tools/anonymize.py restore                          # data/actor_repo.csv, in place
    python tools/anonymize.py anonymize-file FILE COLUMNS      # e.g. login_types.csv login

FILE may be a plain or gzip-compressed CSV; COLUMNS is a comma-separated list of login columns.

pseudonym = "u_" + HMAC-SHA256(secret key, login)[:12]. The key (private/key) and the
pseudonym -> login table (private/login_map.csv) stay local: private/ is gitignored.
Values already starting with "u_" are left unchanged, so re-running a command is safe.
Organisation names (repository owners) are not pseudonymised.
"""
import csv
import gzip
import hashlib
import hmac
import secrets
import sys
import textwrap
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
DATA = ROOT / "data" / "actor_repo.csv"
KEY = ROOT / "private" / "key"
MAP = ROOT / "private" / "login_map.csv"

USAGE = textwrap.dedent(__doc__.split("\n\n")[1])


def opener(path):
    return gzip.open if path.suffix == ".gz" else open


def read(path):
    with opener(path)(path, "rt", newline="") as f:
        return list(csv.DictReader(f))


def write(path, rows, fieldnames):
    with opener(path)(path, "wt", newline="") as f:
        w = csv.DictWriter(f, fieldnames=fieldnames, lineterminator="\n")
        w.writeheader()
        w.writerows(rows)


def load_mapping():
    return {r["pseudonym"]: r["login"] for r in read(MAP)} if MAP.exists() else {}


def save_mapping(mapping):
    write(MAP, [{"pseudonym": p, "login": login} for p, login in mapping.items()], ["pseudonym", "login"])


def pseudonym(key, login, mapping):
    p = "u_" + hmac.new(key, login.encode(), hashlib.sha256).hexdigest()[:12]
    if mapping.get(p, login) != login:
        raise RuntimeError(f"pseudonym collision: {p}")
    mapping[p] = login
    return p


def anonymize():
    rows = read(DATA)
    if all(r["login"].startswith("u_") for r in rows):
        print(f"nothing to do: all logins in {DATA} are already pseudonymised")
        return
    KEY.parent.mkdir(exist_ok=True)
    if not KEY.exists():
        KEY.write_text(secrets.token_hex(32))
    key = bytes.fromhex(KEY.read_text().strip())
    mapping = load_mapping()
    for r in rows:
        if not r["login"].startswith("u_"):
            r["login"] = pseudonym(key, r["login"], mapping)
    save_mapping(mapping)
    write(DATA, rows, list(rows[0]))
    print(f"pseudonymised logins in {DATA}; map: {MAP}")


def restore():
    mapping = load_mapping()
    rows = read(DATA)
    for r in rows:
        r["login"] = mapping.get(r["login"], r["login"])
    write(DATA, rows, list(rows[0]))
    print(f"restored original logins in {DATA}")


def anonymize_file(path, columns):
    key = bytes.fromhex(KEY.read_text().strip())
    mapping = load_mapping()
    rows = read(path)
    for r in rows:
        for c in columns:
            login = r[c]
            if login and not login.startswith("u_"):
                r[c] = pseudonym(key, login, mapping)
    save_mapping(mapping)
    write(path, rows, list(rows[0]))
    print(f"pseudonymised columns {columns} in {path}; map: {MAP}")


def main(argv):
    if argv == ["anonymize"]:
        anonymize()
    elif argv == ["restore"]:
        restore()
    elif len(argv) == 3 and argv[0] == "anonymize-file":
        anonymize_file(Path(argv[1]), argv[2].split(","))
    else:
        sys.exit(f"usage:\n{USAGE}")


if __name__ == "__main__":
    main(sys.argv[1:])
