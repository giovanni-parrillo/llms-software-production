"""Pseudonymise GitHub logins in data/actor_repo.csv, or restore them.

    python tools/anonymize.py anonymize     # logins -> u_<12 hex>, writes private/
    python tools/anonymize.py restore       # pseudonyms -> original logins
    python tools/anonymize.py anonymize-file data/author_reviewer_edges.csv author,reviewer
                                            # same key and map, for any CSV with login columns

pseudonym = "u_" + HMAC-SHA256(secret key, login)[:12]. The key (private/key) and the
pseudonym -> login table (private/login_map.csv) stay local: private/ is gitignored.
Values already starting with "u_" are left unchanged, so re-running a command is safe.
Organisation names (repository owners) are not pseudonymised.
"""
import csv, hashlib, hmac, secrets, sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
DATA = ROOT / "data" / "actor_repo.csv"
KEY, MAP = ROOT / "private" / "key", ROOT / "private" / "login_map.csv"


def read(path):
    with open(path, newline="") as f:
        return list(csv.DictReader(f))


def write(path, rows):
    with open(path, "w", newline="") as f:
        w = csv.DictWriter(f, fieldnames=list(rows[0]), lineterminator="\n")
        w.writeheader()
        w.writerows(rows)


def anonymize():
    KEY.parent.mkdir(exist_ok=True)
    if not KEY.exists():
        KEY.write_text(secrets.token_hex(32))
    key = bytes.fromhex(KEY.read_text().strip())
    mapping = {r["pseudonym"]: r["login"] for r in read(MAP)} if MAP.exists() else {}
    rows = read(DATA)
    out = {}
    for r in rows:
        if r["login"] in mapping:                      # already pseudonymised
            continue
        p = "u_" + hmac.new(key, r["login"].encode(), hashlib.sha256).hexdigest()[:12]
        assert mapping.get(p, r["login"]) == r["login"], f"pseudonym collision: {p}"
        out[r["login"]] = p
        mapping[p] = r["login"]
    write(MAP, [{"pseudonym": p, "login": l} for p, l in mapping.items()])  # map first
    for r in rows:
        r["login"] = out.get(r["login"], r["login"])
    write(DATA, rows)
    print(f"pseudonymised {len(out)} logins; map: {MAP}")


def restore():
    mapping = {r["pseudonym"]: r["login"] for r in read(MAP)}
    rows = read(DATA)
    for r in rows:
        r["login"] = mapping.get(r["login"], r["login"])
    write(DATA, rows)
    print("restored original logins")


def anonymize_file(path, cols):
    key = bytes.fromhex(KEY.read_text().strip())
    mapping = {r["pseudonym"]: r["login"] for r in read(MAP)} if MAP.exists() else {}
    rows = read(path)
    for r in rows:
        for c in cols:
            login = r[c]
            if not login or login.startswith("u_"):   # empty, or already pseudonymised
                continue
            p = "u_" + hmac.new(key, login.encode(), hashlib.sha256).hexdigest()[:12]
            assert mapping.get(p, login) == login, f"pseudonym collision: {p}"
            mapping[p] = login
            r[c] = p
    write(MAP, [{"pseudonym": p, "login": l} for p, l in mapping.items()])
    write(path, rows)
    print(f"pseudonymised columns {cols} in {path}; map: {MAP}")


if __name__ == "__main__":
    if len(sys.argv) == 4 and sys.argv[1] == "anonymize-file":
        anonymize_file(Path(sys.argv[2]), sys.argv[3].split(","))
    else:
        {"anonymize": anonymize, "restore": restore}[sys.argv[1] if len(sys.argv) > 1 else ""]()
