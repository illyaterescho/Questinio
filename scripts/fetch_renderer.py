"""Fetch official npm assets once; the application renderer is fully offline."""
import io, json, tarfile, urllib.request
from pathlib import Path
root = Path(__file__).resolve().parents[1] / 'Resources' / 'AnswerRenderer'
versions = {}
for package in ['katex', 'marked', 'dompurify']:
    metadata = json.load(urllib.request.urlopen('https://registry.npmjs.org/' + package + '/latest'))
    versions[package] = metadata['version']
    archive = tarfile.open(fileobj=io.BytesIO(urllib.request.urlopen(metadata['dist']['tarball']).read()), mode='r:gz')
    names = ['package/dist/katex.min.js', 'package/dist/katex.min.css', 'package/dist/contrib/auto-render.min.js'] if package == 'katex' else ['package/lib/marked.umd.js', 'package/dist/purify.min.js']
    for item in archive.getmembers():
        if item.name not in names and not (package == 'katex' and item.name.startswith('package/dist/fonts/') and item.name.endswith('.woff2')) and not item.name.endswith('/LICENSE') and not item.name.endswith('/LICENSE.txt'):
            continue
        if not item.isfile(): continue
        relative = Path('fonts') / Path(item.name).name if '/fonts/' in item.name else Path(package + '-LICENSE.txt') if 'LICENSE' in item.name else Path(item.name).name
        path = root / relative; path.parent.mkdir(parents=True, exist_ok=True)
        path.write_bytes(archive.extractfile(item).read())
(root / 'versions.json').write_text(json.dumps(versions, indent=2))
print(versions)
