#!/usr/bin/env python3
"""Writes two weeks of believable sample usage for screenshots and demos."""
import datetime as dt, json, os, random, sys

out = sys.argv[1]
os.makedirs(out, exist_ok=True)
random.seed(7)
work = ["a:Xcode", "a:Terminal", "a:Notion", "a:Mail", "s:github.com", "s:docs.google.com", "s:claude.ai", "s:meet.google.com"]
neutral = ["a:Finder", "a:Spotify", "s:wikipedia.org", "a:Google Chrome"]
fun = ["s:youtube.com", "s:instagram.com", "s:reddit.com", "s:x.com"]
today = dt.date.today()
for back in range(14):
    day = today - dt.timedelta(days=back)
    if back and day.weekday() >= 5 and random.random() < 0.6:
        continue
    hours = {}
    last = 18 if back else min(18, dt.datetime.now().hour)
    for hour in range(8, last + 1):
        keys, left = {}, random.uniform(1800, 3300)
        drift = 0.45 if hour in (14, 15, 21) else 0.15
        while left > 120:
            pool = fun if random.random() < drift else neutral if random.random() < 0.2 else work
            chunk = min(left, random.uniform(120, 900))
            key = random.choice(pool)
            keys[key] = keys.get(key, 0) + chunk
            left -= chunk
        hours[str(hour)] = keys
    with open(f"{out}/{day}.json", "w") as file:
        json.dump({"hours": hours}, file)
print(f"Beispieldaten in {out}")
