"""Check public documentation links, images, anchors and language pairs offline."""
from html import unescape
from html.parser import HTMLParser
from pathlib import Path
import re
import sys
from urllib.parse import unquote, urlsplit

ROOT = Path(__file__).resolve().parents[1]
PAIRS = (
    ('README.en.md', 'README.md'),
    ('CONTRIBUTING.en.md', 'CONTRIBUTING.md'),
    ('docs/app.md', 'docs/app.zh-CN.md'),
    ('docs/android-release.md', 'docs/android-release.zh-CN.md'),
    ('docs/legal.md', 'docs/legal.zh-CN.md'),
    ('docs/distribution/README.en.md', 'docs/distribution/README.md'),
    ('docs/architecture.md', 'docs/architecture.zh-CN.md'),
    ('docs/pose.md', 'docs/pose.zh-CN.md'),
    ('docs/ai-development.md', 'docs/ai-development.zh-CN.md'),
    ('docs/ios-setup.md', 'docs/ios-setup.zh-CN.md'),
    ('docs/community-governance.md', 'docs/community-governance.zh-CN.md'),
    ('docs/release-checklist.md', 'docs/release-checklist.zh-CN.md'),
    ('policies/README.en.md', 'policies/README.md'),
)


def without_code(content):
    """Ignore fenced examples; inline code can be part of a real heading."""
    return re.sub(r'^([\x60~]{3,})[^\n]*\n.*?^\1\s*$', '', content,
                  flags=re.MULTILINE | re.DOTALL)


class HtmlLinks(HTMLParser):
    def __init__(self):
        super().__init__()
        self.targets = []

    def handle_starttag(self, tag, attrs):
        for key, value in attrs:
            if key in ('src', 'href') and value:
                self.targets.append(value)


def links(content):
    content = without_code(content)
    targets = re.findall(r'!?\[[^\]\n]*\]\(\s*<?([^\s)>]+)>?(?:\s+"[^"]*")?\s*\)', content)
    targets += re.findall(r'^\s*\[[^\]]+\]:\s*<?([^\s>]+)>?', content, re.MULTILINE)
    parser = HtmlLinks()
    parser.feed(content)
    return targets + parser.targets


def heading_ids(content):
    """Support GitHub-style IDs for the simple ATX headings used in these docs."""
    seen = {}
    ids = set()
    for heading in re.findall(r'^#{1,6}\s+(.+?)\s*#*\s*$', without_code(content), re.MULTILINE):
        heading = re.sub(r'<[^>]+>', '', heading)
        slug = re.sub(r'[^\w\-\s]', '', unescape(heading).lower()).replace(' ', '-')
        count = seen.get(slug, 0)
        ids.add(f'{slug}-{count}' if count else slug)
        seen[slug] = count + 1
    return ids


def check_document(path, root):
    errors = []
    for target in links(path.read_text(encoding="utf-8")):
        url = urlsplit(unescape(target))
        if url.scheme or url.netloc:
            continue
        destination = (path.parent / unquote(url.path)).resolve() if url.path else path.resolve()
        try:
            destination.relative_to(root.resolve())
        except ValueError:
            errors.append(f'{path.relative_to(root)}: link escapes repository: {target}')
            continue
        if not destination.exists():
            errors.append(f'{path.relative_to(root)}: missing target: {target}')
        elif url.fragment and destination.suffix == '.md':
            if unquote(url.fragment) not in heading_ids(destination.read_text(encoding="utf-8")):
                errors.append(f'{path.relative_to(root)}: missing heading: {target}')
    return errors


def main():
    documents = sorted(set(ROOT.glob('*.md')) | set((ROOT / 'docs').glob('*.md'))
                       | set((ROOT / 'docs/distribution').rglob('*.md'))
                       | set((ROOT / 'policies').glob('*.md'))
                       | set((ROOT / '.github').glob('*.md'))
                       | set((ROOT / '.agents/skills').rglob('*.md'))
                       | set((ROOT / '.claude/commands').rglob('*.md')))
    errors = [error for path in documents for error in check_document(path, ROOT)]
    if not (ROOT / 'README.md').is_file():
        errors.append('Missing developer README: README.md')
    for pair in PAIRS:
        for name in pair:
            if not (ROOT / name).is_file():
                errors.append(f'Missing language counterpart: {name}')
    if errors:
        print('\n'.join(errors), file=sys.stderr)
        return 1
    print(f'Checked {len(documents)} public documents and {len(PAIRS)} language pairs; local links and images resolve.')
    return 0


if __name__ == '__main__':
    raise SystemExit(main())
