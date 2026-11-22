#!/usr/bin/env python3
"""App Store Connect helper for the TestFlight workflow (#406). Runs on a GitHub runner, never prints a key.

  asc.py signing OUTDIR      the App Store signing pieces: the distribution certificate and an App Store profile for
                             the app and one for its home screen widget (registering the widget's App ID if missing)
  asc.py wait BUILD          waits until build BUILD of version 1.0 is processed, then turns on internal testing
  asc.py status              lists the app's builds (number, state) for the log
  asc.py gamecenter          Game Center (#541): the capability, the leaderboards and the achievements
  asc.py store META SHOTS    fills in the App Store listing (#407); never submits
  asc.py submit BUILD        sends the version to App Review, only if it holds build BUILD (Tyler's "submit")
  asc.py iap [SHOT]          the tip jar's three consumable in-app purchases (#598): makes any that are missing, with
                             their names, US prices and every territory, and SHOT (a screenshot of the Tip jar) for
                             App Review. Needs the Paid Apps agreement in effect first. Never submits anything.

Reads ASC_KEY_PATH (the .p8 file), ASC_KEY_ID and ASC_ISSUER_ID from the environment.

The distribution certificate's private key isn't stored anywhere. It's re-made on each run from the App Store Connect
key (a one-way hash of it seeds the generator), so every run gets the same key, finds the certificate Apple already
issued for it, and Apple's limit on distribution certificates is never reached. A new App Store Connect key makes one
new certificate, once.
"""
import base64, hashlib, hmac, json, os, sys, time, urllib.error, urllib.parse, urllib.request

API = "https://api.appstoreconnect.apple.com"
BUNDLE_ID = "live.time2play.app"
WIDGET_ID = "live.time2play.app.widget"
# every bundle id the build signs: (the profile's name start, the file it's written to, the env name the workflow reads)
BUNDLES = {BUNDLE_ID: ("Time2Play", "app", "T2P_PROFILE_NAME"),
           WIDGET_ID: ("Time2Play Widget", "widget", "T2P_WIDGET_PROFILE_NAME")}
VERSION = "1.2"  # 1.1 was approved (found Nov 22, 2026: TestFlight refused a 1.1 build as an older version); the next update


def die(msg):
    print(f"::error::{msg}")
    sys.exit(1)


def key_text():
    with open(os.environ["ASC_KEY_PATH"], "rb") as f:
        return f.read()


def token():
    import jwt  # pyjwt
    now = int(time.time())
    return jwt.encode({"iss": os.environ["ASC_ISSUER_ID"], "iat": now, "exp": now + 15 * 60, "aud": "appstoreconnect-v1"},
                      key_text(), algorithm="ES256", headers={"kid": os.environ["ASC_KEY_ID"], "typ": "JWT"})


def call(method, path, body=None, ok_missing=False):
    url = path if path.startswith("http") else API + path
    data = json.dumps(body).encode() if body is not None else None
    req = urllib.request.Request(url, data=data, method=method,
                                 headers={"Authorization": f"Bearer {token()}", "Content-Type": "application/json"})
    try:
        with urllib.request.urlopen(req, timeout=60) as r:
            raw = r.read()
            return json.loads(raw) if raw else {}
    except urllib.error.HTTPError as e:
        detail = e.read().decode(errors="replace")
        if ok_missing and e.code == 404:
            return None
        # Apple's errors name the problem (a missing permission says FORBIDDEN_ERROR); they never contain the key
        print(f"App Store Connect said {e.code} to {method} {urllib.parse.urlparse(url).path}:\n{detail}")
        raise SystemExit(2)


def q(params):
    return "?" + urllib.parse.urlencode(params)


def the_app():
    apps = call("GET", "/v1/apps" + q({"filter[bundleId]": BUNDLE_ID}))["data"]
    apps = [a for a in apps if a["attributes"]["bundleId"] == BUNDLE_ID]
    if not apps:
        die(f"No App Store Connect app with bundle id {BUNDLE_ID}")
    return apps[0]


# ---------- signing ----------

class Stream:
    """A deterministic byte stream from a secret seed (SHA-512 in counter mode)."""
    def __init__(self, seed):
        self.seed, self.n, self.buf = seed, 0, b""

    def __call__(self, k):
        while len(self.buf) < k:
            self.buf += hashlib.sha512(self.seed + self.n.to_bytes(8, "big")).digest()
            self.n += 1
        out, self.buf = self.buf[:k], self.buf[k:]
        return out


def distribution_key():
    from Crypto.PublicKey import RSA  # pycryptodome, pinned in the workflow so the same seed makes the same key
    seed = hmac.new(key_text(), b"time2play app store distribution key v1", hashlib.sha256).digest()
    return RSA.generate(2048, randfunc=Stream(seed))


