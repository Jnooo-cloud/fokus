#!/usr/bin/env python3
"""One-off: copies ActivityWatch history into Fokus' usage files. Days that already have Fokus data are left alone."""
import concurrent.futures, datetime as dt, json, os, sys, urllib.request

API = "http://localhost:5600/api/0/"
OUT = os.path.expanduser("~/Library/Application Support/Fokus/usage")
BROWSERS = {"Google Chrome", "Safari", "Microsoft Edge"}


def call(path, body=None):
    data = json.dumps(body).encode() if body is not None else None
    request = urllib.request.Request(API + path, data=data, headers={"Content-Type": "application/json"})
    return json.load(urllib.request.urlopen(request, timeout=120))


def query(host, web, periods):
    lines = [f'afk = flood(query_bucket("aw-watcher-afk_{host}"));', 'afk = filter_keyvals(afk, "status", ["not-afk"]);',
             f'win = flood(query_bucket("aw-watcher-window_{host}"));', 'win = filter_period_intersect(win, afk);',
             'apps = merge_events_by_keys(win, ["app"]);']
    if web:
        lines += [f'web = flood(query_bucket("{web}"));', 'chrome = filter_keyvals(win, "app", ["Google Chrome"]);',
                  'web = filter_period_intersect(web, chrome);', 'web = split_url_events(web);',
                  'sites = merge_events_by_keys(web, ["$domain"]);']
    else:
        lines.append('sites = [];')
    lines.append('RETURN = {"apps": apps, "sites": sites};')
    return call("query/", {"query": lines, "timeperiods": periods})


def day(date, hosts, web):
    tz = dt.datetime.now().astimezone().tzinfo
    start = dt.datetime.combine(date, dt.time(), tz)
    hours = [start + dt.timedelta(hours=h) for h in range(24)]
    periods = [f"{h.isoformat()}/{(h + dt.timedelta(hours=1)).isoformat()}" for h in hours]
    result = {}
    for host in hosts:
        for hour, period in enumerate(query(host, web, periods)):
            sites = {e["data"].get("$domain"): e["duration"] for e in period["sites"] if e["data"].get("$domain")}
            keys = result.setdefault(str(hour), {})
            browser = 0.0
            for event in period["apps"]:
                name = event["data"].get("app")
                if not name or name == "Fokus":
                    continue
                if name in BROWSERS:
                    browser += event["duration"]
                else:
                    keys["a:" + name] = keys.get("a:" + name, 0) + event["duration"]
            for name, seconds in sites.items():
                keys["s:" + name] = keys.get("s:" + name, 0) + seconds
            rest = browser - sum(sites.values())
            if rest >= 1:
                keys["a:Google Chrome"] = keys.get("a:Google Chrome", 0) + rest
    return date, {h: k for h, k in result.items() if k}


def main():
    buckets = call("buckets/")
    hosts = sorted(k.split("_", 1)[1] for k in buckets if k.startswith("aw-watcher-window_"))
    # The hostname changed over time, but it is one Mac with one Chrome watcher.
    web = max((k for k in buckets if k.startswith("aw-watcher-web-chrome_")), key=lambda k: buckets[k]["last_updated"], default=None)
    first = min(dt.date.fromisoformat(v["created"][:10]) for k, v in buckets.items() if k.startswith("aw-watcher-window_"))
    os.makedirs(OUT, exist_ok=True)
    today = dt.date.today()
    dates = [first + dt.timedelta(days=i) for i in range((today - first).days + 1)]
    dates = [d for d in dates if d == today or not os.path.exists(f"{OUT}/{d}.json")]
    done = 0
    with concurrent.futures.ThreadPoolExecutor(4) as pool:
        for date, hours in pool.map(lambda d: day(d, hosts, web), dates):
            if hours:
                path = f"{OUT}/{date}.json"
                if os.path.exists(path):  # Today: the seconds Fokus already tracked stay on top.
                    for hour, keys in json.load(open(path))["hours"].items():
                        for key, seconds in keys.items():
                            hours.setdefault(hour, {})[key] = hours.get(hour, {}).get(key, 0) + seconds
                with open(path, "w") as file:
                    json.dump({"hours": hours}, file)
                done += 1
    print(f"{done} Tage importiert, {first} bis {today}")


if __name__ == "__main__":
    sys.exit(main())
