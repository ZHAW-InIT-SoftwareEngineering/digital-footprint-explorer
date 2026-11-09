#!/usr/bin/env python3
"""Build the offline policy; update public copies only when explicitly requested."""
# [01] Keep one reviewed policy source; the app can be built and checked without any website files.
from pathlib import Path
from datetime import date
import argparse
import html
import json
import os
import sys

ROOT = Path(__file__).resolve().parents[1]
CONTENT = ROOT / 'Configuration/PrivacyPolicyContent.json'
SWIFT_LICENSE = '/*\n * Copyright (C) 2026 Zurich University of Applied Sciences, Switzerland\n *\n * This program is free software: you can redistribute it and/or modify\n * it under the terms of the GNU Affero General Public License as published by\n * the Free Software Foundation, either version 3 of the License, or\n * (at your option) any later version.\n *\n * This program is distributed in the hope that it will be useful,\n * but WITHOUT ANY WARRANTY; without even the implied warranty of\n * MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the\n * GNU Affero General Public License for more details.\n *\n * You should have received a copy of the GNU Affero General Public License\n * along with this program.  If not, see <https://www.gnu.org/licenses/>.\n */\n\n'


# [02] Use the same escaping rules for policy text so quotes and accents remain readable in the app.
def swift_string(value):

    return json.dumps(value, ensure_ascii=False)


# [03] The app copy is the default. Public copies change only when the caller asks for them.
def outputs(document, *, include_web=False):
    sections = document['sections']
    updated = date.fromisoformat(document['revision']).strftime('%d %B %Y').lstrip('0')
    policy_lines = [f"# {document['app_name']}", '', f"## {document['title']}", '', f"Last updated: {updated}", '']
    policy_lines += sum(([paragraph, ''] for paragraph in document['introduction']), [])
    for section in sections:
        policy_lines += [f"### {section['title']}", '']
        policy_lines += sum(([paragraph, ''] for paragraph in section['paragraphs']), [])
    markdown = '\n'.join(policy_lines)
    body = '\n'.join(f'<p>{html.escape(paragraph)}</p>' for paragraph in document['introduction'])
    for section in sections:
        body += f'\n<section aria-labelledby="{section["id"]}"><h2 id="{section["id"]}">{html.escape(section["title"])}</h2>\n'
        body += '\n'.join(f'<p>{html.escape(paragraph)}</p>' for paragraph in section['paragraphs'])
        body += '\n</section>'
    web = f'''<!doctype html>
<!-- [01] Generated from the reviewed policy source; change that source to keep the app and web text together. -->
<html lang="en">
<head>
  <meta charset="utf-8">
  <meta name="viewport" content="width=device-width, initial-scale=1">
  <meta name="description" content="How Digital Footprint Explorer handles your local history and optional Screen Time access.">
  <title>{html.escape(document['title'])} — {html.escape(document['app_name'])}</title>
  <link rel="stylesheet" href="style.css">
  <link rel="stylesheet" href="ios-pages.css">
</head>
<body class="dfe-site">
  <a class="skip-link" href="#policy-content">Skip to privacy policy</a>
  <header class="site-header">
    <div class="site-bar">
      <a class="site-brand" href="index.html" aria-label="Digital Footprint Explorer home">
        <img src="images/zhaw_rgb.png" alt="ZHAW">
      </a>
      <strong class="site-title">{html.escape(document['app_name'])}</strong>
      <nav class="site-nav" aria-label="Project pages">
        <a href="index.html">Project</a>
        <a href="support-ios.html">iOS support</a>
        <a href="privacy-policy.html" aria-current="page">iOS privacy</a>
      </nav>
    </div>
  </header>

  <main id="policy-content" class="container site-content reading-width" tabindex="-1">
    <!-- [02] Keep the revision and the most requested privacy choices close to the title. -->
    <div class="page-intro">
      <h1>{html.escape(document['title'])}</h1>
      <p class="muted">Last updated <time datetime="{document['revision']}">{html.escape(updated)}</time></p>
      <nav class="topic-links" aria-label="Privacy topics">
        <a href="#screen-time">Screen Time</a>
        <a href="#deletion">Delete your data</a>
        <a href="#contact">Contact</a>
      </nav>
    </div>
    <article class="card policy-copy">
      {body}
    </article>
  </main>

  <footer class="footer">
    <div class="container">
      <p class="muted">© 2026 Zurich University of Applied Sciences (ZHAW) · {html.escape(document['app_name'])}</p>
      <p><a href="mailto:{html.escape(document['contact_email'])}">Email the {html.escape(document['contact_name'])}</a></p>
      <p><a href="https://docs.github.com/en/site-policy/privacy-policies/github-general-privacy-statement">GitHub hosting privacy</a></p>
    </div>
  </footer>
</body>
</html>
'''
    swift_sections = []
    for section in sections:
        paragraphs = ',\n                '.join(swift_string(paragraph) for paragraph in section['paragraphs'])
        swift_sections.append(f'''        PrivacyPolicySection(
            id: {swift_string(section['id'])},
            title: {swift_string(section['title'])},
            paragraphs: [
                {paragraphs}
            ]
        )''')
    intro = ',\n        '.join(swift_string(paragraph) for paragraph in document['introduction'])
    source = SWIFT_LICENSE + f'''// [01] Generated from the reviewed policy in Configuration/PrivacyPolicyContent.json. Edit that source to update this local copy.
import Foundation

// [02] Stable section names keep the privacy page in a clear, predictable reading order.
struct PrivacyPolicySection: Identifiable {{
    let id: String
    let title: String
    let paragraphs: [String]
}}

// [03] Ship a local copy so privacy choices remain available without an internet connection.
enum PrivacyPolicyContent {{
    static let appName = {swift_string(document['app_name'])}
    static let title = {swift_string(document['title'])}
    static let revision = {swift_string(document['revision'])}
    static let updatedText = {swift_string('Last updated: ' + updated)}
    static let contactURL = URL(string: {swift_string('mailto:' + document['contact_email'])})!
    static let introduction = [
        {intro}
    ]
    static let sections = [
{',\n'.join(swift_sections)}
    ]
}}
'''
    generated = {
        ROOT / 'iosApp/PrivacyPolicyContent.swift': source,
    }
    if include_web:
        # [04] Both app layouts sit two folders below the repository. Keep one public policy beside the website,
        # rather than leaving an extra copy inside the app folder.
        public_docs = ROOT.parent.parent / 'docs'
        generated.update({
            public_docs / 'privacy-policy.md': markdown,
            public_docs / 'privacy-policy.html': web,
            public_docs / 'privacy-policy-content.json': json.dumps(document, ensure_ascii=False, indent=2) + '\n',
        })
    return generated