def signing(outdir):
    from cryptography import x509
    from cryptography.hazmat.primitives import hashes, serialization
    from cryptography.x509.oid import NameOID

    os.makedirs(outdir, exist_ok=True)
    os.chmod(outdir, 0o700)
    rsa = distribution_key()
    pem = rsa.export_key(pkcs=8)
    key = serialization.load_pem_private_key(pem, password=None)
    n = key.public_key().public_numbers().n

    # the certificate Apple issued for this key, if there is one
    cert_id, cert_der = None, None
    for c in call("GET", "/v1/certificates" + q({"filter[certificateType]": "DISTRIBUTION", "limit": 200}))["data"]:
        der = base64.b64decode(c["attributes"]["certificateContent"])
        if x509.load_der_x509_certificate(der).public_key().public_numbers().n == n:
            cert_id, cert_der = c["id"], der
            break
    if cert_id:
        print(f"Distribution certificate: found ({cert_id})")
    else:
        csr = (x509.CertificateSigningRequestBuilder()
               .subject_name(x509.Name([x509.NameAttribute(NameOID.COMMON_NAME, "Time2Play GitHub builds"),
                                        x509.NameAttribute(NameOID.COUNTRY_NAME, "US")]))
               .sign(key, hashes.SHA256()))
        csr_pem = csr.public_bytes(serialization.Encoding.PEM).decode()
        made = call("POST", "/v1/certificates", {"data": {"type": "certificates", "attributes": {
            "certificateType": "DISTRIBUTION", "csrContent": csr_pem}}})["data"]
        cert_id, cert_der = made["id"], base64.b64decode(made["attributes"]["certificateContent"])
        print(f"Distribution certificate: made a new one ({cert_id})")

    # an App Store profile for the app and one for its widget, with this certificate
    profiles = {b: profile_for(b, cert_id) for b in BUNDLES}

    # a .p12 the Mac's keychain accepts (its importer wants the older SHA-1 / 3DES packing), with a throwaway password
    from cryptography.hazmat.primitives.serialization import pkcs12
    import secrets
    password = secrets.token_hex(16).encode()
    enc = (serialization.PrivateFormat.PKCS12.encryption_builder().kdf_rounds(50000)
           .key_cert_algorithm(pkcs12.PBES.PBESv1SHA1And3KeyTripleDESCBC).hmac_hash(hashes.SHA1()).build(password))
    p12 = pkcs12.serialize_key_and_certificates(b"Time2Play distribution", key, x509.load_der_x509_certificate(cert_der), None, enc)
    with open(os.path.join(outdir, "dist.p12"), "wb") as f:
        f.write(p12)
    with open(os.path.join(outdir, "dist.p12.pass"), "wb") as f:
        f.write(password)
    with open(os.environ.get("GITHUB_ENV", os.devnull), "a") as env:
        for b, profile in profiles.items():
            _, file, var = BUNDLES[b]
            with open(os.path.join(outdir, f"{file}.mobileprovision"), "wb") as f:
                f.write(base64.b64decode(profile["attributes"]["profileContent"]))
            env.write(f"{var}={profile['attributes']['name']}\n")


def bundle_id(identifier):
    """The App ID's App Store Connect id. The widget's is registered here if it's missing (it needs no capabilities:
    the Keychain group it shares with the app comes with any App Store profile); the app's must already exist."""
    found = call("GET", "/v1/bundleIds" + q({"filter[identifier]": identifier, "limit": 20}))["data"]
    found = [b for b in found if b["attributes"]["identifier"] == identifier]
    if found:
        print(f"App ID {identifier}: registered")
        return found[0]["id"]
    if identifier == BUNDLE_ID:
        die(f"The App ID {identifier} isn't registered")
    made = call("POST", "/v1/bundleIds", {"data": {"type": "bundleIds", "attributes": {
        "identifier": identifier, "name": BUNDLES[identifier][0], "platform": "IOS"}}})["data"]
    print(f"App ID {identifier}: registered it now")
    return made["id"]


def profile_for(identifier, cert_id):
    bundle = bundle_id(identifier)
    caps = call("GET", f"/v1/bundleIds/{bundle}/bundleIdCapabilities")["data"]
    print("  capabilities: " + (", ".join(sorted(c["attributes"]["capabilityType"] for c in caps)) or "none"))
    name = f"{BUNDLES[identifier][0]} App Store {cert_id[:6]}"
    profile = None
    found = call("GET", "/v1/profiles" + q({"filter[name]": name, "filter[profileType]": "IOS_APP_STORE",
                                             "include": "certificates", "limit": 50}))
    for p in found["data"]:
        certs = [c["id"] for c in p["relationships"]["certificates"]["data"] or []]
        if p["attributes"]["profileState"] == "ACTIVE" and cert_id in certs:
            profile = p
    if profile:
        print(f"  App Store profile: found ({name})")
        return profile
    if found["data"]:  # same name but out of date (a capability changed): a fresh one with a dated name
        name = f"{name} {time.strftime('%Y%m%d%H%M')}"
    profile = call("POST", "/v1/profiles", {"data": {"type": "profiles", "attributes": {
        "name": name, "profileType": "IOS_APP_STORE"}, "relationships": {
        "bundleId": {"data": {"type": "bundleIds", "id": bundle}},
        "certificates": {"data": [{"type": "certificates", "id": cert_id}]}}}})["data"]
    print(f"  App Store profile: made ({name})")
    return profile


# ---------- after the upload ----------

def builds(app_id, number=None):
    params = {"filter[app]": app_id, "sort": "-uploadedDate", "limit": 20, "fields[builds]": "version,processingState,uploadedDate,expired"}
    if number:
        params["filter[version]"] = number
    return call("GET", "/v1/builds" + q(params))["data"]


def status():
    app = the_app()
    print(f"App: {app['attributes']['name']} ({app['id']})")
    for b in builds(app["id"]):
        a = b["attributes"]
        print(f"  build {a['version']}: {a['processingState']} (uploaded {a['uploadedDate']})")


