"""Alfred Script Filter template: builds a static menu of URL options.

Run with an absolute interpreter (Alfred has a minimal PATH):
    /usr/bin/python3 scriptfilter.py

Stdlib only, so the system python3 can run it regardless of the user's
default python3 (Homebrew/pyenv are NOT on Alfred's PATH).
"""

import json
from urllib.parse import quote

BASE = "https://example.atlassian.net/issues/?jql="

# (title, subtitle, raw query that becomes part of the URL)
OPTIONS = [
    ("My open tasks", "Assigned to me, not done",
     "assignee = currentUser() AND statusCategory != Done ORDER BY updated DESC"),
    ("Mentions me", "Text/comments mention me, open",
     'text ~ "me" AND statusCategory != Done ORDER BY updated DESC'),
]

items = [
    {
        "title": title,
        "subtitle": subtitle,
        "arg": BASE + quote(query),  # arg flows to Open URL as {query}
        "autocomplete": title,
    }
    for title, subtitle, query in OPTIONS
]

print(json.dumps({"items": items}))
