#!/usr/bin/env python3
import argparse
import json
import ssl
import sys
import time
import urllib.error
import urllib.parse
import urllib.request
from pathlib import Path

try:
    import yaml
except ImportError:
    yaml = None


def load_records(path: Path) -> dict:
    text = path.read_text()
    if yaml is not None:
        return yaml.safe_load(text)
    data: dict = {"hosts": {}, "cnames": {}}
    section = None
    for raw in text.splitlines():
        line = raw.split("#", 1)[0].rstrip()
        if not line.strip():
            continue
        if line.startswith(" ") or line.startswith("\t"):
            if section in ("hosts", "cnames") and ":" in line:
                key, value = line.strip().split(":", 1)
                data[section][key.strip()] = value.strip()
            continue
        if line.startswith("zone:"):
            data["zone"] = line.split(":", 1)[1].strip()
        elif line.startswith("catalog:"):
            data["catalog"] = line.split(":", 1)[1].strip()
        elif line.startswith("hosts:"):
            section = "hosts"
        elif line.startswith("cnames:"):
            section = "cnames"
    return data


class Client:
    def __init__(self, base: str, insecure: bool = False):
        self.base = base.rstrip("/")
        self.token = None
        self.ctx = ssl._create_unverified_context() if insecure else None

    def call(self, path: str, params: dict | None = None, method: str = "GET") -> dict:
        params = dict(params or {})
        headers = {}
        if self.token:
            headers["Authorization"] = f"Bearer {self.token}"
        url = self.base + path
        data = None
        if method == "POST":
            data = urllib.parse.urlencode(params).encode()
            headers["Content-Type"] = "application/x-www-form-urlencoded"
        elif params:
            url += "?" + urllib.parse.urlencode(params)
        req = urllib.request.Request(url, data=data, headers=headers, method=method)
        try:
            with urllib.request.urlopen(req, context=self.ctx, timeout=120) as resp:
                payload = json.loads(resp.read().decode())
        except urllib.error.HTTPError as exc:
            body = exc.read().decode(errors="replace")
            raise RuntimeError(f"{method} {url} -> HTTP {exc.code}: {body}") from exc
        if payload.get("status") != "ok":
            raise RuntimeError(f"{method} {path} failed: {payload}")
        return payload

    def login(self, user: str, password: str) -> None:
        payload = self.call("/api/user/login", {"user": user, "pass": password, "includeInfo": "true"})
        self.token = payload["token"]


def wait_http(base: str, attempts: int = 60) -> None:
    for _ in range(attempts):
        try:
            urllib.request.urlopen(base + "/api/user/login", timeout=3)
            return
        except Exception:
            time.sleep(2)
    raise RuntimeError(f"timeout waiting for {base}")


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--ns1", default="192.168.101.239")
    parser.add_argument("--ns2", default="192.168.101.240")
    parser.add_argument("--password", required=True)
    parser.add_argument("--records", default=str(Path(__file__).resolve().parents[1] / "records.yaml"))
    parser.add_argument("--cluster-domain", default="cluster.home.arpa")
    args = parser.parse_args()

    records = load_records(Path(args.records))
    ns1_http = f"http://{args.ns1}:5380"
    ns2_http = f"http://{args.ns2}:5380"

    print("waiting for ns1 web console")
    wait_http(ns1_http)
    print("waiting for ns2 web console")
    wait_http(ns2_http)

    ns1 = Client(ns1_http)
    ns1.login("admin", args.password)
    state = ns1.call("/api/admin/cluster/state", {"includeServerIpAddresses": "true"})
    initialized = state.get("response", {}).get("clusterInitialized", False)
    if not initialized:
        print("initializing cluster on ns1")
        ns1.call(
            "/api/admin/cluster/init",
            {
                "clusterDomain": args.cluster_domain,
                "primaryNodeIpAddresses": args.ns1,
            },
        )
    else:
        print("cluster already initialized on ns1")

    ns1_https = f"https://ns1.{args.cluster_domain}:53443/"
    ns2 = Client(ns2_http)
    ns2.login("admin", args.password)
    state2 = ns2.call("/api/admin/cluster/state", {"includeServerIpAddresses": "true"})
    if not state2.get("response", {}).get("clusterInitialized", False):
        print("joining ns2 to cluster")
        ns2.call(
            "/api/admin/cluster/initJoin",
            {
                "secondaryNodeIpAddresses": args.ns2,
                "primaryNodeUrl": ns1_https,
                "primaryNodeIpAddress": args.ns1,
                "ignoreCertificateErrors": "true",
                "primaryNodeUsername": "admin",
                "primaryNodePassword": args.password,
            },
            method="POST",
        )
    else:
        print("ns2 already in a cluster")

    catalog = records.get("catalog", f"cluster-catalog.{args.cluster_domain}")
    zone = records["zone"]
    zones = ns1.call("/api/zones/list").get("response", {}).get("zones", [])
    names = {z.get("name") for z in zones}
    if zone not in names:
        print(f"creating zone {zone} in {catalog}")
        ns1.call(
            "/api/zones/create",
            {"zone": zone, "type": "Primary", "catalog": catalog},
        )
    else:
        print(f"zone {zone} already exists")

    for name, ip in records.get("hosts", {}).items():
        print(f"A {name} -> {ip}")
        ns1.call(
            "/api/zones/records/add",
            {
                "domain": name,
                "zone": zone,
                "type": "A",
                "ipAddress": ip,
                "overwrite": "true",
                "ttl": "3600",
            },
        )

    for name, target in records.get("cnames", {}).items():
        print(f"CNAME {name} -> {target}")
        ns1.call(
            "/api/zones/records/add",
            {
                "domain": name,
                "zone": zone,
                "type": "CNAME",
                "cname": target,
                "overwrite": "true",
                "ttl": "3600",
            },
        )

    print("done")
    return 0


if __name__ == "__main__":
    sys.exit(main())