def internal_testing(app_id, build_id=None):
    """Puts the build in front of Tyler's internal testers. Prints every testing group it sees (names only, never a key),
    so a run that can't find the group says what it found instead."""
    groups = call("GET", "/v1/betaGroups" + q({"filter[app]": app_id, "limit": 200,
                                                 "fields[betaGroups]": "name,isInternalGroup,hasAccessToAllBuilds"}))["data"]
    for g in groups:
        a = g["attributes"]
        print(f"Testing group: {a.get('name')} (internal: {a.get('isInternalGroup')}, every build: {a.get('hasAccessToAllBuilds')})")
    if not groups:
        print("Testing groups: none listed for this app")
    internal = [g for g in groups if g["attributes"].get("isInternalGroup")]
    if internal:
        group = internal[0]
        print(f"Internal testing group: {group['attributes']['name']} (already there)")
    else:
        try:
            group = call("POST", "/v1/betaGroups", {"data": {"type": "betaGroups", "attributes": {
                "name": "Tyler", "isInternalGroup": True, "hasAccessToAllBuilds": True},
                "relationships": {"app": {"data": {"type": "apps", "id": app_id}}}}})["data"]
            print("Internal testing group: made \"Tyler\" (every new build goes to it)")
        except SystemExit:
            print("::warning::No internal testing group, and App Store Connect wouldn't make one with this key. The build is "
                  "uploaded: in App Store Connect open the app, then TestFlight, then the + next to Internal Testing, name "
                  "the group, turn on automatic distribution, add yourself, and the build appears in the TestFlight app.")
            return
    # a group that doesn't get every build automatically gets this one by hand
    for g in internal or [group]:
        if build_id and not g["attributes"].get("hasAccessToAllBuilds"):
            try:
                call("POST", f"/v1/betaGroups/{g['id']}/relationships/builds", {"data": [{"type": "builds", "id": build_id}]})
                print(f"Added this build to {g['attributes'].get('name')}")
            except SystemExit:
                print(f"::warning::Couldn't add this build to {g['attributes'].get('name')}; add it in TestFlight")
    # add the Account Holder; internal testers have to be App Store Connect users
    try:
        users = call("GET", "/v1/users" + q({"filter[roles]": "ACCOUNT_HOLDER", "limit": 5}))["data"]
    except SystemExit:
        print("Couldn't list the team's users with this key; add yourself in TestFlight → Internal Testing")
        return
    have = call("GET", f"/v1/betaGroups/{group['id']}/betaTesters" + q({"limit": 50}))["data"]
    have_emails = {(t["attributes"].get("email") or "").lower() for t in have}
    for u in users:
        email = u["attributes"]["username"]
        print(f"::add-mask::{email}")
        if email.lower() in have_emails:
            print("The Account Holder is already an internal tester")
            continue
        try:
            call("POST", "/v1/betaTesters", {"data": {"type": "betaTesters", "attributes": {
                "email": email, "firstName": u["attributes"].get("firstName") or "Tyler",
                "lastName": u["attributes"].get("lastName") or "Locke"},
                "relationships": {"betaGroups": {"data": [{"type": "betaGroups", "id": group["id"]}]}}}})
            print("Added the Account Holder as an internal tester")
        except SystemExit:
            print("Couldn't add the Account Holder as a tester with this key; add yourself in TestFlight → Internal Testing")


def wait(number, minutes=40):
    app = the_app()
    end = time.time() + minutes * 60
    state = None
    while time.time() < end:
        found = builds(app["id"], number)
        if found:
            state = found[0]["attributes"]["processingState"]
            print(f"{time.strftime('%H:%M:%S')} build {number}: {state}")
            if state in ("VALID", "FAILED", "INVALID"):
                break
        else:
            print(f"{time.strftime('%H:%M:%S')} build {number}: not listed yet")
        time.sleep(60)
    with open(os.environ.get("GITHUB_STEP_SUMMARY", os.devnull), "a") as f:
        f.write(f"Build {number} on App Store Connect: {state or 'not listed yet'}\n")
    found = builds(app["id"], number)
    internal_testing(app["id"], found[0]["id"] if found and state == "VALID" else None)
    if state in ("FAILED", "INVALID"):
        die(f"Apple marked build {number} {state}; App Store Connect emails the reason")
    if state != "VALID":
        print(f"Build {number} is still processing after {minutes} minutes; it shows in TestFlight when Apple finishes")


# ---------- the App Store listing (#407): fills things in, never submits ----------

SHOT_TYPES = {"iphone": "APP_IPHONE_67", "ipad": "APP_IPAD_PRO_3GEN_129"}  # 6.9" iPhone, 13" iPad


def one(path):
    got = call("GET", path, ok_missing=True)
    return got.get("data") if got else None


def upload_shot(set_id, path):
    data = open(path, "rb").read()
    made = call("POST", "/v1/appScreenshots", {"data": {"type": "appScreenshots", "attributes": {
        "fileName": os.path.basename(path), "fileSize": len(data)},
        "relationships": {"appScreenshotSet": {"data": {"type": "appScreenshotSets", "id": set_id}}}}})["data"]
    for op in made["attributes"]["uploadOperations"]:
        part = data[op["offset"]:op["offset"] + op["length"]]
        req = urllib.request.Request(op["url"], data=part, method=op["method"],
                                     headers={h["name"]: h["value"] for h in op.get("requestHeaders", [])})
        urllib.request.urlopen(req, timeout=120).read()
    call("PATCH", f"/v1/appScreenshots/{made['id']}", {"data": {"type": "appScreenshots", "id": made["id"], "attributes": {
        "uploaded": True, "sourceFileChecksum": hashlib.md5(data).hexdigest()}}})