# [05] Reject incomplete policy details before writing any copy. Check mode reports old copies without replacing them.
def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--check', action='store_true', help='Verify the selected copies without rewriting them.')
    parser.add_argument('--include-web', action='store_true', help='Also generate or verify the HTML, Markdown and JSON policy copies in the repository website.')
    args = parser.parse_args()
    document = json.loads(CONTENT.read_text())
    if document['schema_version'] != 1:
        raise ValueError('Unsupported policy schema')
    ids = [section['id'] for section in document['sections']]
    if len(set(ids)) != len(ids) or not ids:
        raise ValueError('Policy sections need unique, stable IDs')
    if not document.get('contact_name', '').strip():
        raise ValueError('A public team contact name is required')
    if not document['contact_email'] or '@' not in document['contact_email']:
        raise ValueError('A real project contact is required')
    stale = []
    for path, content in outputs(document, include_web=args.include_web).items():
        if args.check:
            if not path.is_file() or path.read_text() != content:
                # [06] Public pages live outside the app folder; report that path without changing any file.
                stale.append(os.path.relpath(path, ROOT))
        else:
            path.parent.mkdir(parents=True, exist_ok=True)
            path.write_text(content)
    if stale:
        print('Policy copies are out of date: ' + ', '.join(stale), file=sys.stderr)
        return 1
    print('Policy copies agree.' if args.check else 'Policy copies generated.')
    return 0


if __name__ == '__main__':
    raise SystemExit(main())