def store(meta_path, shots_dir):
    meta = json.load(open(meta_path))
    loc = meta["locale"]
    app = the_app()
    app_id = app["id"]
    print(f"App: {app['attributes']['name']} ({app_id})")

    # the version (1.0, still being prepared)
    versions = call("GET", f"/v1/apps/{app_id}/appStoreVersions" + q({"filter[platform]": "IOS", "limit": 20}))["data"]
    editable = [v for v in versions if v["attributes"].get("appStoreState") in
                ("PREPARE_FOR_SUBMISSION", "DEVELOPER_REJECTED", "REJECTED", "METADATA_REJECTED")]
    if editable:
        version = editable[0]
    else:
        version = call("POST", "/v1/appStoreVersions", {"data": {"type": "appStoreVersions", "attributes": {
            "platform": "IOS", "versionString": VERSION},
            "relationships": {"app": {"data": {"type": "apps", "id": app_id}}}}})["data"]
    vid = version["id"]
    call("PATCH", f"/v1/appStoreVersions/{vid}", {"data": {"type": "appStoreVersions", "id": vid, "attributes": {
        "copyright": meta["copyright"]}}})
    print(f"Version {version['attributes']['versionString']}: {version['attributes'].get('appStoreState')}")

    # the version's words
    fields = {k: meta[k] for k in ("description", "keywords", "promotionalText", "supportUrl", "marketingUrl")}
    if meta.get("whatsNew"):   # an update's "What's New in This Version" (not allowed on a first version)
        fields["whatsNew"] = meta["whatsNew"]
    locs = call("GET", f"/v1/appStoreVersions/{vid}/appStoreVersionLocalizations")["data"]
    vloc = next((l for l in locs if l["attributes"]["locale"] == loc), None)
    if vloc:
        call("PATCH", f"/v1/appStoreVersionLocalizations/{vloc['id']}", {"data": {
            "type": "appStoreVersionLocalizations", "id": vloc["id"], "attributes": fields}})
    else:
        vloc = call("POST", "/v1/appStoreVersionLocalizations", {"data": {"type": "appStoreVersionLocalizations",
            "attributes": dict(fields, locale=loc),
            "relationships": {"appStoreVersion": {"data": {"type": "appStoreVersions", "id": vid}}}}})["data"]
    print("Description, keywords, promotional text, support and marketing links: set")

    # the app's name, subtitle, privacy link and category
    infos = call("GET", f"/v1/apps/{app_id}/appInfos")["data"]
    info = next((i for i in infos if i["attributes"].get("appStoreState") != "READY_FOR_SALE"), infos[0])
    ilocs = call("GET", f"/v1/appInfos/{info['id']}/appInfoLocalizations")["data"]
    iloc = next((l for l in ilocs if l["attributes"]["locale"] == loc), None)
    attrs = {"name": meta["name"], "subtitle": meta["subtitle"], "privacyPolicyUrl": meta["privacyPolicyUrl"]}
    if iloc:
        call("PATCH", f"/v1/appInfoLocalizations/{iloc['id']}", {"data": {"type": "appInfoLocalizations", "id": iloc["id"], "attributes": attrs}})
    print("Name, subtitle and privacy policy link: set")
    rel = {"primaryCategory": meta["primaryCategory"], "primarySubcategoryOne": meta["primarySubcategoryOne"],
           "primarySubcategoryTwo": meta["primarySubcategoryTwo"]}
    call("PATCH", f"/v1/appInfos/{info['id']}", {"data": {"type": "appInfos", "id": info["id"], "relationships": {
        k: {"data": {"type": "appCategories", "id": v}} for k, v in rel.items()}}})
    print("Category: Games (Card, Family)")

    # App Review's details; the review key goes in from the secret, here only
    r = meta["review"]
    notes = r["notes"].replace("{REVIEW_KEY}", os.environ.get("REVIEW_SIGNIN_KEY") or "(the review key: add it here)")
    rattrs = {"contactFirstName": r["contactFirstName"], "contactLastName": r["contactLastName"],
              "contactEmail": r["contactEmail"], "demoAccountRequired": r["demoAccountRequired"], "notes": notes}
    detail = one(f"/v1/appStoreVersions/{vid}/appStoreReviewDetail")
    if detail:
        call("PATCH", f"/v1/appStoreReviewDetails/{detail['id']}", {"data": {"type": "appStoreReviewDetails", "id": detail["id"], "attributes": rattrs}})
    else:
        call("POST", "/v1/appStoreReviewDetails", {"data": {"type": "appStoreReviewDetails", "attributes": rattrs,
            "relationships": {"appStoreVersion": {"data": {"type": "appStoreVersions", "id": vid}}}}})
    print("Review notes and contact: set (the phone number is Tyler's to add)")

    # screenshots: only into an empty set, so a re-run never doubles them. "replaceShots" (#595: the games' new names
    # are on the new screenshots) first clears this version's sets once, for a version still being prepared
    sets = call("GET", f"/v1/appStoreVersionLocalizations/{vloc['id']}/appScreenshotSets")["data"]
    if meta.get("replaceShots") == version["attributes"]["versionString"]:
        made = os.listdir(shots_dir)
        for device, kind in SHOT_TYPES.items():
            x = next((x for x in sets if x["attributes"]["screenshotDisplayType"] == kind), None)
            if not x or not any(f.startswith(f"store-{device}-") and f.endswith(".png") for f in made):
                continue   # nothing new to put in its place: leave it as it is
            old = call("GET", f"/v1/appScreenshotSets/{x['id']}/appScreenshots")["data"]
            for o in old:
                call("DELETE", f"/v1/appScreenshots/{o['id']}")
            print(f"Screenshots {kind}: cleared {len(old)} for the new ones")
    for device, kind in SHOT_TYPES.items():
        files = sorted(f for f in os.listdir(shots_dir) if f.startswith(f"store-{device}-") and f.endswith(".png")
                       and f not in meta.get("skipShots", []))
        if not files:
            print(f"Screenshots {kind}: none made")
            continue
        s = next((x for x in sets if x["attributes"]["screenshotDisplayType"] == kind), None)
        if not s:
            s = call("POST", "/v1/appScreenshotSets", {"data": {"type": "appScreenshotSets", "attributes": {
                "screenshotDisplayType": kind}, "relationships": {"appStoreVersionLocalization": {
                "data": {"type": "appStoreVersionLocalizations", "id": vloc["id"]}}}}})["data"]
        have = call("GET", f"/v1/appScreenshotSets/{s['id']}/appScreenshots")["data"]
        if have:
            print(f"Screenshots {kind}: {len(have)} already there, left as they are")
            continue
        for f in files:
            upload_shot(s["id"], os.path.join(shots_dir, f))
        print(f"Screenshots {kind}: uploaded {len(files)}")

    # the newest processed build, picked for this version (Tyler can pick another)
    done = [b for b in builds(app_id) if b["attributes"]["processingState"] == "VALID" and not b["attributes"].get("expired")]
    if done:
        b = done[0]
        call("PATCH", f"/v1/appStoreVersions/{vid}/relationships/build", {"data": {"type": "builds", "id": b["id"]}})
        print(f"Build for review: {b['attributes']['version']}")
    else:
        print("Build for review: none processed yet")
    print("Not submitted. Submitting for review is Tyler's call.")


# ---------- Game Center (#541): the capability, the leaderboards and the achievements; never submits ----------

GC = {
    "leaderboards": [
        # #595: the games' names changed (Hot Dice is 10,000, Roll Call is Yacht Dice); the ids never change
        ("t2p.best.hotdice", "10,000 best score", "10,000", "points", "point"),
        ("t2p.best.rollcall", "Yacht Dice best score", "Yacht Dice", "points", "point"),
        ("t2p.best.closeenough", "Close Enough best score", "Close Enough", "points", "point"),
    ],
    # (id, name, points, before, after): the app's own achievements (T2PCore Stats.swift Achievement.all)
    "achievements": [
        ("t2p.first_win", "First win", 10, "Win a game.", "You won a game."),
        ("t2p.games_10", "Regular", 20, "Play 10 games.", "You played 10 games."),
        ("t2p.games_50", "Part of the furniture", 50, "Play 50 games.", "You played 50 games."),
        ("t2p.wins_5", "On a roll", 30, "Win 5 games.", "You won 5 games."),
        ("t2p.all_four", "All-rounder", 30, "Play all four games.", "You played all four games."),
        ("t2p.overdraft_win", "Empty-handed", 15, "Win a hand of Overdraft.", "You won a hand of Overdraft."),
        ("t2p.hotdice_10k", "Ten thousand", 40, "Win a game of 10,000 played to the full 10,000.", "You won a game of 10,000 played to the full 10,000."),
        ("t2p.rollcall_full", "Full card", 50, "Finish Yacht Dice with points in every box.", "You finished Yacht Dice with points in every box."),
        ("t2p.rollcall_300", "Three hundred club", 40, "Score 300 or more in Yacht Dice.", "You scored 300 or more in Yacht Dice."),
        ("t2p.closeenough_bullseye", "Bullseye", 25, "Score full points on a Close Enough question.", "You scored full points on a Close Enough question."),
    ],
}


def badge_png(path, seed):
    """A plain 512 x 512 badge (a gold ring on navy) for an achievement's image, made with the standard library."""
    import struct, zlib, math
    n = 512
    rows = []
    for y in range(n):
        row = bytearray([0])
        for x in range(n):
            d = math.hypot(x - n / 2, y - n / 2)
            if 150 < d < 190 or d < 40 + (seed % 5) * 12:
                row += bytes((0xE9, 0xB4, 0x5A))
            else:
                row += bytes((0x0B, 0x11, 0x21))
        rows.append(bytes(row))
    raw = zlib.compress(b"".join(rows), 9)
    def chunk(t, d): return struct.pack(">I", len(d)) + t + d + struct.pack(">I", zlib.crc32(t + d) & 0xFFFFFFFF)
    with open(path, "wb") as f:
        f.write(b"\x89PNG\r\n\x1a\n" + chunk(b"IHDR", struct.pack(">IIBBBBB", n, n, 8, 2, 0, 0, 0)) + chunk(b"IDAT", raw) + chunk(b"IEND", b""))


def upload_asset(kind, rel, parent_id, path):
    data = open(path, "rb").read()
    made = call("POST", f"/v1/{kind}", {"data": {"type": kind, "attributes": {"fileName": os.path.basename(path), "fileSize": len(data)},
                "relationships": {rel: {"data": {"type": rel + "s", "id": parent_id}}}}})["data"]
    for op in made["attributes"]["uploadOperations"]:
        part = data[op["offset"]:op["offset"] + op["length"]]
        req = urllib.request.Request(op["url"], data=part, method=op["method"],
                                     headers={h["name"]: h["value"] for h in op.get("requestHeaders", [])})
        urllib.request.urlopen(req, timeout=120).read()
    call("PATCH", f"/v1/{kind}/{made['id']}", {"data": {"type": kind, "id": made["id"], "attributes": {"uploaded": True}}})


def gamecenter():
    app = the_app()
    app_id = app["id"]
    print(f"App: {app['attributes']['name']} ({app_id})")

    # 1. the capability on the App ID (the next TestFlight run's profile then carries the entitlement)
    ids = [b for b in call("GET", "/v1/bundleIds" + q({"filter[identifier]": BUNDLE_ID}))["data"] if b["attributes"]["identifier"] == BUNDLE_ID]
    bundle = ids[0]["id"]
    caps = [c["attributes"]["capabilityType"] for c in call("GET", f"/v1/bundleIds/{bundle}/bundleIdCapabilities")["data"]]
    if "GAME_CENTER" in caps:
        print("Game Center capability: already on the App ID")
    else:
        try:
            call("POST", "/v1/bundleIdCapabilities", {"data": {"type": "bundleIdCapabilities", "attributes": {"capabilityType": "GAME_CENTER"},
                 "relationships": {"bundleId": {"data": {"type": "bundleIds", "id": bundle}}}}})
            print("Game Center capability: turned on for the App ID")
        except SystemExit:
            print("::warning::Couldn't turn on Game Center for the App ID with this key (see Apple's answer above)")

    # 2. Game Center for the app
    detail = one(f"/v1/apps/{app_id}/gameCenterDetail")
    if detail:
        print(f"Game Center for the app: already on ({detail['id']})")
    else:
        detail = call("POST", "/v1/gameCenterDetails", {"data": {"type": "gameCenterDetails", "attributes": {},
                      "relationships": {"app": {"data": {"type": "apps", "id": app_id}}}}})["data"]
        print(f"Game Center for the app: turned on ({detail['id']})")
    did = detail["id"]

    # 3. leaderboards (best score, higher is better), each with its English name
    have = {l["attributes"]["vendorIdentifier"]: l for l in
            call("GET", f"/v1/gameCenterDetails/{did}/gameCenterLeaderboards" + q({"limit": 200}))["data"]}
    for vid, ref, name, suffix, single in GC["leaderboards"]:
        if vid in have:
            # #595: one that's there gets its English name brought up to date (never its id)
            lid = have[vid]["id"]
            if have[vid]["attributes"].get("referenceName") != ref:
                call("PATCH", f"/v1/gameCenterLeaderboards/{lid}", {"data": {"type": "gameCenterLeaderboards", "id": lid, "attributes": {"referenceName": ref}}})
            locs = call("GET", f"/v1/gameCenterLeaderboards/{lid}/localizations")["data"]
            en = next((l for l in locs if l["attributes"]["locale"] == "en-US"), None)
            if en and en["attributes"].get("name") != name:
                call("PATCH", f"/v1/gameCenterLeaderboardLocalizations/{en['id']}", {"data": {"type": "gameCenterLeaderboardLocalizations", "id": en["id"], "attributes": {"name": name}}})
                print(f"Leaderboard {vid}: there, renamed to {name}")
            else:
                print(f"Leaderboard {vid}: there")
            continue
        lb = call("POST", "/v1/gameCenterLeaderboards", {"data": {"type": "gameCenterLeaderboards", "attributes": {
            "referenceName": ref, "vendorIdentifier": vid, "defaultFormatter": "INTEGER", "submissionType": "BEST_SCORE",
            "scoreSortType": "DESC", "scoreRangeStart": "0", "scoreRangeEnd": "1000000"},
            "relationships": {"gameCenterDetail": {"data": {"type": "gameCenterDetails", "id": did}}}}})["data"]
        call("POST", "/v1/gameCenterLeaderboardLocalizations", {"data": {"type": "gameCenterLeaderboardLocalizations", "attributes": {
            "locale": "en-US", "name": name, "formatterSuffix": " " + suffix, "formatterSuffixSingular": " " + single},
            "relationships": {"gameCenterLeaderboard": {"data": {"type": "gameCenterLeaderboards", "id": lb["id"]}}}}})
        print(f"Leaderboard {vid}: made")

    # 4. achievements, each with its English words and a badge
    have = {a["attributes"]["vendorIdentifier"]: a for a in
            call("GET", f"/v1/gameCenterDetails/{did}/gameCenterAchievements" + q({"limit": 200}))["data"]}
    tmp = os.environ.get("RUNNER_TEMP", "/tmp")
    for k, (vid, name, points, before, after) in enumerate(GC["achievements"]):
        if vid in have:
            # #595: one that's there gets its English words brought up to date (never its id)
            locs = call("GET", f"/v1/gameCenterAchievements/{have[vid]['id']}/localizations")["data"]
            en = next((l for l in locs if l["attributes"]["locale"] == "en-US"), None)
            want = {"name": name, "beforeEarnedDescription": before, "afterEarnedDescription": after}
            if en and any(en["attributes"].get(f) != v for f, v in want.items()):
                call("PATCH", f"/v1/gameCenterAchievementLocalizations/{en['id']}", {"data": {"type": "gameCenterAchievementLocalizations", "id": en["id"], "attributes": want}})
                print(f"Achievement {vid}: there, words brought up to date")
            else:
                print(f"Achievement {vid}: there")
            continue
        a = call("POST", "/v1/gameCenterAchievements", {"data": {"type": "gameCenterAchievements", "attributes": {
            "referenceName": name, "vendorIdentifier": vid, "points": points, "showBeforeEarned": True, "repeatable": False},
            "relationships": {"gameCenterDetail": {"data": {"type": "gameCenterDetails", "id": did}}}}})["data"]
        loc = call("POST", "/v1/gameCenterAchievementLocalizations", {"data": {"type": "gameCenterAchievementLocalizations", "attributes": {
            "locale": "en-US", "name": name, "beforeEarnedDescription": before, "afterEarnedDescription": after},
            "relationships": {"gameCenterAchievement": {"data": {"type": "gameCenterAchievements", "id": a["id"]}}}}})["data"]
        png = os.path.join(tmp, f"badge-{k}.png")
        badge_png(png, k)
        try:
            upload_asset("gameCenterAchievementImages", "gameCenterAchievementLocalization", loc["id"], png)
            print(f"Achievement {vid}: made, with its badge")
        except SystemExit:
            print(f"::warning::Achievement {vid}: made; its badge didn't upload (add one in App Store Connect before release)")
    print("Not submitted. Game Center's leaderboards and achievements go live with an App Store version, which is Tyler's call.")


# ---------- submitting for App Review (#407): only when Tyler says "submit", started by hand (submit.yml) ----------

def submit(expected_build):
    """Sends the version being prepared to App Review, with the build Tyler approved. Checks first that the version
    holds exactly that build, and stops (changing nothing) if anything doesn't match."""
    app = the_app()
    app_id = app["id"]
    versions = call("GET", f"/v1/apps/{app_id}/appStoreVersions" + q({"filter[platform]": "IOS", "limit": 20}))["data"]
    ready = [v for v in versions if v["attributes"].get("appStoreState") in
             ("PREPARE_FOR_SUBMISSION", "DEVELOPER_REJECTED", "REJECTED", "METADATA_REJECTED")]
    if not ready:
        states = ", ".join(f"{v['attributes'].get('versionString')}: {v['attributes'].get('appStoreState')}" for v in versions)
        die(f"No version waiting to be submitted ({states or 'none'}).")
    version = ready[0]
    vid = version["id"]
    build = one(f"/v1/appStoreVersions/{vid}/build")
    number = build["attributes"]["version"] if build else None
    print(f"Version {version['attributes']['versionString']} ({version['attributes']['appStoreState']}), build {number}")
    if str(number) != str(expected_build):
        die(f"The version holds build {number}, not build {expected_build}. Nothing submitted.")
    if build["attributes"].get("processingState") != "VALID":
        die(f"Build {number} isn't VALID ({build['attributes'].get('processingState')}). Nothing submitted.")

    # Game Center (#541): the version has to say it uses Game Center (the build carries the entitlement), and the
    # leaderboards and achievements go with it. Each is added once; one that fails is reported, not fatal.
    gcv = one(f"/v1/appStoreVersions/{vid}/gameCenterAppVersion")
    if not gcv:
        call("POST", "/v1/gameCenterAppVersions", {"data": {"type": "gameCenterAppVersions", "relationships": {
            "appStoreVersion": {"data": {"type": "appStoreVersions", "id": vid}}}}})
        print("Game Center: turned on for this version")
    detail = one(f"/v1/apps/{app_id}/gameCenterDetail")
    if detail:
        did = detail["id"]
        for kind, rel, rtype in (("Leaderboard", "gameCenterLeaderboard", "gameCenterLeaderboards"),
                                 ("Achievement", "gameCenterAchievement", "gameCenterAchievements")):
            things = call("GET", f"/v1/gameCenterDetails/{did}/{rtype}" + q({"limit": 200}))["data"]
            released = call("GET", f"/v1/gameCenterDetails/{did}/{kind.lower()}Releases" + q({"limit": 200, "include": rel}), ok_missing=True)
            have = {((r.get("relationships", {}).get(rel, {}) or {}).get("data") or {}).get("id") for r in ((released or {}).get("data") or [])}
            added = 0
            for t in things:
                if t["id"] in have:
                    continue
                try:
                    call("POST", f"/v1/gameCenter{kind}Releases", {"data": {"type": f"gameCenter{kind}Releases", "relationships": {
                        rel: {"data": {"type": rtype, "id": t["id"]}},
                        "gameCenterDetail": {"data": {"type": "gameCenterDetails", "id": did}}}}})
                    added += 1
                except SystemExit as e:
                    print(f"Game Center: couldn't add {kind.lower()} {t['attributes'].get('referenceName')}: {e}")
            print(f"Game Center: {kind.lower()}s with this version: {len(things)} ({added} added now)")

    # a review submission for the app (reuse one still being put together), the version in it, then send it
    open_subs = call("GET", "/v1/reviewSubmissions" + q({"filter[app]": app_id, "filter[platform]": "IOS",
                                                           "filter[state]": "READY_FOR_REVIEW", "limit": 5}), ok_missing=True)
    sub = (open_subs or {}).get("data") or []
    sub = sub[0] if sub else call("POST", "/v1/reviewSubmissions", {"data": {"type": "reviewSubmissions",
        "attributes": {"platform": "IOS"}, "relationships": {"app": {"data": {"type": "apps", "id": app_id}}}}})["data"]
    items = call("GET", f"/v1/reviewSubmissions/{sub['id']}/items", ok_missing=True)
    has_version = any((i.get("relationships", {}).get("appStoreVersion", {}).get("data") or {}).get("id") == vid
                      for i in ((items or {}).get("data") or []))
    if not has_version:
        call("POST", "/v1/reviewSubmissionItems", {"data": {"type": "reviewSubmissionItems", "relationships": {
            "reviewSubmission": {"data": {"type": "reviewSubmissions", "id": sub["id"]}},
            "appStoreVersion": {"data": {"type": "appStoreVersions", "id": vid}}}}})
    done = call("PATCH", f"/v1/reviewSubmissions/{sub['id']}", {"data": {"type": "reviewSubmissions", "id": sub["id"],
        "attributes": {"submitted": True}}})["data"]
    print(f"Submitted for App Review: build {number}, submission {done['attributes'].get('state')}")


# ---------- the tip jar (#598): three consumable in-app purchases; never submits ----------

IAP = [
    # (product id, name, US price, description: 55 characters at most)
    ("live.time2play.app.tip.small", "Tip", "1.99", "A coffee’s worth of thanks. Tips unlock nothing."),
    ("live.time2play.app.tip.big", "Big tip", "4.99", "A round of thanks for the table. Tips unlock nothing."),
    ("live.time2play.app.tip.huge", "Huge tip", "9.99", "Game night’s on you. Tips unlock nothing."),
]
# The EU's 27 (App Store territory ids): the app isn't offered there (Tyler, Nov 20 2026), so neither are the tips
EU = {"AUT", "BEL", "BGR", "HRV", "CYP", "CZE", "DNK", "EST", "FIN", "FRA", "DEU", "GRC", "HUN", "IRL", "ITA", "LVA",
      "LTU", "LUX", "MLT", "NLD", "POL", "PRT", "ROU", "SVK", "SVN", "ESP", "SWE"}
IAP_REVIEW_NOTE = ("A tip jar: You, then Tip jar (and a small line on a game's end screen). Tips are thank-yous only: they "
                   "unlock nothing, and every game stays free. A Supporter star then shows on the player's own You screen, on "
                   "that phone only.")


def iap(shot=None):
    """Makes the tip jar's products in App Store Connect, each only if it's missing (safe to run again). Apple refuses
    until the Paid Apps agreement is in effect; its answer is printed and nothing else changes."""
    app = the_app()
    app_id = app["id"]
    print(f"App: {app['attributes']['name']} ({app_id})")
    have = {i["attributes"]["productId"]: i for i in
            call("GET", f"/v1/apps/{app_id}/inAppPurchasesV2" + q({"limit": 200}))["data"]}
    territories = None
    for pid, name, price, desc in IAP:
        if pid in have:
            item = have[pid]
            print(f"{pid}: there ({item['attributes'].get('state')})")
        else:
            item = call("POST", "/v2/inAppPurchases", {"data": {"type": "inAppPurchases", "attributes": {
                "name": name, "productId": pid, "inAppPurchaseType": "CONSUMABLE", "reviewNote": IAP_REVIEW_NOTE,
                "familySharable": False}, "relationships": {"app": {"data": {"type": "apps", "id": app_id}}}}})["data"]
            print(f"{pid}: made")
        iid = item["id"]
        # the English name and description
        locs = call("GET", f"/v2/inAppPurchases/{iid}/inAppPurchaseLocalizations")["data"]
        if not any(l["attributes"]["locale"] == "en-US" for l in locs):
            call("POST", "/v1/inAppPurchaseLocalizations", {"data": {"type": "inAppPurchaseLocalizations", "attributes": {
                "locale": "en-US", "name": name, "description": desc},
                "relationships": {"inAppPurchaseV2": {"data": {"type": "inAppPurchases", "id": iid}}}}})
            print(f"{pid}: English name and description set")
        # the price: the US price point, the other territories follow it (Apple's equalization)
        sched = call("GET", f"/v2/inAppPurchases/{iid}/iapPriceSchedule", ok_missing=True)
        if not (sched or {}).get("data"):
            points = call("GET", f"/v2/inAppPurchases/{iid}/pricePoints" + q({"filter[territory]": "USA", "limit": 8000}))["data"]
            pp = next((x for x in points if x["attributes"].get("customerPrice") == price), None)
            if not pp:
                die(f"{pid}: no US price point at {price}")
            call("POST", "/v1/inAppPurchasePriceSchedules", {
                "data": {"type": "inAppPurchasePriceSchedules", "relationships": {
                    "inAppPurchase": {"data": {"type": "inAppPurchases", "id": iid}},
                    "baseTerritory": {"data": {"type": "territories", "id": "USA"}},
                    "manualPrices": {"data": [{"type": "inAppPurchasePrices", "id": "${price}"}]}}},
                "included": [{"type": "inAppPurchasePrices", "id": "${price}", "attributes": {"startDate": None},
                              "relationships": {"inAppPurchasePricePoint": {"data": {"type": "inAppPurchasePricePoints", "id": pp["id"]}}}}]})
            print(f"{pid}: priced at ${price} (US)")
        # where it's sold: everywhere the app is. Not the EU (Tyler, Nov 20 2026): the app is off there, so no trader
        # status (the Digital Services Act puts a trader's address on the store page) is needed
        avail = call("GET", f"/v2/inAppPurchases/{iid}/inAppPurchaseAvailability", ok_missing=True)
        if not (avail or {}).get("data"):
            if territories is None:
                territories = [t["id"] for t in call("GET", "/v1/territories" + q({"limit": 200}))["data"]
                               if t["id"] not in EU]
            call("POST", "/v1/inAppPurchaseAvailabilities", {"data": {"type": "inAppPurchaseAvailabilities",
                "attributes": {"availableInNewTerritories": True}, "relationships": {
                    "inAppPurchase": {"data": {"type": "inAppPurchases", "id": iid}},
                    "availableTerritories": {"data": [{"type": "territories", "id": t} for t in territories]}}}})
            print(f"{pid}: available in {len(territories)} territories")
        # App Review's screenshot of the Tip jar
        if shot:
            got = call("GET", f"/v2/inAppPurchases/{iid}/appStoreReviewScreenshot", ok_missing=True)
            if not (got or {}).get("data"):
                data = open(shot, "rb").read()
                made = call("POST", "/v1/inAppPurchaseAppStoreReviewScreenshots", {"data": {
                    "type": "inAppPurchaseAppStoreReviewScreenshots",
                    "attributes": {"fileName": os.path.basename(shot), "fileSize": len(data)},
                    "relationships": {"inAppPurchaseV2": {"data": {"type": "inAppPurchases", "id": iid}}}}})["data"]
                for op in made["attributes"]["uploadOperations"]:
                    part = data[op["offset"]:op["offset"] + op["length"]]
                    req = urllib.request.Request(op["url"], data=part, method=op["method"],
                                                 headers={h["name"]: h["value"] for h in op.get("requestHeaders", [])})
                    urllib.request.urlopen(req, timeout=120).read()
                call("PATCH", f"/v1/inAppPurchaseAppStoreReviewScreenshots/{made['id']}", {"data": {
                    "type": "inAppPurchaseAppStoreReviewScreenshots", "id": made["id"],
                    "attributes": {"uploaded": True, "sourceFileChecksum": hashlib.md5(data).hexdigest()}}})
                print(f"{pid}: review screenshot uploaded")
    print("Not submitted. The first tips go to App Review with the next app version: pick them on that version's page "
          "(In-App Purchases) before submitting, which is Tyler's call.")


if __name__ == "__main__":
    cmd = sys.argv[1] if len(sys.argv) > 1 else ""
    if cmd == "signing":
        signing(sys.argv[2])
    elif cmd == "wait":
        wait(sys.argv[2])
    elif cmd == "status":
        status()
    elif cmd == "gamecenter":
        gamecenter()
    elif cmd == "store":
        store(sys.argv[2], sys.argv[3])
    elif cmd == "submit":
        submit(sys.argv[2])
    elif cmd == "iap":
        iap(sys.argv[2] if len(sys.argv) > 2 else None)
    else:
        die(__doc__)
